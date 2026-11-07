package main

import "remotto/agent/internal/oswin"

// newControllers returns the OS ports for Windows. Media uses the real
// SendInput implementation from M2 and volume uses the Core Audio worker from
// M3. Power (M4) still returns the unsupported stub until its milestone replaces
// it.
func newControllers() controllers {
	return controllers{
		Media: oswin.NewMedia(),
		Audio: oswin.NewAudio(),
		Power: unsupported{},
	}
}
