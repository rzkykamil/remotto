//go:build windows

package instance

import (
	"sync"

	"golang.org/x/sys/windows"
)

// acquire creates the named mutex. CreateMutex succeeds with
// ERROR_ALREADY_EXISTS when another process already owns the name, so that
// case closes the new handle and reports ErrAlreadyRunning.
func acquire(name string) (Release, error) {
	namePtr, err := windows.UTF16PtrFromString(name)
	if err != nil {
		return nil, err
	}
	h, err := windows.CreateMutex(nil, false, namePtr)
	if err != nil {
		if err == windows.ERROR_ALREADY_EXISTS {
			if h != 0 {
				_ = windows.CloseHandle(h)
			}
			return nil, ErrAlreadyRunning
		}
		return nil, err
	}
	var once sync.Once
	return func() {
		once.Do(func() { _ = windows.CloseHandle(h) })
	}, nil
}
