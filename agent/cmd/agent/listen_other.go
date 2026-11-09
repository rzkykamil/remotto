//go:build !windows

package main

import (
	"errors"
	"syscall"
)

// isAddrInUse reports whether err means the address is already bound.
func isAddrInUse(err error) bool {
	return errors.Is(err, syscall.EADDRINUSE)
}
