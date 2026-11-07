package main

import (
	"bytes"
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// runApp calls run with a throwaway APPDATA so no test can touch the real
// %APPDATA%\Remotto. The tests never open a listener.
func runApp(t *testing.T, args ...string) (code int, stdout, stderr string) {
	t.Helper()
	t.Setenv("APPDATA", t.TempDir())
	var out, errOut bytes.Buffer
	code = run(context.Background(), args, &out, &errOut)
	return code, out.String(), errOut.String()
}

func TestRunWithoutArgsPrintsUsageAndExits2(t *testing.T) {
	code, _, stderr := runApp(t)
	if code != 2 {
		t.Fatalf("exit code = %d, want 2", code)
	}
	if !strings.Contains(stderr, "Usage") {
		t.Errorf("stderr does not contain usage: %q", stderr)
	}
}

func TestHelpExitsZeroAndPrintsUsage(t *testing.T) {
	for _, arg := range []string{"help", "-h", "--help"} {
		t.Run(arg, func(t *testing.T) {
			code, stdout, _ := runApp(t, arg)
			if code != 0 {
				t.Fatalf("exit code = %d, want 0", code)
			}
			if !strings.Contains(stdout, "Usage") {
				t.Errorf("stdout does not contain usage: %q", stdout)
			}
		})
	}
}

func TestVersionPrintsVersion(t *testing.T) {
	code, stdout, stderr := runApp(t, "version")
	if code != 0 {
		t.Fatalf("exit code = %d, want 0 (stderr %q)", code, stderr)
	}
	if want := "remotto-agent dev\n"; stdout != want {
		t.Errorf("stdout = %q, want %q", stdout, want)
	}
}

func TestUnknownSubcommandExits2(t *testing.T) {
	code, _, stderr := runApp(t, "foo")
	if code != 2 {
		t.Fatalf("exit code = %d, want 2", code)
	}
	if !strings.Contains(stderr, "foo") {
		t.Errorf("stderr does not name the subcommand: %q", stderr)
	}
}

func TestPlannedSubcommandsAreUnavailable(t *testing.T) {
	// pair (M1), reset-token (M1), install-startup and uninstall-startup (M6).
	for _, name := range []string{"pair", "reset-token", "install-startup", "uninstall-startup"} {
		t.Run(name, func(t *testing.T) {
			code, _, stderr := runApp(t, name)
			if code != 1 {
				t.Fatalf("exit code = %d, want 1", code)
			}
			if !strings.Contains(stderr, "belum tersedia") {
				t.Errorf("stderr = %q, want message containing %q", stderr, "belum tersedia")
			}
		})
	}
}

func TestRunHelpFlagExitsZero(t *testing.T) {
	code, _, _ := runApp(t, "run", "-h")
	if code != 0 {
		t.Fatalf("exit code = %d, want 0", code)
	}
}

func TestRunUnknownFlagExits2(t *testing.T) {
	code, _, stderr := runApp(t, "run", "--bogus")
	if code != 2 {
		t.Fatalf("exit code = %d, want 2", code)
	}
	if !strings.Contains(stderr, "bogus") {
		t.Errorf("stderr does not name the flag: %q", stderr)
	}
}

func TestRunRejectsPositionalArgs(t *testing.T) {
	code, _, _ := runApp(t, "run", "extra")
	if code != 2 {
		t.Fatalf("exit code = %d, want 2", code)
	}
}

// TestRunInvalidConfigFailsBeforeLogAndListener checks that validation runs
// before the log file and the listener are created: no agent.log may appear.
func TestRunInvalidConfigFailsBeforeLogAndListener(t *testing.T) {
	tests := []struct {
		name      string
		content   string
		wantField string
	}{
		{name: "port below range", content: `{"port": 80}`, wantField: `"port"`},
		{name: "unknown log level", content: `{"logLevel": "loud"}`, wantField: `"logLevel"`},
		{name: "malformed json", content: `{"port":`, wantField: "parse config"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			dir := t.TempDir()
			cfgPath := filepath.Join(dir, "config.json")
			if err := os.WriteFile(cfgPath, []byte(tt.content), 0o600); err != nil {
				t.Fatal(err)
			}

			code, _, stderr := runApp(t, "run", "--config", cfgPath)
			if code != 1 {
				t.Fatalf("exit code = %d, want 1 (stderr %q)", code, stderr)
			}
			if !strings.Contains(stderr, tt.wantField) {
				t.Errorf("stderr = %q, want it to mention %q", stderr, tt.wantField)
			}
			if _, err := os.Stat(filepath.Join(dir, "logs")); !os.IsNotExist(err) {
				t.Errorf("logs folder exists or stat failed (%v); validation must run before logging", err)
			}
		})
	}
}
