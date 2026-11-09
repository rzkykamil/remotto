//go:build !windows

package main

// newControllers returns the OS ports for platforms without an OS
// implementation. Every port fails with control.ErrUnsupported.
func newControllers() controllers {
	return controllers{
		Media: unsupported{},
		Audio: unsupported{},
		Power: unsupported{},
	}
}
