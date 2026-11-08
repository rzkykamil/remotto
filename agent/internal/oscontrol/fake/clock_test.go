package fake

import (
	"reflect"
	"testing"
	"time"
)

var clockStart = time.Date(2026, 1, 1, 12, 0, 0, 0, time.UTC)

func TestClockAdvanceBelowDeadlineDoesNotFire(t *testing.T) {
	c := NewClock(clockStart)
	fired := 0
	c.AfterFunc(5*time.Second, func() { fired++ })

	c.Advance(4999 * time.Millisecond)

	if fired != 0 {
		t.Fatalf("fired = %d before deadline, want 0", fired)
	}
	if got := c.Pending(); got != 1 {
		t.Fatalf("Pending() = %d, want 1", got)
	}
}

func TestClockAdvanceToDeadlineFiresOnce(t *testing.T) {
	steps := []struct {
		name     string
		advances []time.Duration
		want     int
	}{
		{"exact deadline", []time.Duration{5 * time.Second}, 1},
		{"deadline reached in parts", []time.Duration{2 * time.Second, 3 * time.Second}, 1},
		{"again after firing", []time.Duration{5 * time.Second, 10 * time.Second}, 1},
	}
	for _, tc := range steps {
		t.Run(tc.name, func(t *testing.T) {
			c := NewClock(clockStart)
			fired := 0
			c.AfterFunc(5*time.Second, func() { fired++ })
			for _, d := range tc.advances {
				c.Advance(d)
			}
			if fired != tc.want {
				t.Fatalf("fired = %d, want %d", fired, tc.want)
			}
		})
	}
}

func TestClockNowFollowsAdvance(t *testing.T) {
	c := NewClock(clockStart)
	c.Advance(90 * time.Second)
	if want := clockStart.Add(90 * time.Second); !c.Now().Equal(want) {
		t.Fatalf("Now() = %v, want %v", c.Now(), want)
	}
}

func TestClockStopBeforeDeadlinePreventsFire(t *testing.T) {
	c := NewClock(clockStart)
	fired := 0
	timer := c.AfterFunc(5*time.Second, func() { fired++ })

	if !timer.Stop() {
		t.Fatal("Stop() before deadline = false, want true")
	}
	c.Advance(10 * time.Second)

	if fired != 0 {
		t.Fatalf("fired = %d after Stop, want 0", fired)
	}
	if got := c.Pending(); got != 0 {
		t.Fatalf("Pending() = %d after Stop, want 0", got)
	}
}

func TestClockStopAfterFireReturnsFalse(t *testing.T) {
	c := NewClock(clockStart)
	timer := c.AfterFunc(time.Second, func() {})
	c.Advance(time.Second)

	if timer.Stop() {
		t.Fatal("Stop() after firing = true, want false")
	}
}

func TestClockStopTwiceReturnsFalseSecondTime(t *testing.T) {
	c := NewClock(clockStart)
	timer := c.AfterFunc(time.Second, func() {})

	if !timer.Stop() {
		t.Fatal("first Stop() = false, want true")
	}
	if timer.Stop() {
		t.Fatal("second Stop() = true, want false")
	}
}

func TestClockFiresInDeadlineOrder(t *testing.T) {
	c := NewClock(clockStart)
	var order []string
	c.AfterFunc(3*time.Second, func() { order = append(order, "c") })
	c.AfterFunc(1*time.Second, func() { order = append(order, "a") })
	c.AfterFunc(2*time.Second, func() { order = append(order, "b") })
	c.AfterFunc(1*time.Second, func() { order = append(order, "a2") })

	c.Advance(5 * time.Second)

	want := []string{"a", "a2", "b", "c"}
	if !reflect.DeepEqual(order, want) {
		t.Fatalf("order = %v, want %v", order, want)
	}
}

func TestClockCallbackSchedulingNewTimer(t *testing.T) {
	t.Run("new timer fires in later advance", func(t *testing.T) {
		c := NewClock(clockStart)
		fired := 0
		c.AfterFunc(time.Second, func() {
			c.AfterFunc(2*time.Second, func() { fired++ })
		})

		c.Advance(time.Second)
		c.Advance(time.Second)
		if fired != 0 {
			t.Fatalf("fired = %d at t+2s, want 0", fired)
		}
		c.Advance(time.Second)
		if fired != 1 {
			t.Fatalf("fired = %d at t+3s, want 1", fired)
		}
	})

	t.Run("new timer due within same advance fires too", func(t *testing.T) {
		c := NewClock(clockStart)
		var seen []time.Time
		c.AfterFunc(time.Second, func() {
			seen = append(seen, c.Now())
			c.AfterFunc(time.Second, func() {
				seen = append(seen, c.Now())
			})
		})

		c.Advance(10 * time.Second)

		want := []time.Time{clockStart.Add(time.Second), clockStart.Add(2 * time.Second)}
		if len(seen) != len(want) {
			t.Fatalf("fired %d times, want %d", len(seen), len(want))
		}
		for i := range want {
			if !seen[i].Equal(want[i]) {
				t.Fatalf("callback %d saw Now() = %v, want %v", i, seen[i], want[i])
			}
		}
	})
}

func TestClockCallbackCanCallClockMethods(t *testing.T) {
	c := NewClock(clockStart)
	pendingInside := -1
	c.AfterFunc(time.Second, func() {
		// Would deadlock if Advance still held the mutex.
		pendingInside = c.Pending()
	})

	c.Advance(time.Second)

	if pendingInside != 0 {
		t.Fatalf("Pending() inside callback = %d, want 0", pendingInside)
	}
}

func TestClockPendingCountsActiveTimers(t *testing.T) {
	c := NewClock(clockStart)
	if got := c.Pending(); got != 0 {
		t.Fatalf("Pending() on new clock = %d, want 0", got)
	}

	stopped := c.AfterFunc(time.Second, func() {})
	c.AfterFunc(2*time.Second, func() {})
	if got := c.Pending(); got != 2 {
		t.Fatalf("Pending() = %d, want 2", got)
	}

	stopped.Stop()
	if got := c.Pending(); got != 1 {
		t.Fatalf("Pending() after Stop = %d, want 1", got)
	}

	c.Advance(2 * time.Second)
	if got := c.Pending(); got != 0 {
		t.Fatalf("Pending() after firing = %d, want 0", got)
	}
}
