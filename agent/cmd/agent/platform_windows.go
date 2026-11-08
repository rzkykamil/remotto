package main

import "remotto/agent/internal/oswin"

// newControllers returns the OS ports for Windows. Media uses the real
// SendInput implementation from M2, volume uses the Core Audio worker from M3,
// and power uses shutdown.exe and the sleep path from M4. Power commands never
// reach the OS directly: serveAgent wraps them in control.PowerScheduler.
func newControllers() controllers {
	return controllers{
		Media: oswin.NewMedia(),
		Audio: oswin.NewAudio(),
		Power: oswin.NewPower(),
	}
}
