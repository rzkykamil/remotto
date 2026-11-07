package main

// newControllers returns the OS ports for Windows. In M0 it still returns the
// unsupported stubs: the internal/oswin implementations replace them in M2
// (media), M3 (volume) and M4 (power). No real OS code runs in M0.
func newControllers() controllers {
	return controllers{
		Media: unsupported{},
		Audio: unsupported{},
		Power: unsupported{},
	}
}
