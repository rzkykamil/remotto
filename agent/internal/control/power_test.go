package control_test

import (
	"bytes"
	"context"
	"errors"
	"io"
	"log/slog"
	"strings"
	"sync"
	"testing"
	"time"

	"remotto/agent/internal/control"
	"remotto/agent/internal/oscontrol/fake"
)

var testStart = time.Date(2026, 11, 9, 10, 0, 0, 0, time.UTC)

// holdPower blocks Execute until Release, so a test can inspect the scheduler
// while a power command is running.
type holdPower struct {
	started chan control.PowerAction
	release chan struct{}
	once    sync.Once
}

func newHoldPower() *holdPower {
	return &holdPower{
		started: make(chan control.PowerAction, 1),
		release: make(chan struct{}),
	}
}

func (p *holdPower) Execute(ctx context.Context, action control.PowerAction) error {
	p.started <- action
	select {
	case <-p.release:
		return nil
	case <-ctx.Done():
		return ctx.Err()
	}
}

// Release lets a blocked Execute return. It is safe to call more than once.
func (p *holdPower) Release() {
	p.once.Do(func() { close(p.release) })
}

func quietLogger() *slog.Logger {
	return slog.New(slog.NewTextHandler(io.Discard, nil))
}

func schedOpts(c *fake.Clock) control.PowerOptions {
	return control.PowerOptions{Clock: c, Logger: quietLogger()}
}

func mustSchedule(t *testing.T, s *control.PowerScheduler, action control.PowerAction) control.PendingPower {
	t.Helper()
	p, err := s.Schedule(context.Background(), action)
	if err != nil {
		t.Fatalf("Schedule(%q) error = %v, want nil", action, err)
	}
	return p
}

// advanceAsync runs clock.Advance in its own goroutine. The returned channel
// closes when Advance has returned.
func advanceAsync(c *fake.Clock, d time.Duration) <-chan struct{} {
	done := make(chan struct{})
	go func() {
		defer close(done)
		c.Advance(d)
	}()
	return done
}

func waitStarted(t *testing.T, p *holdPower) control.PowerAction {
	t.Helper()
	select {
	case action := <-p.started:
		return action
	case <-time.After(5 * time.Second):
		t.Fatal("Execute was not called within 5s")
		return ""
	}
}

func TestPowerActionValid(t *testing.T) {
	tests := []struct {
		action control.PowerAction
		want   bool
	}{
		{control.PowerSleep, true},
		{control.PowerRestart, true},
		{control.PowerShutdown, true},
		{control.PowerAction("hibernate"), false},
		{control.PowerAction(""), false},
	}
	for _, tt := range tests {
		t.Run(string(tt.action), func(t *testing.T) {
			if got := tt.action.Valid(); got != tt.want {
				t.Fatalf("Valid() = %v, want %v", got, tt.want)
			}
		})
	}
}

// BR-4: every power action waits the full PowerDelay before the OS is called,
// and Schedule itself never calls the OS.
func TestBR4_ExecutesOnlyAfterPowerDelay(t *testing.T) {
	actions := []control.PowerAction{control.PowerSleep, control.PowerRestart, control.PowerShutdown}
	for _, action := range actions {
		t.Run(string(action), func(t *testing.T) {
			clock := fake.NewClock(testStart)
			ctrl := &fake.Power{}
			s := control.NewPowerScheduler(ctrl, schedOpts(clock))

			p, err := s.Schedule(context.Background(), action)
			if err != nil {
				t.Fatalf("Schedule() error = %v, want nil", err)
			}
			if p.Action != action || p.Remaining != 5*time.Second || p.Delay != 5*time.Second {
				t.Fatalf("Schedule() = %+v, want %q with Remaining and Delay 5s", p, action)
			}
			if !p.ScheduledAt.Equal(testStart) {
				t.Fatalf("ScheduledAt = %v, want %v", p.ScheduledAt, testStart)
			}
			if calls := ctrl.Calls(); len(calls) != 0 {
				t.Fatalf("Execute called before the delay: %v", calls)
			}

			clock.Advance(4999 * time.Millisecond)
			if calls := ctrl.Calls(); len(calls) != 0 {
				t.Fatalf("Execute called at 4999ms: %v", calls)
			}
			pending, ok := s.Pending()
			if !ok || pending.Remaining != time.Millisecond {
				t.Fatalf("Pending() = %+v, %v; want Remaining 1ms", pending, ok)
			}

			clock.Advance(time.Millisecond)
			if calls := ctrl.Calls(); len(calls) != 1 || calls[0] != action {
				t.Fatalf("Calls() = %v, want [%q] exactly once", calls, action)
			}
			if _, ok := s.Pending(); ok {
				t.Fatal("Pending() ok after execution, want idle")
			}
		})
	}
}

// BR-5: a second request while a command is scheduled is rejected, and the
// original schedule keeps its deadline.
func TestBR5_SecondScheduleRejected(t *testing.T) {
	clock := fake.NewClock(testStart)
	ctrl := &fake.Power{}
	s := control.NewPowerScheduler(ctrl, schedOpts(clock))
	mustSchedule(t, s, control.PowerSleep)

	clock.Advance(2 * time.Second)
	_, err := s.Schedule(context.Background(), control.PowerRestart)
	if !errors.Is(err, control.ErrPowerPending) {
		t.Fatalf("second Schedule() error = %v, want ErrPowerPending", err)
	}
	pending, ok := s.Pending()
	if !ok || pending.Action != control.PowerSleep || pending.Remaining != 3*time.Second {
		t.Fatalf("Pending() = %+v, %v; want sleep with Remaining 3s", pending, ok)
	}

	clock.Advance(3 * time.Second)
	if calls := ctrl.Calls(); len(calls) != 1 || calls[0] != control.PowerSleep {
		t.Fatalf("Calls() = %v, want [sleep] only", calls)
	}
}

// BR-5: a request while the command is executing is rejected too, and Pending
// reports Remaining 0 with ok true.
func TestBR5_ScheduleRejectedWhileExecuting(t *testing.T) {
	clock := fake.NewClock(testStart)
	ctrl := newHoldPower()
	t.Cleanup(ctrl.Release)
	s := control.NewPowerScheduler(ctrl, schedOpts(clock))
	mustSchedule(t, s, control.PowerRestart)

	done := advanceAsync(clock, control.PowerDelay)
	if got := waitStarted(t, ctrl); got != control.PowerRestart {
		t.Fatalf("Execute action = %q, want restart", got)
	}

	_, err := s.Schedule(context.Background(), control.PowerSleep)
	if !errors.Is(err, control.ErrPowerPending) {
		t.Fatalf("Schedule() while executing error = %v, want ErrPowerPending", err)
	}
	pending, ok := s.Pending()
	if !ok || pending.Action != control.PowerRestart || pending.Remaining != 0 {
		t.Fatalf("Pending() while executing = %+v, %v; want restart with Remaining 0, ok true", pending, ok)
	}

	ctrl.Release()
	<-done
	if _, ok := s.Pending(); ok {
		t.Fatal("Pending() ok after execution, want idle")
	}
}

// BR-17: cancel without a schedule fails.
func TestBR17_CancelWithoutScheduleFails(t *testing.T) {
	s := control.NewPowerScheduler(&fake.Power{}, schedOpts(fake.NewClock(testStart)))

	for range 2 {
		action, err := s.Cancel()
		if !errors.Is(err, control.ErrNoPendingPower) {
			t.Fatalf("Cancel() error = %v, want ErrNoPendingPower", err)
		}
		if action != "" {
			t.Fatalf("Cancel() action = %q, want empty", action)
		}
	}
}

// BR-17: cancel returns the action and stops the command from running.
func TestBR17_CancelPreventsExecution(t *testing.T) {
	clock := fake.NewClock(testStart)
	ctrl := &fake.Power{}
	s := control.NewPowerScheduler(ctrl, schedOpts(clock))
	mustSchedule(t, s, control.PowerRestart)

	clock.Advance(3 * time.Second)
	action, err := s.Cancel()
	if err != nil || action != control.PowerRestart {
		t.Fatalf("Cancel() = %q, %v; want restart, nil", action, err)
	}

	clock.Advance(10 * time.Second)
	if calls := ctrl.Calls(); len(calls) != 0 {
		t.Fatalf("Calls() = %v after cancel, want none", calls)
	}
	if _, ok := s.Pending(); ok {
		t.Fatal("Pending() ok after cancel, want idle")
	}
	if n := clock.Pending(); n != 0 {
		t.Fatalf("clock has %d pending timers after cancel, want 0", n)
	}
}

// A cancel while the command runs fails, and the command still completes.
func TestCancelWhileExecutingFails(t *testing.T) {
	clock := fake.NewClock(testStart)
	ctrl := newHoldPower()
	t.Cleanup(ctrl.Release)
	s := control.NewPowerScheduler(ctrl, schedOpts(clock))
	mustSchedule(t, s, control.PowerShutdown)

	done := advanceAsync(clock, control.PowerDelay)
	waitStarted(t, ctrl)

	action, err := s.Cancel()
	if !errors.Is(err, control.ErrPowerExecuting) {
		t.Fatalf("Cancel() while executing error = %v, want ErrPowerExecuting", err)
	}
	if action != "" {
		t.Fatalf("Cancel() action = %q, want empty", action)
	}

	ctrl.Release()
	<-done
	if _, ok := s.Pending(); ok {
		t.Fatal("Pending() ok after execution, want idle")
	}
}

// After a cancel, a new schedule starts a full PowerDelay countdown.
func TestCancelThenScheduleWaitsFullDelay(t *testing.T) {
	clock := fake.NewClock(testStart)
	ctrl := &fake.Power{}
	s := control.NewPowerScheduler(ctrl, schedOpts(clock))
	mustSchedule(t, s, control.PowerSleep)

	clock.Advance(3 * time.Second)
	if _, err := s.Cancel(); err != nil {
		t.Fatalf("Cancel() error = %v, want nil", err)
	}
	p := mustSchedule(t, s, control.PowerShutdown)
	if p.Remaining != 5*time.Second {
		t.Fatalf("Remaining = %v, want 5s", p.Remaining)
	}

	clock.Advance(4999 * time.Millisecond)
	if calls := ctrl.Calls(); len(calls) != 0 {
		t.Fatalf("Calls() = %v at 4999ms after reschedule, want none", calls)
	}
	clock.Advance(time.Millisecond)
	if calls := ctrl.Calls(); len(calls) != 1 || calls[0] != control.PowerShutdown {
		t.Fatalf("Calls() = %v, want [shutdown] once", calls)
	}
}

// A failed OS call returns the scheduler to idle, the next schedule works, and
// the cause is logged but not returned.
func TestExecuteFailureReturnsToIdle(t *testing.T) {
	clock := fake.NewClock(testStart)
	ctrl := &fake.Power{}
	ctrl.SetErr(errors.New("exit status 1"))

	var logBuf bytes.Buffer
	logger := slog.New(slog.NewTextHandler(&logBuf, nil))
	s := control.NewPowerScheduler(ctrl, control.PowerOptions{Clock: clock, Logger: logger})

	mustSchedule(t, s, control.PowerSleep)
	clock.Advance(control.PowerDelay)

	if calls := ctrl.Calls(); len(calls) != 1 || calls[0] != control.PowerSleep {
		t.Fatalf("Calls() = %v, want [sleep] once", calls)
	}
	if _, ok := s.Pending(); ok {
		t.Fatal("Pending() ok after failed execute, want idle")
	}
	logged := logBuf.String()
	if !strings.Contains(logged, "power execute failed") || !strings.Contains(logged, "exit status 1") {
		t.Fatalf("log = %q, want execute failure with cause", logged)
	}

	ctrl.SetErr(nil)
	mustSchedule(t, s, control.PowerRestart)
	clock.Advance(control.PowerDelay)
	if calls := ctrl.Calls(); len(calls) != 2 || calls[1] != control.PowerRestart {
		t.Fatalf("Calls() = %v, want second call restart", calls)
	}
}

// Without a controller the scheduler fails closed: no timer, nothing pending.
func TestPowerNilControllerFailsClosed(t *testing.T) {
	clock := fake.NewClock(testStart)
	s := control.NewPowerScheduler(nil, schedOpts(clock))

	_, err := s.Schedule(context.Background(), control.PowerSleep)
	if !errors.Is(err, control.ErrPower) {
		t.Fatalf("errors.Is(err, ErrPower) = false, err = %v", err)
	}
	if !errors.Is(err, control.ErrUnsupported) {
		t.Fatalf("errors.Is(err, ErrUnsupported) = false, want true")
	}
	if _, ok := s.Pending(); ok {
		t.Fatal("Pending() ok with nil controller, want false")
	}
	if n := clock.Pending(); n != 0 {
		t.Fatalf("clock has %d timers with nil controller, want 0", n)
	}
}

func TestInvalidPowerActionRejected(t *testing.T) {
	tests := []control.PowerAction{control.PowerAction("hibernate"), control.PowerAction("")}
	for _, action := range tests {
		t.Run(string(action), func(t *testing.T) {
			clock := fake.NewClock(testStart)
			ctrl := &fake.Power{}
			s := control.NewPowerScheduler(ctrl, schedOpts(clock))

			_, err := s.Schedule(context.Background(), action)
			if !errors.Is(err, control.ErrPower) {
				t.Fatalf("errors.Is(err, ErrPower) = false, err = %v", err)
			}
			if !errors.Is(err, control.ErrInvalidPowerAction) {
				t.Fatalf("errors.Is(err, ErrInvalidPowerAction) = false, err = %v", err)
			}
			if _, ok := s.Pending(); ok {
				t.Fatal("Pending() ok after invalid action, want false")
			}
			if n := clock.Pending(); n != 0 {
				t.Fatalf("clock has %d timers after invalid action, want 0", n)
			}
		})
	}
}

// A canceled context is rejected before any state changes.
func TestCanceledContextRejectedBeforeScheduling(t *testing.T) {
	clock := fake.NewClock(testStart)
	ctrl := &fake.Power{}
	s := control.NewPowerScheduler(ctrl, schedOpts(clock))

	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	_, err := s.Schedule(ctx, control.PowerSleep)
	if !errors.Is(err, control.ErrPower) || !errors.Is(err, context.Canceled) {
		t.Fatalf("Schedule() error = %v, want ErrPower wrapping context.Canceled", err)
	}
	if _, ok := s.Pending(); ok {
		t.Fatal("Pending() ok after rejected context, want false")
	}
}

// Errors match ErrPower through errors.Is, and Error() does not expose the cause.
func TestErrorsWrapErrPowerWithoutLeakingCause(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	s := control.NewPowerScheduler(&fake.Power{}, schedOpts(fake.NewClock(testStart)))

	_, err := s.Schedule(ctx, control.PowerSleep)
	if !errors.Is(err, control.ErrPower) {
		t.Fatalf("errors.Is(err, ErrPower) = false, err = %v", err)
	}
	if err.Error() != control.ErrPower.Error() {
		t.Fatalf("err.Error() = %q, want %q", err.Error(), control.ErrPower.Error())
	}
	if strings.Contains(err.Error(), context.Canceled.Error()) {
		t.Fatalf("err.Error() leaks cause: %q", err.Error())
	}
}

// Close discards a scheduled command so it never runs.
func TestCloseDiscardsSchedule(t *testing.T) {
	clock := fake.NewClock(testStart)
	ctrl := &fake.Power{}
	s := control.NewPowerScheduler(ctrl, schedOpts(clock))
	mustSchedule(t, s, control.PowerShutdown)

	s.Close()
	s.Close()

	if n := clock.Pending(); n != 0 {
		t.Fatalf("clock has %d pending timers after Close, want 0", n)
	}
	if _, ok := s.Pending(); ok {
		t.Fatal("Pending() ok after Close, want false")
	}
	clock.Advance(10 * time.Second)
	if calls := ctrl.Calls(); len(calls) != 0 {
		t.Fatalf("Calls() = %v after Close, want none", calls)
	}
	if _, err := s.Cancel(); !errors.Is(err, control.ErrNoPendingPower) {
		t.Fatalf("Cancel() after Close error = %v, want ErrNoPendingPower", err)
	}
}

// Cancel and the timer race for the same schedule. Each round must end with
// exactly one outcome: Execute was called, or Cancel succeeded. Run 200 rounds.
func TestPowerCancelAndFireRaceSingleOutcome(t *testing.T) {
	const rounds = 200
	for i := range rounds {
		clock := fake.NewClock(testStart)
		ctrl := &fake.Power{}
		s := control.NewPowerScheduler(ctrl, schedOpts(clock))
		mustSchedule(t, s, control.PowerSleep)

		var wg sync.WaitGroup
		start := make(chan struct{})
		var cancelErr error
		wg.Add(2)
		go func() {
			defer wg.Done()
			<-start
			_, cancelErr = s.Cancel()
		}()
		go func() {
			defer wg.Done()
			<-start
			clock.Advance(control.PowerDelay)
		}()
		close(start)
		wg.Wait()

		executed := len(ctrl.Calls())
		cancelled := cancelErr == nil
		if executed > 1 {
			t.Fatalf("round %d: Execute called %d times, want at most 1", i, executed)
		}
		if cancelErr != nil && !errors.Is(cancelErr, control.ErrPowerExecuting) && !errors.Is(cancelErr, control.ErrNoPendingPower) {
			t.Fatalf("round %d: Cancel() error = %v, want ErrPowerExecuting or ErrNoPendingPower", i, cancelErr)
		}
		if (executed == 1) == cancelled {
			t.Fatalf("round %d: executed = %d, cancelled = %v; want exactly one outcome", i, executed, cancelled)
		}
	}
}
