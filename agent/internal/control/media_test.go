package control_test

import (
	"context"
	"errors"
	"sync"
	"testing"
	"time"

	"remotto/agent/internal/control"
	"remotto/agent/internal/oscontrol/fake"
)

func TestMediaActionValid(t *testing.T) {
	tests := []struct {
		action control.MediaAction
		want   bool
	}{
		{control.MediaPlayPause, true},
		{control.MediaNext, true},
		{control.MediaPrev, true},
		{control.MediaAction("volume-up"), false},
		{control.MediaAction(""), false},
	}
	for _, tt := range tests {
		t.Run(string(tt.action), func(t *testing.T) {
			if got := tt.action.Valid(); got != tt.want {
				t.Fatalf("Valid() = %v, want %v", got, tt.want)
			}
		})
	}
}

// FR-2.1: each media action reaches the OS controller exactly once.
func TestMediaServiceDoSendsOneCallPerAction(t *testing.T) {
	tests := []control.MediaAction{control.MediaPlayPause, control.MediaNext, control.MediaPrev}
	for _, action := range tests {
		t.Run(string(action), func(t *testing.T) {
			m := &fake.Media{}
			svc := control.NewMediaService(m)

			if err := svc.Do(context.Background(), action); err != nil {
				t.Fatalf("Do(%q) error = %v, want nil", action, err)
			}
			got := m.Calls()
			if len(got) != 1 || got[0] != action {
				t.Fatalf("Calls() = %v, want [%q]", got, action)
			}
		})
	}
}

func TestMediaServiceDoRejectsInvalidAction(t *testing.T) {
	tests := []control.MediaAction{control.MediaAction("volume-up"), control.MediaAction("")}
	for _, action := range tests {
		t.Run(string(action), func(t *testing.T) {
			m := &fake.Media{}
			svc := control.NewMediaService(m)

			err := svc.Do(context.Background(), action)
			if !errors.Is(err, control.ErrInvalidAction) {
				t.Fatalf("Do(%q) error = %v, want ErrInvalidAction", action, err)
			}
			if calls := m.Calls(); len(calls) != 0 {
				t.Fatalf("Calls() = %v, want none", calls)
			}
		})
	}
}

func TestMediaServiceDoWrapsOSError(t *testing.T) {
	cause := errors.New("SendInput 0x5 access denied")
	m := &fake.Media{}
	m.SetErr(cause)
	svc := control.NewMediaService(m)

	err := svc.Do(context.Background(), control.MediaPlayPause)
	if !errors.Is(err, control.ErrMedia) {
		t.Fatalf("errors.Is(err, ErrMedia) = false, err = %v", err)
	}
	if err.Error() != control.ErrMedia.Error() {
		t.Fatalf("err.Error() = %q, want %q", err.Error(), control.ErrMedia.Error())
	}
	if got := errors.Unwrap(err); got != cause {
		t.Fatalf("errors.Unwrap(err) = %v, want original cause", got)
	}
}

func TestMediaServiceDoMapsUnsupportedToMediaError(t *testing.T) {
	m := &fake.Media{}
	m.SetErr(control.ErrUnsupported)
	svc := control.NewMediaService(m)

	err := svc.Do(context.Background(), control.MediaNext)
	if !errors.Is(err, control.ErrMedia) {
		t.Fatalf("errors.Is(err, ErrMedia) = false, err = %v", err)
	}
	if !errors.Is(err, control.ErrUnsupported) {
		t.Fatalf("errors.Is(err, ErrUnsupported) = false, want cause kept for logging")
	}
}

func TestMediaServiceDoReturnsMediaErrorPassThrough(t *testing.T) {
	inner := control.Wrap(control.ErrMedia, errors.New("inner"))
	m := &fake.Media{}
	m.SetErr(inner)
	svc := control.NewMediaService(m)

	err := svc.Do(context.Background(), control.MediaPrev)
	if err != inner {
		t.Fatalf("Do() error = %v, want the same ErrMedia error returned as-is", err)
	}
}

func TestMediaServiceNilControllerFailsClosed(t *testing.T) {
	svc := control.NewMediaService(nil)

	err := svc.Do(context.Background(), control.MediaPlayPause)
	if !errors.Is(err, control.ErrMedia) {
		t.Fatalf("errors.Is(err, ErrMedia) = false, err = %v", err)
	}
	if !errors.Is(err, control.ErrUnsupported) {
		t.Fatalf("errors.Is(err, ErrUnsupported) = false, want true")
	}
}

func TestMediaServiceConcurrentCallsSerialized(t *testing.T) {
	const n = 20
	m := &fake.Media{}
	svc := control.NewMediaService(m)

	var wg sync.WaitGroup
	errs := make(chan error, n)
	for range n {
		wg.Go(func() {
			errs <- svc.Do(context.Background(), control.MediaNext)
		})
	}
	wg.Wait()
	close(errs)

	for err := range errs {
		if err != nil {
			t.Fatalf("Do() error = %v, want nil", err)
		}
	}
	if got := len(m.Calls()); got != n {
		t.Fatalf("len(Calls()) = %d, want %d", got, n)
	}
}

func TestMediaServiceDoIsFast(t *testing.T) {
	svc := control.NewMediaService(&fake.Media{})

	start := time.Now()
	if err := svc.Do(context.Background(), control.MediaPlayPause); err != nil {
		t.Fatalf("Do() error = %v, want nil", err)
	}
	if elapsed := time.Since(start); elapsed > 100*time.Millisecond {
		t.Fatalf("Do() took %v, want < 100ms", elapsed)
	}
}
