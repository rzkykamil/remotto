package oswin

import (
	"context"
	"errors"
	"reflect"
	"strings"
	"testing"

	"remotto/agent/internal/control"
)

// These tests never call NewPower's production run func or the real
// shutdown.exe. They inject fake run and sleep funcs, so no power command
// reaches the OS.

func TestShutdownArgs(t *testing.T) {
	tests := []struct {
		name   string
		action control.PowerAction
		want   []string
		wantOK bool
	}{
		{name: "shutdown", action: control.PowerShutdown, want: []string{"/s", "/t", "0"}, wantOK: true},
		{name: "restart", action: control.PowerRestart, want: []string{"/r", "/t", "0"}, wantOK: true},
		{name: "sleep has no shutdown args", action: control.PowerSleep, want: nil, wantOK: false},
		{name: "unknown", action: control.PowerAction("hibernate"), want: nil, wantOK: false},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, ok := shutdownArgs(tt.action)
			if ok != tt.wantOK || !reflect.DeepEqual(got, tt.want) {
				t.Fatalf("shutdownArgs(%q) = (%v, %v), want (%v, %v)", tt.action, got, ok, tt.want, tt.wantOK)
			}
		})
	}
}

// TestShutdownArgsNeverForce covers R-15: shutdown and restart must never pass
// /f, so unsaved work in other apps is not force-closed.
func TestShutdownArgsNeverForce(t *testing.T) {
	for _, a := range []control.PowerAction{control.PowerShutdown, control.PowerRestart} {
		args, ok := shutdownArgs(a)
		if !ok {
			t.Fatalf("shutdownArgs(%q) not ok", a)
		}
		for _, arg := range args {
			if strings.EqualFold(arg, "/f") || strings.EqualFold(arg, "-f") {
				t.Errorf("shutdownArgs(%q) contains force flag %q, R-15 forbids it", a, arg)
			}
		}
	}
}

func TestPowerExecute(t *testing.T) {
	tests := []struct {
		name       string
		action     control.PowerAction
		runErr     error
		wantArgs   []string
		wantRun    bool
		wantSleep  bool
		wantErr    bool
		wantSecret bool
	}{
		{
			name:     "shutdown passes /s /t 0",
			action:   control.PowerShutdown,
			wantArgs: []string{"/s", "/t", "0"},
			wantRun:  true,
		},
		{
			name:     "restart passes /r /t 0",
			action:   control.PowerRestart,
			wantArgs: []string{"/r", "/t", "0"},
			wantRun:  true,
		},
		{
			name:      "sleep calls sleep, not run",
			action:    control.PowerSleep,
			wantSleep: true,
		},
		{
			name:     "run error is wrapped as ErrPower",
			action:   control.PowerShutdown,
			runErr:   errors.New("secret os detail"),
			wantArgs: []string{"/s", "/t", "0"},
			wantRun:  true,
			wantErr:  true,
		},
		{
			name:    "unknown action is rejected without run",
			action:  control.PowerAction("hibernate"),
			wantErr: true,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ran, slept := false, false
			var gotArgs []string
			p := &Power{
				run: func(_ context.Context, args []string) error {
					ran = true
					gotArgs = args
					return tt.runErr
				},
				sleep: func(context.Context) error {
					slept = true
					return nil
				},
			}

			err := p.Execute(context.Background(), tt.action)

			if ran != tt.wantRun {
				t.Fatalf("run called = %v, want %v", ran, tt.wantRun)
			}
			if slept != tt.wantSleep {
				t.Fatalf("sleep called = %v, want %v", slept, tt.wantSleep)
			}
			if tt.wantRun && !reflect.DeepEqual(gotArgs, tt.wantArgs) {
				t.Fatalf("run args = %v, want %v", gotArgs, tt.wantArgs)
			}
			if !tt.wantErr {
				if err != nil {
					t.Fatalf("Execute() error = %v, want nil", err)
				}
				return
			}
			if !errors.Is(err, control.ErrPower) {
				t.Fatalf("errors.Is(err, ErrPower) = false, err = %v", err)
			}
		})
	}
}

func TestPowerExecuteErrorHidesOSDetail(t *testing.T) {
	cause := errors.New("secret os detail")
	p := &Power{
		run:   func(context.Context, []string) error { return control.Wrap(control.ErrPower, cause) },
		sleep: func(context.Context) error { return nil },
	}

	err := p.Execute(context.Background(), control.PowerRestart)

	if msg := err.Error(); msg != control.ErrPower.Error() {
		t.Fatalf("err.Error() = %q, want %q", msg, control.ErrPower.Error())
	}
	if !errors.Is(err, cause) {
		t.Fatalf("errors.Is(err, cause) = false, want true; err = %v", err)
	}
}

func TestPowerExecuteSleepErrorIsWrapped(t *testing.T) {
	p := &Power{
		run:   func(context.Context, []string) error { t.Fatal("run must not be called for sleep"); return nil },
		sleep: func(context.Context) error { return control.Wrap(control.ErrPower, errors.New("sleep failed")) },
	}

	err := p.Execute(context.Background(), control.PowerSleep)

	if !errors.Is(err, control.ErrPower) {
		t.Fatalf("errors.Is(err, ErrPower) = false, err = %v", err)
	}
}

// TestNewPowerWiresSleep checks that NewPower fills the sleep path without
// calling it. Calling it would reach the real OS, so this test only inspects
// the field.
func TestNewPowerWiresSleep(t *testing.T) {
	p := NewPower()

	if p.sleep == nil {
		t.Fatal("NewPower().sleep is nil, want the production sleep path")
	}
	if p.run == nil {
		t.Fatal("NewPower().run is nil, want the production shutdown runner")
	}
}
