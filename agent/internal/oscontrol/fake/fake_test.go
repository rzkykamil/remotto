package fake

import (
	"context"
	"errors"
	"reflect"
	"sync"
	"testing"

	"remotto/agent/internal/control"
)

var errBoom = errors.New("boom")

func TestMediaRecordsCallsInOrder(t *testing.T) {
	tests := []struct {
		name    string
		actions []control.MediaAction
	}{
		{"single", []control.MediaAction{control.MediaPlayPause}},
		{"sequence", []control.MediaAction{control.MediaNext, control.MediaPrev, control.MediaPlayPause}},
		{"none", nil},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			m := &Media{}
			for _, a := range tt.actions {
				if err := m.Send(context.Background(), a); err != nil {
					t.Fatalf("Send(%q) error = %v, want nil", a, err)
				}
			}
			if got := m.Calls(); !reflect.DeepEqual(got, tt.actions) {
				t.Fatalf("Calls() = %v, want %v", got, tt.actions)
			}
		})
	}
}

func TestMediaSetErrReturnsSameError(t *testing.T) {
	m := &Media{}
	m.SetErr(errBoom)
	err := m.Send(context.Background(), control.MediaNext)
	if !errors.Is(err, errBoom) {
		t.Fatalf("Send() error = %v, want errBoom", err)
	}
	if got := m.Calls(); len(got) != 1 || got[0] != control.MediaNext {
		t.Fatalf("Calls() = %v, want [next] (failed calls are still recorded)", got)
	}
	m.SetErr(nil)
	if err := m.Send(context.Background(), control.MediaPrev); err != nil {
		t.Fatalf("Send() after SetErr(nil) error = %v, want nil", err)
	}
}

func TestMediaCallsReturnsCopy(t *testing.T) {
	m := &Media{}
	_ = m.Send(context.Background(), control.MediaNext)
	got := m.Calls()
	got[0] = control.MediaPrev
	if again := m.Calls(); again[0] != control.MediaNext {
		t.Fatalf("Calls() shares storage with the fake: got %v", again)
	}
}

func TestAudioStoresStateAsGiven(t *testing.T) {
	ctx := context.Background()
	a := NewAudio(30, false)

	v, err := a.Volume(ctx)
	if err != nil || v != (control.Volume{Level: 30, Muted: false}) {
		t.Fatalf("Volume() = %+v, %v; want {30 false}, nil", v, err)
	}

	// No clamping and no unmute here: the fake stores exactly what it receives.
	if err := a.SetLevel(ctx, 150); err != nil {
		t.Fatalf("SetLevel(150) error = %v", err)
	}
	if err := a.SetMuted(ctx, true); err != nil {
		t.Fatalf("SetMuted(true) error = %v", err)
	}
	v, err = a.Volume(ctx)
	if err != nil || v != (control.Volume{Level: 150, Muted: true}) {
		t.Fatalf("Volume() = %+v, %v; want {150 true}, nil", v, err)
	}
	if got, want := a.SetLevelCalls(), []int{150}; !reflect.DeepEqual(got, want) {
		t.Fatalf("SetLevelCalls() = %v, want %v", got, want)
	}
}

func TestAudioSetErrFailsAllMethods(t *testing.T) {
	ctx := context.Background()
	a := NewAudio(40, false)
	a.SetErr(errBoom)

	if _, err := a.Volume(ctx); !errors.Is(err, errBoom) {
		t.Errorf("Volume() error = %v, want errBoom", err)
	}
	if err := a.SetLevel(ctx, 70); !errors.Is(err, errBoom) {
		t.Errorf("SetLevel() error = %v, want errBoom", err)
	}
	if err := a.SetMuted(ctx, true); !errors.Is(err, errBoom) {
		t.Errorf("SetMuted() error = %v, want errBoom", err)
	}

	a.SetErr(nil)
	v, err := a.Volume(ctx)
	if err != nil || v != (control.Volume{Level: 40, Muted: false}) {
		t.Fatalf("state changed while failing: Volume() = %+v, %v", v, err)
	}
}

func TestAudioSetLevelCallsCopy(t *testing.T) {
	a := NewAudio(0, false)
	_ = a.SetLevel(context.Background(), 10)
	got := a.SetLevelCalls()
	got[0] = 99
	if again := a.SetLevelCalls(); !reflect.DeepEqual(again, []int{10}) {
		t.Fatalf("SetLevelCalls() shares storage with the fake: got %v", again)
	}
}

func TestAudioSetMuteErrFailsOnlySetMuted(t *testing.T) {
	ctx := context.Background()
	a := NewAudio(40, true)
	a.SetMuteErr(errBoom)

	if err := a.SetMuted(ctx, false); !errors.Is(err, errBoom) {
		t.Fatalf("SetMuted() error = %v, want errBoom", err)
	}
	if err := a.SetLevel(ctx, 55); err != nil {
		t.Fatalf("SetLevel() error = %v, want nil", err)
	}
	v, err := a.Volume(ctx)
	if err != nil || v != (control.Volume{Level: 55, Muted: true}) {
		t.Fatalf("Volume() = %+v, %v; want {55 true}, nil", v, err)
	}

	a.SetMuteErr(nil)
	if err := a.SetMuted(ctx, false); err != nil {
		t.Fatalf("SetMuted() after SetMuteErr(nil) error = %v, want nil", err)
	}
}

func TestAudioSetMutedCallsRecordFailedAttempts(t *testing.T) {
	ctx := context.Background()
	a := NewAudio(40, true)
	a.SetMuteErr(errBoom)

	_ = a.SetMuted(ctx, false)
	a.SetMuteErr(nil)
	_ = a.SetMuted(ctx, true)

	if got, want := a.SetMutedCalls(), []bool{false, true}; !reflect.DeepEqual(got, want) {
		t.Fatalf("SetMutedCalls() = %v, want %v (failed attempts included)", got, want)
	}
	got := a.SetMutedCalls()
	got[0] = true
	if again := a.SetMutedCalls(); !reflect.DeepEqual(again, []bool{false, true}) {
		t.Fatalf("SetMutedCalls() shares storage with the fake: got %v", again)
	}
}

func TestPowerRecordsCallsWithoutRunning(t *testing.T) {
	p := &Power{}
	ctx := context.Background()
	for _, a := range []control.PowerAction{control.PowerSleep, control.PowerRestart, control.PowerShutdown} {
		if err := p.Execute(ctx, a); err != nil {
			t.Fatalf("Execute(%q) error = %v, want nil", a, err)
		}
	}
	want := []control.PowerAction{control.PowerSleep, control.PowerRestart, control.PowerShutdown}
	if got := p.Calls(); !reflect.DeepEqual(got, want) {
		t.Fatalf("Calls() = %v, want %v", got, want)
	}
}

func TestPowerSetErrReturnsSameError(t *testing.T) {
	p := &Power{}
	p.SetErr(errBoom)
	if err := p.Execute(context.Background(), control.PowerSleep); !errors.Is(err, errBoom) {
		t.Fatalf("Execute() error = %v, want errBoom", err)
	}
	if got := p.Calls(); len(got) != 1 || got[0] != control.PowerSleep {
		t.Fatalf("Calls() = %v, want [sleep]", got)
	}
}

// TestConcurrentCallsAreRecorded checks that concurrent use does not lose calls.
// Run with -race where CGO is available to also catch data races.
func TestConcurrentCallsAreRecorded(t *testing.T) {
	const workers, perWorker = 2, 100
	m := &Media{}
	a := NewAudio(0, false)
	ctx := context.Background()

	var wg sync.WaitGroup
	for range workers {
		wg.Go(func() {
			for i := range perWorker {
				_ = m.Send(ctx, control.MediaNext)
				_ = a.SetLevel(ctx, i%101)
			}
		})
	}
	wg.Wait()

	if got := len(m.Calls()); got != workers*perWorker {
		t.Fatalf("Media recorded %d calls, want %d", got, workers*perWorker)
	}
	if got := len(a.SetLevelCalls()); got != workers*perWorker {
		t.Fatalf("Audio recorded %d SetLevel calls, want %d", got, workers*perWorker)
	}
}
