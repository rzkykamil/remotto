package main

import (
	"context"
	"errors"
	"strings"
	"testing"

	"remotto/agent/internal/startup"
)

// fakeSchtasks stands in for schtasks. It records every call and never runs the
// real Task Scheduler.
type fakeSchtasks struct {
	calls [][]string
	out   []byte
	err   error
}

func (f *fakeSchtasks) Run(_ context.Context, name string, args ...string) ([]byte, error) {
	f.calls = append(f.calls, append([]string{name}, args...))
	return f.out, f.err
}

// stubStartup replaces newStartupManager with a Manager that uses fake for
// schtasks and fixed executable and user values, so no test touches the OS.
func stubStartup(t *testing.T, fake *fakeSchtasks) {
	t.Helper()
	prev := newStartupManager
	newStartupManager = func() *startup.Manager {
		return &startup.Manager{
			Runner:      fake,
			Executable:  func() (string, error) { return `C:\remotto\remotto-agent.exe`, nil },
			CurrentUser: func() (string, error) { return `DESKTOP\tester`, nil },
			TempDir:     t.TempDir(),
		}
	}
	t.Cleanup(func() { newStartupManager = prev })
}

func TestInstallStartupSuccess(t *testing.T) {
	fake := &fakeSchtasks{}
	stubStartup(t, fake)

	code, stdout, stderr := runApp(t, "install-startup")
	if code != 0 {
		t.Fatalf("exit code = %d, want 0 (stderr %q)", code, stderr)
	}
	if want := "autostart terpasang: agent jalan otomatis saat login\n"; stdout != want {
		t.Errorf("stdout = %q, want %q", stdout, want)
	}
	if len(fake.calls) != 1 {
		t.Fatalf("schtasks calls = %d, want 1", len(fake.calls))
	}
	call := strings.Join(fake.calls[0], " ")
	for _, want := range []string{"schtasks", "/Create", "/XML", `/TN Remotto\Agent`, "/F"} {
		if !strings.Contains(call, want) {
			t.Errorf("schtasks call %q does not contain %q", call, want)
		}
	}
}

func TestInstallStartupGenericErrorExits1WithoutRawOutput(t *testing.T) {
	const raw = "ERROR: secret raw output"
	fake := &fakeSchtasks{out: []byte(raw), err: errors.New("exit status 1")}
	stubStartup(t, fake)

	code, stdout, stderr := runApp(t, "install-startup")
	if code != 1 {
		t.Fatalf("exit code = %d, want 1", code)
	}
	if stdout != "" {
		t.Errorf("stdout = %q, want empty", stdout)
	}
	if want := "remotto-agent: failed to install startup task"; !strings.Contains(stderr, want) {
		t.Errorf("stderr = %q, want it to contain %q", stderr, want)
	}
	if strings.Contains(stderr, "secret raw output") {
		t.Errorf("stderr leaks raw schtasks output: %q", stderr)
	}
}

func TestInstallStartupNeedAdminSuggestsAdministratorTerminal(t *testing.T) {
	fake := &fakeSchtasks{out: []byte("ERROR: Access is denied."), err: errors.New("exit status 1")}
	stubStartup(t, fake)

	code, _, stderr := runApp(t, "install-startup")
	if code != 1 {
		t.Fatalf("exit code = %d, want 1", code)
	}
	if !strings.Contains(stderr, "Administrator") {
		t.Errorf("stderr = %q, want it to suggest an Administrator terminal", stderr)
	}
}

func TestInstallStartupExtraArgsExits2WithoutSchtasks(t *testing.T) {
	fake := &fakeSchtasks{}
	stubStartup(t, fake)

	code, _, stderr := runApp(t, "install-startup", "extra")
	if code != 2 {
		t.Fatalf("exit code = %d, want 2", code)
	}
	if !strings.Contains(stderr, "extra") {
		t.Errorf("stderr = %q, want it to name the extra argument", stderr)
	}
	if len(fake.calls) != 0 {
		t.Errorf("schtasks calls = %d, want 0", len(fake.calls))
	}
}

func TestUninstallStartupSuccess(t *testing.T) {
	fake := &fakeSchtasks{}
	stubStartup(t, fake)

	code, stdout, stderr := runApp(t, "uninstall-startup")
	if code != 0 {
		t.Fatalf("exit code = %d, want 0 (stderr %q)", code, stderr)
	}
	if want := "autostart dihapus\n"; stdout != want {
		t.Errorf("stdout = %q, want %q", stdout, want)
	}
	if len(fake.calls) != 1 || !strings.Contains(strings.Join(fake.calls[0], " "), "/Delete") {
		t.Errorf("schtasks calls = %v, want one /Delete call", fake.calls)
	}
}

// TestUninstallStartupNotInstalledIsIdempotent checks that a missing task is
// reported as removed and exits 0.
func TestUninstallStartupNotInstalledIsIdempotent(t *testing.T) {
	fake := &fakeSchtasks{
		out: []byte("ERROR: The system cannot find the file specified."),
		err: errors.New("exit status 1"),
	}
	stubStartup(t, fake)

	code, stdout, stderr := runApp(t, "uninstall-startup")
	if code != 0 {
		t.Fatalf("exit code = %d, want 0 (stderr %q)", code, stderr)
	}
	if want := "autostart dihapus\n"; stdout != want {
		t.Errorf("stdout = %q, want %q", stdout, want)
	}
}

func TestUninstallStartupNeedAdminExits1(t *testing.T) {
	fake := &fakeSchtasks{out: []byte("ERROR: Access is denied."), err: errors.New("exit status 1")}
	stubStartup(t, fake)

	code, _, stderr := runApp(t, "uninstall-startup")
	if code != 1 {
		t.Fatalf("exit code = %d, want 1", code)
	}
	if !strings.Contains(stderr, "Administrator") {
		t.Errorf("stderr = %q, want it to suggest an Administrator terminal", stderr)
	}
}

func TestUninstallStartupGenericErrorExits1(t *testing.T) {
	fake := &fakeSchtasks{out: []byte("ERROR: boom"), err: errors.New("exit status 1")}
	stubStartup(t, fake)

	code, _, stderr := runApp(t, "uninstall-startup")
	if code != 1 {
		t.Fatalf("exit code = %d, want 1", code)
	}
	if want := "remotto-agent: failed to remove startup task"; !strings.Contains(stderr, want) {
		t.Errorf("stderr = %q, want it to contain %q", stderr, want)
	}
}

func TestUninstallStartupExtraArgsExits2WithoutSchtasks(t *testing.T) {
	fake := &fakeSchtasks{}
	stubStartup(t, fake)

	code, _, _ := runApp(t, "uninstall-startup", "extra")
	if code != 2 {
		t.Fatalf("exit code = %d, want 2", code)
	}
	if len(fake.calls) != 0 {
		t.Errorf("schtasks calls = %d, want 0", len(fake.calls))
	}
}

func TestUsageTextNoLongerMarksStartupUnavailable(t *testing.T) {
	for _, name := range []string{"install-startup", "uninstall-startup"} {
		for _, line := range strings.Split(usageText, "\n") {
			if strings.Contains(line, name) && strings.Contains(line, "belum tersedia") {
				t.Errorf("usage line %q still marks %s as unavailable", line, name)
			}
		}
		if !strings.Contains(usageText, name) {
			t.Errorf("usage text does not list %s", name)
		}
	}
	if !strings.Contains(usageText, "reset-token") || !strings.Contains(usageText, "belum tersedia") {
		t.Errorf("reset-token must keep its unavailable note")
	}
}
