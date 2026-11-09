package control

import "time"

// Timer is a pending callback that can be cancelled before it runs.
type Timer interface {
	// Stop cancels the timer. It returns true if the call stopped the timer
	// before its callback started, and false if the timer already fired or was stopped.
	Stop() bool
}

// Clock gives the scheduler the current time and delayed callbacks. Tests
// inject a fake clock so deadlines can be advanced without waiting.
type Clock interface {
	Now() time.Time
	AfterFunc(d time.Duration, f func()) Timer
}

// RealClock is the Clock backed by the standard time package.
type RealClock struct{}

// Now returns the current wall-clock time.
func (RealClock) Now() time.Time {
	return time.Now()
}

// AfterFunc runs f in its own goroutine after d has elapsed.
func (RealClock) AfterFunc(d time.Duration, f func()) Timer {
	return time.AfterFunc(d, f)
}
