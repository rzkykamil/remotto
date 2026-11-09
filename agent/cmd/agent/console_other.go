//go:build !windows

package main

// detachConsole is a no-op on platforms without a Windows console.
func detachConsole() error {
	return nil
}
