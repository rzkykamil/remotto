package fake

import (
	"sync"
	"time"

	"remotto/agent/internal/control"
)

var _ control.Clock = (*Clock)(nil)

// Clock is a control.Clock whose time moves only when Advance is called. Timers
// run synchronously inside Advance, so scheduler tests never wait on real time.
type Clock struct {
	mu     sync.Mutex
	now    time.Time
	seq    uint64
	timers []*clockTimer
}

// clockTimer is the control.Timer returned by Clock.AfterFunc.
type clockTimer struct {
	clock    *Clock
	deadline time.Time
	seq      uint64
	f        func()
	done     bool // true once fired or stopped
}

// NewClock returns a Clock that starts at start and has no pending timers.
func NewClock(start time.Time) *Clock {
	return &Clock{now: start}
}

// Now returns the current fake time.
func (c *Clock) Now() time.Time {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.now
}

// AfterFunc schedules f to run once the fake time reaches Now()+d. A negative d
// is treated as zero. The timer only fires during a later Advance call, even
// when d is zero.
func (c *Clock) AfterFunc(d time.Duration, f func()) control.Timer {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.seq++
	t := &clockTimer{
		clock:    c,
		deadline: c.now.Add(max(d, 0)),
		seq:      c.seq,
		f:        f,
	}
	c.timers = append(c.timers, t)
	return t
}

// Advance moves the fake time forward by d (negative d counts as zero) and runs
// every timer whose deadline is at or before the new time. Timers run in the
// calling goroutine, ordered by deadline and then by scheduling order. While a
// callback runs, Now returns that timer's deadline, and the internal mutex is
// not held, so callbacks may call Now, Pending, AfterFunc or Stop.
func (c *Clock) Advance(d time.Duration) {
	c.mu.Lock()
	target := c.now.Add(max(d, 0))
	c.mu.Unlock()

	for {
		c.mu.Lock()
		t := c.nextDueLocked(target)
		if t == nil {
			c.now = target
			c.mu.Unlock()
			return
		}
		c.removeLocked(t)
		t.done = true
		if t.deadline.After(c.now) {
			c.now = t.deadline
		}
		c.mu.Unlock()

		t.f()
	}
}

// Pending returns the number of timers that have neither fired nor been stopped.
func (c *Clock) Pending() int {
	c.mu.Lock()
	defer c.mu.Unlock()
	return len(c.timers)
}

// Stop cancels the timer. It returns true if the timer was still pending, and
// false if it already fired or was already stopped.
func (t *clockTimer) Stop() bool {
	c := t.clock
	c.mu.Lock()
	defer c.mu.Unlock()
	if t.done {
		return false
	}
	t.done = true
	c.removeLocked(t)
	return true
}

// nextDueLocked returns the earliest pending timer with a deadline at or before
// target, or nil. Ties go to the timer scheduled first. Caller holds c.mu.
func (c *Clock) nextDueLocked(target time.Time) *clockTimer {
	var next *clockTimer
	for _, t := range c.timers {
		if t.deadline.After(target) {
			continue
		}
		if next == nil || t.deadline.Before(next.deadline) ||
			(t.deadline.Equal(next.deadline) && t.seq < next.seq) {
			next = t
		}
	}
	return next
}

// removeLocked drops t from the pending list. Caller holds c.mu.
func (c *Clock) removeLocked(t *clockTimer) {
	for i, cur := range c.timers {
		if cur == t {
			c.timers = append(c.timers[:i], c.timers[i+1:]...)
			return
		}
	}
}
