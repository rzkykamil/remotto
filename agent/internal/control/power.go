package control

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"sync"
	"time"
)

// PowerDelay is the countdown between an accepted power request and its OS
// execution (BR-4). It is a constant on purpose: no option may change it.
const PowerDelay = 5 * time.Second

// powerExecuteTimeout caps a single OS power command. The caller never waits
// for it; it only bounds the goroutine that runs the command.
const powerExecuteTimeout = 15 * time.Second

// Sentinel errors for the power scheduler. Their messages are safe to return to
// clients.
var (
	ErrPowerPending       = errors.New("a power command is already scheduled")
	ErrNoPendingPower     = errors.New("no power command is scheduled")
	ErrPowerExecuting     = errors.New("a power command is executing")
	ErrInvalidPowerAction = errors.New("unknown power action")
)

// Valid reports whether a is one of the supported power actions.
func (a PowerAction) Valid() bool {
	switch a {
	case PowerSleep, PowerRestart, PowerShutdown:
		return true
	}
	return false
}

// PendingPower describes the scheduled power command. Remaining is the time left
// before execution, and is zero while the command is executing. Clients count
// down from Remaining, never from wall-clock timestamps (BR-20).
type PendingPower struct {
	Action      PowerAction
	Remaining   time.Duration
	Delay       time.Duration
	ScheduledAt time.Time
}

// PowerOptions configures a PowerScheduler. A nil Clock uses RealClock and a nil
// Logger uses slog.Default. There is no option to change the delay.
type PowerOptions struct {
	Clock  Clock
	Logger *slog.Logger
}

type powerState int

const (
	powerIdle powerState = iota
	powerScheduled
	powerExecuting
)

// PowerScheduler holds at most one pending power command. It waits PowerDelay
// on the clock, then runs the OS command outside its lock, so status reads keep
// answering while the command runs (BR-4, BR-5, BR-17).
type PowerScheduler struct {
	ctrl   PowerController
	clock  Clock
	logger *slog.Logger

	mu          sync.Mutex
	state       powerState
	action      PowerAction
	scheduledAt time.Time
	deadline    time.Time
	timer       Timer
	// gen is bumped on every schedule and cancel. A timer callback from an older
	// generation finds gen changed and does nothing.
	gen uint64
}

// NewPowerScheduler returns an idle PowerScheduler that executes through c. A
// nil c makes Schedule fail with ErrPower (fail-closed).
func NewPowerScheduler(c PowerController, o PowerOptions) *PowerScheduler {
	clock := o.Clock
	if clock == nil {
		clock = RealClock{}
	}
	logger := o.Logger
	if logger == nil {
		logger = slog.Default()
	}
	return &PowerScheduler{ctrl: c, clock: clock, logger: logger}
}

// Schedule accepts action and starts the PowerDelay countdown. It does not touch
// the OS, so it returns right away. A second request while a command is
// scheduled or executing fails with ErrPowerPending and changes nothing (BR-5).
func (s *PowerScheduler) Schedule(ctx context.Context, action PowerAction) (PendingPower, error) {
	if !action.Valid() {
		return PendingPower{}, Wrap(ErrPower, ErrInvalidPowerAction)
	}
	if s.ctrl == nil {
		return PendingPower{}, Wrap(ErrPower, ErrUnsupported)
	}
	if err := ctx.Err(); err != nil {
		return PendingPower{}, Wrap(ErrPower, err)
	}

	s.mu.Lock()
	defer s.mu.Unlock()

	if s.state != powerIdle {
		return PendingPower{}, ErrPowerPending
	}

	s.gen++
	gen := s.gen
	now := s.clock.Now()
	s.state = powerScheduled
	s.action = action
	s.scheduledAt = now
	s.deadline = now.Add(PowerDelay)
	s.timer = s.clock.AfterFunc(PowerDelay, func() { s.fire(gen) })
	return s.snapshotLocked(PowerDelay), nil
}

// Cancel removes the scheduled command and returns its action (BR-17). It fails
// with ErrNoPendingPower when nothing is scheduled, and with ErrPowerExecuting
// when the command already runs. The outcome is decided under the lock by gen,
// so the result of Timer.Stop is not needed.
func (s *PowerScheduler) Cancel() (PowerAction, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	switch s.state {
	case powerIdle:
		return "", ErrNoPendingPower
	case powerExecuting:
		return "", ErrPowerExecuting
	}

	action := s.action
	s.cancelLocked()
	return action, nil
}

// Pending reports the scheduled command. While the command executes, it reports
// Remaining 0 and ok true. When idle, it reports ok false.
func (s *PowerScheduler) Pending() (PendingPower, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()

	switch s.state {
	case powerScheduled:
		return s.snapshotLocked(max(s.deadline.Sub(s.clock.Now()), 0)), true
	case powerExecuting:
		return s.snapshotLocked(0), true
	}
	return PendingPower{}, false
}

// Close discards a scheduled command so it never runs. A command that is
// already executing is left alone.
func (s *PowerScheduler) Close() {
	s.mu.Lock()
	defer s.mu.Unlock()

	if s.state == powerScheduled {
		s.cancelLocked()
	}
}

// fire runs on the timer goroutine. It executes the command only if gen still
// matches the schedule that created the timer.
func (s *PowerScheduler) fire(gen uint64) {
	action, ok := s.beginExecute(gen)
	if !ok {
		return
	}

	var err error
	defer func() {
		if r := recover(); r != nil {
			err = fmt.Errorf("panic: %v", r)
		}
		s.endExecute()
		if err != nil {
			wrapped := powerError(err)
			s.logger.Error("power execute failed",
				"action", string(action),
				"error", wrapped,
				"cause", errors.Unwrap(wrapped),
			)
		}
	}()

	err = s.execute(action)
}

// execute runs the OS command. It is called without s.mu held.
func (s *PowerScheduler) execute(action PowerAction) error {
	ctx, cancel := context.WithTimeout(context.Background(), powerExecuteTimeout)
	defer cancel()
	return s.ctrl.Execute(ctx, action)
}

// beginExecute moves a scheduled command to executing. It returns false when gen
// is stale or the schedule is no longer active.
func (s *PowerScheduler) beginExecute(gen uint64) (PowerAction, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()

	if gen != s.gen || s.state != powerScheduled {
		return "", false
	}
	s.state = powerExecuting
	s.timer = nil
	return s.action, true
}

// endExecute returns the scheduler to idle once the OS call has returned.
func (s *PowerScheduler) endExecute() {
	s.mu.Lock()
	defer s.mu.Unlock()

	s.resetLocked()
}

// cancelLocked stops the timer and bumps gen, so a fire that is already waiting
// for the lock sees a stale generation. Caller holds s.mu and the state is
// powerScheduled.
func (s *PowerScheduler) cancelLocked() {
	s.timer.Stop()
	s.gen++
	s.resetLocked()
}

// resetLocked returns the scheduler to idle and clears the schedule fields.
// Caller holds s.mu.
func (s *PowerScheduler) resetLocked() {
	s.state = powerIdle
	s.action = ""
	s.scheduledAt = time.Time{}
	s.deadline = time.Time{}
	s.timer = nil
}

// snapshotLocked builds a PendingPower for the current schedule. Caller holds s.mu.
func (s *PowerScheduler) snapshotLocked(remaining time.Duration) PendingPower {
	return PendingPower{
		Action:      s.action,
		Remaining:   remaining,
		Delay:       PowerDelay,
		ScheduledAt: s.scheduledAt,
	}
}

// powerError maps an OS error to ErrPower, keeping the cause for logging. An
// error that already matches ErrPower is returned as-is.
func powerError(err error) error {
	if errors.Is(err, ErrPower) {
		return err
	}
	return Wrap(ErrPower, err)
}
