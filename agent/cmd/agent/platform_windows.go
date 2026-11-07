package main

import "remotto/agent/internal/oswin"

// newControllers returns the OS ports for Windows. Media uses the real
// SendInput implementation from M2. Volume (M3) and power (M4) still return the
// unsupported stubs until their milestones replace them.
func newControllers() controllers {
	return controllers{
		Media: oswin.NewMedia(),
		Audio: unsupported{},
		Power: unsupported{},
	}
}
