package main

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"net"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"remotto/agent/internal/instance"
)

// stubAcquire replaces acquireInstance for the test and restores it afterwards.
func stubAcquire(t *testing.T, fn func() (instance.Release, error)) {
	t.Helper()
	prev := acquireInstance
	acquireInstance = fn
	t.Cleanup(func() { acquireInstance = prev })
}

// runApp calls run with a throwaway APPDATA so no test can touch the real
// %APPDATA%\Remotto. The tests never open a listener.
func runApp(t *testing.T, args ...string) (code int, stdout, stderr string) {
	t.Helper()
	t.Setenv("APPDATA", t.TempDir())
	stubAcquire(t, func() (instance.Release, error) { return func() {}, nil })
	stubDiscovery(t)
	var out, errOut bytes.Buffer
	code = run(context.Background(), args, &out, &errOut)
	return code, out.String(), errOut.String()
}

// TestRunExitsWhenAgentAlreadyRunning checks that a second agent stops before
// it reads the config, creates the logs folder or opens a listener.
func TestRunExitsWhenAgentAlreadyRunning(t *testing.T) {
	t.Setenv("APPDATA", t.TempDir())
	dir := t.TempDir()
	cfgPath := filepath.Join(dir, "config.json")
	calls := 0
	stubAcquire(t, func() (instance.Release, error) {
		calls++
		return nil, instance.ErrAlreadyRunning
	})

	var out, errOut bytes.Buffer
	code := run(context.Background(), []string{"run", "--config", cfgPath}, &out, &errOut)
	if code != 1 {
		t.Fatalf("exit code = %d, want 1 (stderr %q)", code, errOut.String())
	}
	if calls != 1 {
		t.Errorf("acquireInstance calls = %d, want 1", calls)
	}
	if want := "agent sudah berjalan di sesi ini"; !strings.Contains(errOut.String(), want) {
		t.Errorf("stderr = %q, want it to contain %q", errOut.String(), want)
	}
	if _, err := os.Stat(cfgPath); !errors.Is(err, os.ErrNotExist) {
		t.Errorf("config exists or stat failed (%v); lock must be taken before config", err)
	}
	if _, err := os.Stat(filepath.Join(dir, "logs")); !errors.Is(err, os.ErrNotExist) {
		t.Errorf("logs folder exists or stat failed (%v); lock must be taken before logging", err)
	}
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
	// Only reset-token (M5) is still planned. install-startup and
	// uninstall-startup are implemented (M6) and covered in startup_test.go.
	for _, name := range []string{"reset-token"} {
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
		{name: "port below range", content: `{"configVersion": 1, "port": 80}`, wantField: `"port"`},
		{name: "unknown log level", content: `{"configVersion": 1, "logLevel": "loud"}`, wantField: `"logLevel"`},
		{name: "newer configVersion", content: `{"configVersion": 99}`, wantField: "newer"},
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

// stubDetach replaces detach for the test and restores it afterwards. It
// returns a pointer to the number of calls. Tests never call FreeConsole.
func stubDetach(t *testing.T, fn func() error) *int {
	t.Helper()
	calls := new(int)
	prev := detach
	detach = func() error {
		*calls++
		return fn()
	}
	t.Cleanup(func() { detach = prev })
	return calls
}

// busyPortConfig writes a valid config that listens on a loopback port held by
// the test. run then fails at listen, after the logger is ready and before any
// server starts. It returns the config path and the agent.log path.
func busyPortConfig(t *testing.T) (cfgPath, logPath string) {
	t.Helper()
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("listen: %v", err)
	}
	t.Cleanup(func() { _ = ln.Close() })
	dir := t.TempDir()
	cfgPath = filepath.Join(dir, "config.json")
	writeRunConfig(t, cfgPath, ln.Addr().(*net.TCPAddr).Port, e2eToken)
	return cfgPath, filepath.Join(dir, "logs", "agent.log")
}

func TestRunWithoutBackgroundDoesNotDetach(t *testing.T) {
	cfgPath, _ := busyPortConfig(t)
	calls := stubDetach(t, func() error { return nil })

	code, _, _ := runApp(t, "run", "--config", cfgPath)
	if code != 1 {
		t.Fatalf("exit code = %d, want 1 (listen fails on the busy port)", code)
	}
	if *calls != 0 {
		t.Errorf("detach calls = %d, want 0 without --background", *calls)
	}
}

func TestRunBackgroundDetachesOnceBeforeLogger(t *testing.T) {
	cfgPath, logPath := busyPortConfig(t)
	logsDir := filepath.Dir(logPath)
	logsExisted := true
	calls := stubDetach(t, func() error {
		_, err := os.Stat(logsDir)
		logsExisted = err == nil
		return nil
	})

	code, _, stderr := runApp(t, "run", "--config", cfgPath, "--background")
	if code != 1 {
		t.Fatalf("exit code = %d, want 1 (stderr %q)", code, stderr)
	}
	if *calls != 1 {
		t.Errorf("detach calls = %d, want 1", *calls)
	}
	if logsExisted {
		t.Error("logs folder existed at detach time; detach must run before the logger is opened")
	}
}

func TestRunBackgroundKeepsStderrFreeOfLogLines(t *testing.T) {
	cfgPath, logPath := busyPortConfig(t)
	stubDetach(t, func() error { return nil })

	code, _, stderr := runApp(t, "run", "--config", cfgPath, "--background")
	if code != 1 {
		t.Fatalf("exit code = %d, want 1 (stderr %q)", code, stderr)
	}
	for _, line := range strings.Split(stderr, "\n") {
		if strings.HasPrefix(strings.TrimSpace(line), "{") {
			t.Errorf("stderr has a JSON log line in background mode: %q", line)
		}
	}
	data, err := os.ReadFile(logPath)
	if err != nil {
		t.Fatalf("read agent.log: %v", err)
	}
	if !strings.Contains(string(data), `"msg":"listen failed"`) {
		t.Errorf("agent.log = %q, want the listen failure line", string(data))
	}
}

func TestRunForegroundWritesLogLinesToStderr(t *testing.T) {
	cfgPath, _ := busyPortConfig(t)

	code, _, stderr := runApp(t, "run", "--config", cfgPath)
	if code != 1 {
		t.Fatalf("exit code = %d, want 1 (stderr %q)", code, stderr)
	}
	if !strings.Contains(stderr, `"msg":"listen failed"`) {
		t.Errorf("stderr = %q, want the JSON log line without --background", stderr)
	}
}

func TestRunBackgroundDetachFailureIsLoggedAndRunContinues(t *testing.T) {
	cfgPath, logPath := busyPortConfig(t)
	calls := stubDetach(t, func() error { return errors.New("no console") })

	code, _, stderr := runApp(t, "run", "--config", cfgPath, "--background")
	if code != 1 {
		t.Fatalf("exit code = %d, want 1 (stderr %q)", code, stderr)
	}
	if *calls != 1 {
		t.Errorf("detach calls = %d, want 1", *calls)
	}
	data, err := os.ReadFile(logPath)
	if err != nil {
		t.Fatalf("read agent.log: %v", err)
	}
	if !strings.Contains(string(data), "console detach failed") {
		t.Errorf("agent.log = %q, want the detach warning", string(data))
	}
	if !strings.Contains(string(data), `"msg":"listen failed"`) {
		t.Errorf("agent.log = %q, want run to continue to listen after detach failure", string(data))
	}
}

// TestListenAgentBusyPortReturnsFriendlyError checks that a port held by another
// program yields the readable message, naming the port and the config key.
func TestListenAgentBusyPortReturnsFriendlyError(t *testing.T) {
	held, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("listen: %v", err)
	}
	defer func() { _ = held.Close() }()
	port := held.Addr().(*net.TCPAddr).Port

	ln, err := listenAgent(fmt.Sprintf("127.0.0.1:%d", port), port)
	if err == nil {
		_ = ln.Close()
		t.Fatal("listenAgent on a busy port returned no error")
	}
	for _, want := range []string{"sudah dipakai", fmt.Sprint(port), `"port"`} {
		if !strings.Contains(err.Error(), want) {
			t.Errorf("error = %q, want it to contain %q", err.Error(), want)
		}
	}
}

// TestListenAgentOtherErrorIsUnchanged checks that an error that is not a busy
// port is returned as is, without the friendly message.
func TestListenAgentOtherErrorIsUnchanged(t *testing.T) {
	const addr = "127.0.0.1:99999"
	_, want := net.Listen("tcp", addr)
	if want == nil {
		t.Skip("address unexpectedly listenable; cannot test a non-busy error")
	}
	_, err := listenAgent(addr, 8765)
	if err == nil {
		t.Fatal("listenAgent returned no error for an invalid address")
	}
	if err.Error() != want.Error() {
		t.Errorf("error = %q, want the unchanged %q", err.Error(), want.Error())
	}
	if strings.Contains(err.Error(), "sudah dipakai") {
		t.Errorf("non-busy error got the busy-port message: %q", err.Error())
	}
}

// TestRunBusyPortExitsOneWithFriendlyStderr checks, end to end through run, that
// a busy port exits 1, prints the readable message with the address, and never
// prints the token.
func TestRunBusyPortExitsOneWithFriendlyStderr(t *testing.T) {
	held, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("listen: %v", err)
	}
	defer func() { _ = held.Close() }()
	port := held.Addr().(*net.TCPAddr).Port

	dir := t.TempDir()
	cfgPath := filepath.Join(dir, "config.json")
	writeRunConfig(t, cfgPath, port, e2eToken)

	code, _, stderr := runApp(t, "run", "--config", cfgPath)
	if code != 1 {
		t.Fatalf("exit code = %d, want 1 (stderr %q)", code, stderr)
	}
	if !strings.Contains(stderr, "sudah dipakai") {
		t.Errorf("stderr = %q, want it to contain %q", stderr, "sudah dipakai")
	}
	if want := fmt.Sprintf("127.0.0.1:%d", port); !strings.Contains(stderr, want) {
		t.Errorf("stderr = %q, want the address %q", stderr, want)
	}
	if strings.Contains(stderr, e2eToken) {
		t.Errorf("stderr leaks the token: %q", stderr)
	}
}
