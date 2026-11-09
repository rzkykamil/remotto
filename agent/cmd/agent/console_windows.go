package main

import (
	"errors"

	"golang.org/x/sys/windows"
)

// detachConsole calls kernel32 FreeConsole, which detaches this process from
// its console. The process keeps running; only the console window goes away.
func detachConsole() error {
	proc := windows.NewLazySystemDLL("kernel32.dll").NewProc("FreeConsole")
	ok, _, err := proc.Call()
	if ok != 0 {
		return nil
	}
	if err == nil {
		err = errors.New("FreeConsole returned 0")
	}
	return err
}
