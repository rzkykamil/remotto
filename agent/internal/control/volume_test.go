package control_test

import (
	"context"
	"errors"
	"reflect"
	"sync"
	"testing"

	"remotto/agent/internal/control"
	"remotto/agent/internal/oscontrol/fake"
)

// BR-3: levels outside 0-100 are rejected before the OS is touched.
func TestBR3_SetLevelRejectsOutOfRange(t *testing.T) {
	tests := []int{-1, 101, 1000, -1000}
	for _, level := range tests {
		t.Run(itoa(level), func(t *testing.T) {
			a := fake.NewAudio(35, true)
			svc := control.NewVolumeService(a)

			_, err := svc.SetLevel(context.Background(), level)
			if !errors.Is(err, control.ErrInvalidLevel) {
				t.Fatalf("SetLevel(%d) error = %v, want ErrInvalidLevel", level, err)
			}
			if calls := a.SetLevelCalls(); len(calls) != 0 {
				t.Fatalf("SetLevelCalls() = %v, want none", calls)
			}
			v, _ := a.Volume(context.Background())
			if v != (control.Volume{Level: 35, Muted: true}) {
				t.Fatalf("state = %+v, want unchanged {35 true}", v)
			}
		})
	}
}

func TestBR3_SetLevelAcceptsBounds(t *testing.T) {
	for _, level := range []int{0, 100} {
		t.Run(itoa(level), func(t *testing.T) {
			svc := control.NewVolumeService(fake.NewAudio(35, false))

			v, err := svc.SetLevel(context.Background(), level)
			if err != nil {
				t.Fatalf("SetLevel(%d) error = %v, want nil", level, err)
			}
			if v.Level != level {
				t.Fatalf("SetLevel(%d) level = %d, want %d", level, v.Level, level)
			}
		})
	}
}

// BR-15: setting a level always unmutes.
func TestBR15_SetLevelUnmutes(t *testing.T) {
	a := fake.NewAudio(35, true)
	svc := control.NewVolumeService(a)

	v, err := svc.SetLevel(context.Background(), 50)
	if err != nil {
		t.Fatalf("SetLevel() error = %v, want nil", err)
	}
	if v != (control.Volume{Level: 50, Muted: false}) {
		t.Fatalf("SetLevel() = %+v, want {50 false}", v)
	}
}

// BR-16: up and down move by VolumeStep and clamp at the limits.
func TestBR16_StepUpDown(t *testing.T) {
	tests := []struct {
		name  string
		start int
		up    bool
		want  int
	}{
		{"up 35 to 40", 35, true, 40},
		{"down 35 to 30", 35, false, 30},
		{"up 98 clamps to 100", 98, true, 100},
		{"down 2 clamps to 0", 2, false, 0},
		{"up at 100 stays 100", 100, true, 100},
		{"down at 0 stays 0", 0, false, 0},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			a := fake.NewAudio(tt.start, false)
			svc := control.NewVolumeService(a)

			var (
				v   control.Volume
				err error
			)
			if tt.up {
				v, err = svc.Up(context.Background())
			} else {
				v, err = svc.Down(context.Background())
			}
			if err != nil {
				t.Fatalf("step error = %v, want nil", err)
			}
			if v.Level != tt.want {
				t.Fatalf("level = %d, want %d", v.Level, tt.want)
			}
		})
	}
}

// BR-16: a step at a limit still succeeds and still unmutes.
func TestBR16_StepAtLimitStillUnmutes(t *testing.T) {
	tests := []struct {
		name  string
		start int
		up    bool
		want  int
	}{
		{"up at 100 muted", 100, true, 100},
		{"down at 0 muted", 0, false, 0},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			a := fake.NewAudio(tt.start, true)
			svc := control.NewVolumeService(a)

			var (
				v   control.Volume
				err error
			)
			if tt.up {
				v, err = svc.Up(context.Background())
			} else {
				v, err = svc.Down(context.Background())
			}
			if err != nil {
				t.Fatalf("step error = %v, want nil", err)
			}
			if v != (control.Volume{Level: tt.want, Muted: false}) {
				t.Fatalf("step = %+v, want {%d false}", v, tt.want)
			}
		})
	}
}

// Concurrent steps must not lose updates: 10 ups from 0 end at 50.
func TestBR16_ConcurrentStepsSerialized(t *testing.T) {
	const n = 10
	a := fake.NewAudio(0, false)
	svc := control.NewVolumeService(a)

	var wg sync.WaitGroup
	errs := make(chan error, n)
	for range n {
		wg.Go(func() {
			_, err := svc.Up(context.Background())
			errs <- err
		})
	}
	wg.Wait()
	close(errs)

	for err := range errs {
		if err != nil {
			t.Fatalf("Up() error = %v, want nil", err)
		}
	}
	v, _ := a.Volume(context.Background())
	if v.Level != n*control.VolumeStep {
		t.Fatalf("level = %d, want %d", v.Level, n*control.VolumeStep)
	}
}

func TestSetMutedKeepsLevel(t *testing.T) {
	tests := []struct {
		name  string
		muted bool
	}{
		{"mute", true},
		{"unmute", false},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			a := fake.NewAudio(35, !tt.muted)
			svc := control.NewVolumeService(a)

			v, err := svc.SetMuted(context.Background(), tt.muted)
			if err != nil {
				t.Fatalf("SetMuted() error = %v, want nil", err)
			}
			if v != (control.Volume{Level: 35, Muted: tt.muted}) {
				t.Fatalf("SetMuted() = %+v, want {35 %v}", v, tt.muted)
			}
			if calls := a.SetLevelCalls(); len(calls) != 0 {
				t.Fatalf("SetLevelCalls() = %v, want none", calls)
			}
		})
	}
}

func TestGetReturnsOSVolume(t *testing.T) {
	svc := control.NewVolumeService(fake.NewAudio(42, true))

	v, err := svc.Get(context.Background())
	if err != nil {
		t.Fatalf("Get() error = %v, want nil", err)
	}
	if v != (control.Volume{Level: 42, Muted: true}) {
		t.Fatalf("Get() = %+v, want {42 true}", v)
	}
}

func TestOSErrorWrapsAsAudioError(t *testing.T) {
	cause := errors.New("COM 0x8007 device gone")
	a := fake.NewAudio(35, false)
	a.SetErr(cause)
	svc := control.NewVolumeService(a)
	ctx := context.Background()

	calls := map[string]func() error{
		"Get":      func() error { _, err := svc.Get(ctx); return err },
		"SetLevel": func() error { _, err := svc.SetLevel(ctx, 50); return err },
		"Up":       func() error { _, err := svc.Up(ctx); return err },
		"Down":     func() error { _, err := svc.Down(ctx); return err },
		"SetMuted": func() error { _, err := svc.SetMuted(ctx, true); return err },
	}
	for name, call := range calls {
		t.Run(name, func(t *testing.T) {
			err := call()
			if !errors.Is(err, control.ErrAudio) {
				t.Fatalf("errors.Is(err, ErrAudio) = false, err = %v", err)
			}
			if !errors.Is(err, cause) {
				t.Fatalf("errors.Is(err, cause) = false, want cause kept for logging")
			}
			if err.Error() != control.ErrAudio.Error() {
				t.Fatalf("err.Error() = %q, want %q", err.Error(), control.ErrAudio.Error())
			}
		})
	}
}

func TestNilControllerFailsClosed(t *testing.T) {
	svc := control.NewVolumeService(nil)
	ctx := context.Background()

	calls := map[string]func() error{
		"Get":      func() error { _, err := svc.Get(ctx); return err },
		"SetLevel": func() error { _, err := svc.SetLevel(ctx, 50); return err },
		"Up":       func() error { _, err := svc.Up(ctx); return err },
		"Down":     func() error { _, err := svc.Down(ctx); return err },
		"SetMuted": func() error { _, err := svc.SetMuted(ctx, true); return err },
	}
	for name, call := range calls {
		t.Run(name, func(t *testing.T) {
			err := call()
			if !errors.Is(err, control.ErrAudio) {
				t.Fatalf("errors.Is(err, ErrAudio) = false, err = %v", err)
			}
			if !errors.Is(err, control.ErrUnsupported) {
				t.Fatalf("errors.Is(err, ErrUnsupported) = false, want true")
			}
		})
	}
}

// A cancelled context fails before the OS is touched.
func TestCancelledContextDoesNotTouchOS(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	cancel()

	a := fake.NewAudio(35, false)
	svc := control.NewVolumeService(a)

	calls := map[string]func() error{
		"Get":      func() error { _, err := svc.Get(ctx); return err },
		"SetLevel": func() error { _, err := svc.SetLevel(ctx, 50); return err },
		"Up":       func() error { _, err := svc.Up(ctx); return err },
		"Down":     func() error { _, err := svc.Down(ctx); return err },
		"SetMuted": func() error { _, err := svc.SetMuted(ctx, true); return err },
	}
	for name, call := range calls {
		t.Run(name, func(t *testing.T) {
			if err := call(); !errors.Is(err, control.ErrAudio) {
				t.Fatalf("errors.Is(err, ErrAudio) = false, err = %v", err)
			}
		})
	}

	if calls := a.SetLevelCalls(); len(calls) != 0 {
		t.Fatalf("SetLevelCalls() = %v, want none", calls)
	}
	v, _ := a.Volume(context.Background())
	if v != (control.Volume{Level: 35, Muted: false}) {
		t.Fatalf("state = %+v, want unchanged {35 false}", v)
	}
}

// callPath runs one of the three level-changing paths from level 35:
// SetLevel(50), Up (40) or Down (30).
func callPath(svc *control.VolumeService, name string) (control.Volume, error) {
	ctx := context.Background()
	switch name {
	case "SetLevel":
		return svc.SetLevel(ctx, 50)
	case "Up":
		return svc.Up(ctx)
	case "Down":
		return svc.Down(ctx)
	}
	panic("unknown path " + name)
}

// wantLevel is the level each path must reach from 35.
var wantLevel = map[string]int{"SetLevel": 50, "Up": 40, "Down": 30}

// BR-15: an unmuted device is not unmuted again by a level change.
func TestBR15_PathsSkipUnmuteWhenNotMuted(t *testing.T) {
	for _, name := range []string{"SetLevel", "Up", "Down"} {
		t.Run(name, func(t *testing.T) {
			a := fake.NewAudio(35, false)
			svc := control.NewVolumeService(a)

			v, err := callPath(svc, name)
			if err != nil {
				t.Fatalf("%s error = %v, want nil", name, err)
			}
			if calls := a.SetMutedCalls(); len(calls) != 0 {
				t.Fatalf("SetMutedCalls() = %v, want none", calls)
			}
			if v != (control.Volume{Level: wantLevel[name], Muted: false}) {
				t.Fatalf("%s = %+v, want {%d false}", name, v, wantLevel[name])
			}
		})
	}
}

// BR-15: a muted device is unmuted by a level change.
func TestBR15_PathsUnmuteWhenMuted(t *testing.T) {
	for _, name := range []string{"SetLevel", "Up", "Down"} {
		t.Run(name, func(t *testing.T) {
			a := fake.NewAudio(35, true)
			svc := control.NewVolumeService(a)

			v, err := callPath(svc, name)
			if err != nil {
				t.Fatalf("%s error = %v, want nil", name, err)
			}
			if got, want := a.SetMutedCalls(), []bool{false}; !reflect.DeepEqual(got, want) {
				t.Fatalf("SetMutedCalls() = %v, want %v", got, want)
			}
			if v != (control.Volume{Level: wantLevel[name], Muted: false}) {
				t.Fatalf("%s = %+v, want {%d false}", name, v, wantLevel[name])
			}
		})
	}
}

// A broken mute write must not block level changes on an unmuted device.
func TestPathsSucceedWhenMuteWriteBrokenAndNotMuted(t *testing.T) {
	for _, name := range []string{"SetLevel", "Up", "Down"} {
		t.Run(name, func(t *testing.T) {
			a := fake.NewAudio(35, false)
			a.SetMuteErr(errors.New("Incorrect function."))
			svc := control.NewVolumeService(a)

			v, err := callPath(svc, name)
			if err != nil {
				t.Fatalf("%s error = %v, want nil", name, err)
			}
			if v.Level != wantLevel[name] {
				t.Fatalf("%s level = %d, want %d", name, v.Level, wantLevel[name])
			}
			if calls := a.SetMutedCalls(); len(calls) != 0 {
				t.Fatalf("SetMutedCalls() = %v, want none", calls)
			}
		})
	}
}

// An unmute failure on a muted device is returned as ErrAudio, keeping the cause.
// The level was already written before the failure.
func TestPathsFailWhenUnmuteFailsAndMuted(t *testing.T) {
	for _, name := range []string{"SetLevel", "Up", "Down"} {
		t.Run(name, func(t *testing.T) {
			cause := errors.New("Incorrect function.")
			a := fake.NewAudio(35, true)
			a.SetMuteErr(cause)
			svc := control.NewVolumeService(a)

			_, err := callPath(svc, name)
			if !errors.Is(err, control.ErrAudio) {
				t.Fatalf("errors.Is(err, ErrAudio) = false, err = %v", err)
			}
			if !errors.Is(err, cause) {
				t.Fatalf("errors.Is(err, cause) = false, want cause kept for logging")
			}
			if err.Error() != control.ErrAudio.Error() {
				t.Fatalf("err.Error() = %q, want %q", err.Error(), control.ErrAudio.Error())
			}
			if got := a.SetLevelCalls(); len(got) != 1 || got[0] != wantLevel[name] {
				t.Fatalf("SetLevelCalls() = %v, want [%d]", got, wantLevel[name])
			}
		})
	}
}

// The public SetMuted always reaches the OS, whatever the current state.
func TestSetMutedPublicCallsOSRegardlessOfState(t *testing.T) {
	ctx := context.Background()

	a := fake.NewAudio(35, false)
	if _, err := control.NewVolumeService(a).SetMuted(ctx, true); err != nil {
		t.Fatalf("SetMuted(true) error = %v, want nil", err)
	}
	if got, want := a.SetMutedCalls(), []bool{true}; !reflect.DeepEqual(got, want) {
		t.Fatalf("SetMuted(true) on unmuted: SetMutedCalls() = %v, want %v", got, want)
	}

	b := fake.NewAudio(35, false)
	if _, err := control.NewVolumeService(b).SetMuted(ctx, false); err != nil {
		t.Fatalf("SetMuted(false) error = %v, want nil", err)
	}
	if got, want := b.SetMutedCalls(), []bool{false}; !reflect.DeepEqual(got, want) {
		t.Fatalf("SetMuted(false) on unmuted: SetMutedCalls() = %v, want %v", got, want)
	}
}

// itoa avoids importing strconv for subtest names.
func itoa(n int) string {
	if n == 0 {
		return "0"
	}
	neg := n < 0
	if neg {
		n = -n
	}
	var b []byte
	for n > 0 {
		b = append([]byte{byte('0' + n%10)}, b...)
		n /= 10
	}
	if neg {
		b = append([]byte{'-'}, b...)
	}
	return string(b)
}
