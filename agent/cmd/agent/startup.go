package main

import (
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"os/user"

	"remotto/agent/internal/startup"
)

// newStartupManager builds the logon-task manager for install-startup and
// uninstall-startup. Tests replace it with a fake Runner so they never call the
// real schtasks.
var newStartupManager = func() *startup.Manager {
	// Runner is left nil so the Manager uses the system Runner (schtasks).
	return &startup.Manager{
		Executable: os.Executable,
		CurrentUser: func() (string, error) {
			u, err := user.Current()
			if err != nil {
				return "", err
			}
			return u.Username, nil
		},
	}
}

// cmdInstallStartup creates the logon task that runs the agent in the background.
func cmdInstallStartup(stdout, stderr io.Writer, args []string) int {
	if len(args) > 0 {
		fmt.Fprintf(stderr, "remotto-agent: argumen tidak dikenal: %s\n", args[0])
		return 2
	}
	err := newStartupManager().Install(context.Background())
	if err != nil {
		reportStartupError(stderr, err)
		return 1
	}
	fmt.Fprintln(stdout, "autostart terpasang: agent jalan otomatis saat login")
	return 0
}

// cmdUninstallStartup removes the logon task. A missing task counts as removed.
func cmdUninstallStartup(stdout, stderr io.Writer, args []string) int {
	if len(args) > 0 {
		fmt.Fprintf(stderr, "remotto-agent: argumen tidak dikenal: %s\n", args[0])
		return 2
	}
	err := newStartupManager().Uninstall(context.Background())
	if err != nil {
		reportStartupError(stderr, err)
		return 1
	}
	fmt.Fprintln(stdout, "autostart dihapus")
	return 0
}

// reportStartupError prints a safe message. Sentinel messages never include
// raw schtasks output.
func reportStartupError(stderr io.Writer, err error) {
	if errors.Is(err, startup.ErrNeedAdmin) {
		fmt.Fprintln(stderr, "remotto-agent: butuh hak administrator untuk mengatur autostart")
		fmt.Fprintln(stderr, "buka terminal sebagai Administrator, lalu jalankan perintah ini lagi")
		return
	}
	fmt.Fprintf(stderr, "remotto-agent: %v\n", err)
}
