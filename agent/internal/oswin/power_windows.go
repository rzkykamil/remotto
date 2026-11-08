package oswin

import (
	"context"
	"errors"
	"fmt"
	"os/exec"
	"path/filepath"
	"syscall"

	"golang.org/x/sys/windows"

	"remotto/agent/internal/control"
)

var _ control.PowerController = (*Power)(nil)

// Power runs shutdown and restart through shutdown.exe. Sleep goes through its
// own path. Both run functions are fields so tests can replace them and no
// test reaches the OS.
type Power struct {
	run   func(ctx context.Context, args []string) error
	sleep func(ctx context.Context) error
}

// NewPower returns a Power bound to the production shutdown.exe runner and the
// production sleep path. It does not run any command until Execute is called.
func NewPower() *Power {
	return &Power{
		run:   runShutdown,
		sleep: newSleep(nil).run,
	}
}

// shutdownArgs returns the shutdown.exe arguments for a. Shutdown and restart
// never include /f, so apps with unsaved work are not force-closed (R-15).
// Sleep and unknown actions return false.
func shutdownArgs(a control.PowerAction) ([]string, bool) {
	switch a {
	case control.PowerShutdown:
		return []string{"/s", "/t", "0"}, true
	case control.PowerRestart:
		return []string{"/r", "/t", "0"}, true
	}
	return nil, false
}

// Execute runs the power action a immediately. Delay and cancel belong to the
// scheduler, not here. Errors carry only the ErrPower message; the OS detail
// stays reachable through Unwrap for logs.
func (p *Power) Execute(ctx context.Context, a control.PowerAction) error {
	if a == control.PowerSleep {
		return p.sleep(ctx)
	}
	args, ok := shutdownArgs(a)
	if !ok {
		return control.Wrap(control.ErrPower, fmt.Errorf("unknown power action %q", a))
	}
	if err := p.run(ctx, args); err != nil {
		if errors.Is(err, control.ErrPower) {
			return err
		}
		return control.Wrap(control.ErrPower, err)
	}
	return nil
}

// runShutdown runs shutdown.exe from System32 without a shell and without a
// console window.
func runShutdown(ctx context.Context, args []string) error {
	sysDir, err := windows.GetSystemDirectory()
	if err != nil {
		return control.Wrap(control.ErrPower, fmt.Errorf("resolve system directory: %w", err))
	}
	cmd := exec.CommandContext(ctx, filepath.Join(sysDir, "shutdown.exe"), args...)
	cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true}
	out, err := cmd.CombinedOutput()
	if err != nil {
		return control.Wrap(control.ErrPower, fmt.Errorf("shutdown.exe failed: %w: %s", err, out))
	}
	return nil
}
