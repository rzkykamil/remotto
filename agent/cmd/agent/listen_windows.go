//go:build windows

package main

import (
	"errors"

	"golang.org/x/sys/windows"
)

// isAddrInUse reports whether err means the address is already bound. On Windows
// the code is WSAEADDRINUSE (10048), not syscall.EADDRINUSE.
func isAddrInUse(err error) bool {
	return errors.Is(err, windows.WSAEADDRINUSE)
}
