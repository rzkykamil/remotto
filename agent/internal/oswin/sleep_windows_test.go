package oswin

import (
	"bytes"
	"context"
	"errors"
	"log/slog"
	"strings"
	"testing"
	"unsafe"

	"remotto/agent/internal/control"
)

// These tests never call newSleep's production funcs, GetPwrCapabilities,
// PostMessageW or SetSuspendState. Every OS call is replaced by a fake, so no
// power effect reaches the OS.

// TestSystemPowerCapabilitiesLayout checks the struct against winnt.h. AoAc is
// at offset 20. The task brief said 19, but the SDK order (FastSystemS4,
// Hiberboot, WakeAlarmPresent, AoAc) puts it at 20. On the development laptop,
// byte 20 of GetPwrCapabilities is 1 and byte 19 is 0. powercfg -a lists only
// S0 Low Power Idle, so AoAc must be TRUE there.
func TestSystemPowerCapabilitiesLayout(t *testing.T) {
	var c systemPowerCapabilities

	if got := unsafe.Sizeof(c); got != 76 {
		t.Errorf("Sizeof(systemPowerCapabilities) = %d, want 76", got)
	}
	if got := unsafe.Offsetof(c.SystemS3); got != 5 {
		t.Errorf("Offsetof(SystemS3) = %d, want 5", got)
	}
	if got := unsafe.Offsetof(c.AoAc); got != 20 {
		t.Errorf("Offsetof(AoAc) = %d, want 20", got)
	}
	if got := unsafe.Offsetof(c.BatteriesScale); got != 32 {
		t.Errorf("Offsetof(BatteriesScale) = %d, want 32", got)
	}
	if got := unsafe.Offsetof(c.AcOnLineWake); got != 56 {
		t.Errorf("Offsetof(AcOnLineWake) = %d, want 56", got)
	}
}

func TestChooseSleepPath(t *testing.T) {
	tests := []struct {
		name     string
		caps     sleepCaps
		wantPath sleepPath
		wantErr  bool
	}{
		{name: "AoAc only uses monitor off", caps: sleepCaps{AoAc: true}, wantPath: pathMonitorOff},
		{name: "S3 only uses suspend", caps: sleepCaps{S3: true}, wantPath: pathSuspend},
		{name: "both prefer monitor off", caps: sleepCaps{AoAc: true, S3: true}, wantPath: pathMonitorOff},
		{name: "neither is an error", caps: sleepCaps{}, wantErr: true},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := chooseSleepPath(tt.caps)
			if tt.wantErr {
				if !errors.Is(err, control.ErrPower) {
					t.Fatalf("errors.Is(err, ErrPower) = false, err = %v", err)
				}
				if !errors.Is(err, errNoSleepSupport) {
					t.Fatalf("errors.Is(err, errNoSleepSupport) = false, err = %v", err)
				}
				return
			}
			if err != nil {
				t.Fatalf("chooseSleepPath(%+v) error = %v", tt.caps, err)
			}
			if got != tt.wantPath {
				t.Fatalf("chooseSleepPath(%+v) = %q, want %q", tt.caps, got, tt.wantPath)
			}
		})
	}
}

// fakeSleep builds a sleepImpl with fake OS calls. It records which path ran.
type fakeSleep struct {
	caps       []sleepCaps // one entry per readCaps call, last one repeats
	capsErr    error
	monitorErr error
	suspendErr error

	readCalls   int
	monitorRuns int
	suspendRuns int
}

func (f *fakeSleep) impl(logger *slog.Logger) *sleepImpl {
	return &sleepImpl{
		readCaps: func() (sleepCaps, error) {
			f.readCalls++
			if f.capsErr != nil {
				return sleepCaps{}, f.capsErr
			}
			i := f.readCalls - 1
			if i >= len(f.caps) {
				i = len(f.caps) - 1
			}
			return f.caps[i], nil
		},
		monitorOff: func(context.Context) error {
			f.monitorRuns++
			return f.monitorErr
		},
		suspend: func(context.Context) error {
			f.suspendRuns++
			return f.suspendErr
		},
		logger: logger,
	}
}

func TestSleepImplChoosesPath(t *testing.T) {
	tests := []struct {
		name        string
		caps        sleepCaps
		wantMonitor int
		wantSuspend int
	}{
		{name: "AoAc calls monitor off only", caps: sleepCaps{AoAc: true}, wantMonitor: 1},
		{name: "S3 calls suspend only", caps: sleepCaps{S3: true}, wantSuspend: 1},
		{name: "both calls monitor off only", caps: sleepCaps{AoAc: true, S3: true}, wantMonitor: 1},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			f := &fakeSleep{caps: []sleepCaps{tt.caps}}
			err := f.impl(discardLogger()).run(context.Background())
			if err != nil {
				t.Fatalf("run() error = %v", err)
			}
			if f.monitorRuns != tt.wantMonitor || f.suspendRuns != tt.wantSuspend {
				t.Fatalf("monitorOff=%d suspend=%d, want %d and %d",
					f.monitorRuns, f.suspendRuns, tt.wantMonitor, tt.wantSuspend)
			}
		})
	}
}

// TestSleepImplReadsCapsEveryCall checks that capabilities are read at each
// call, not cached at construction.
func TestSleepImplReadsCapsEveryCall(t *testing.T) {
	f := &fakeSleep{caps: []sleepCaps{{S3: true}, {AoAc: true}}}
	s := f.impl(discardLogger())

	if err := s.run(context.Background()); err != nil {
		t.Fatalf("first run() error = %v", err)
	}
	if err := s.run(context.Background()); err != nil {
		t.Fatalf("second run() error = %v", err)
	}
	if f.readCalls != 2 {
		t.Fatalf("readCaps calls = %d, want 2", f.readCalls)
	}
	if f.suspendRuns != 1 || f.monitorRuns != 1 {
		t.Fatalf("suspend=%d monitorOff=%d, want 1 and 1", f.suspendRuns, f.monitorRuns)
	}
}

func TestSleepImplErrors(t *testing.T) {
	secret := errors.New("secret os detail")
	tests := []struct {
		name     string
		f        fakeSleep
		wantMon  int
		wantSusp int
	}{
		{name: "readCaps error", f: fakeSleep{capsErr: secret}},
		{name: "no sleep support", f: fakeSleep{caps: []sleepCaps{{}}}},
		{name: "monitor off error", f: fakeSleep{caps: []sleepCaps{{AoAc: true}}, monitorErr: secret}, wantMon: 1},
		{name: "suspend error", f: fakeSleep{caps: []sleepCaps{{S3: true}}, suspendErr: secret}, wantSusp: 1},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			f := tt.f
			err := f.impl(discardLogger()).run(context.Background())
			if !errors.Is(err, control.ErrPower) {
				t.Fatalf("errors.Is(err, ErrPower) = false, err = %v", err)
			}
			if msg := err.Error(); msg != control.ErrPower.Error() {
				t.Fatalf("err.Error() = %q, want %q", msg, control.ErrPower.Error())
			}
			if f.monitorRuns != tt.wantMon || f.suspendRuns != tt.wantSusp {
				t.Fatalf("monitorOff=%d suspend=%d, want %d and %d",
					f.monitorRuns, f.suspendRuns, tt.wantMon, tt.wantSusp)
			}
		})
	}
}

func TestSleepImplCanceledContextRunsNothing(t *testing.T) {
	f := &fakeSleep{caps: []sleepCaps{{AoAc: true}}}
	ctx, cancel := context.WithCancel(context.Background())
	cancel()

	err := f.impl(discardLogger()).run(ctx)

	if !errors.Is(err, control.ErrPower) {
		t.Fatalf("errors.Is(err, ErrPower) = false, err = %v", err)
	}
	if f.readCalls != 0 || f.monitorRuns != 0 || f.suspendRuns != 0 {
		t.Fatalf("canceled run touched OS: reads=%d monitor=%d suspend=%d",
			f.readCalls, f.monitorRuns, f.suspendRuns)
	}
}

func TestSleepImplLogsChosenPath(t *testing.T) {
	var buf bytes.Buffer
	logger := slog.New(slog.NewTextHandler(&buf, &slog.HandlerOptions{Level: slog.LevelInfo}))
	f := &fakeSleep{caps: []sleepCaps{{AoAc: true, S3: false}}}

	if err := f.impl(logger).run(context.Background()); err != nil {
		t.Fatalf("run() error = %v", err)
	}

	out := buf.String()
	for _, want := range []string{"sleep path chosen", "path=monitor_off", "aoac=true", "s3=false"} {
		if !strings.Contains(out, want) {
			t.Errorf("log %q missing %q", out, want)
		}
	}
}

// discardLogger returns a logger whose output is dropped, so tests stay quiet.
func discardLogger() *slog.Logger {
	return slog.New(slog.NewTextHandler(&bytes.Buffer{}, nil))
}
