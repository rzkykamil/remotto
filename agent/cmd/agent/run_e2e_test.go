package main

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"remotto/agent/internal/config"
	"remotto/agent/internal/control"
	"remotto/agent/internal/oscontrol/fake"
	"remotto/agent/internal/pairing"
	"remotto/agent/internal/server"
)

const e2eToken = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

// writeRunConfig saves a valid config that listens on 127.0.0.1:port.
func writeRunConfig(t *testing.T, path string, port int, token string) {
	t.Helper()
	cfg := config.Default("host", time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC))
	cfg.LaptopName = "Laptop-Kamar"
	cfg.BindAddress = "127.0.0.1"
	cfg.Port = port
	cfg.Token = token
	cfg.TokenCreatedAt = "2026-01-01T00:00:00Z"
	if err := config.Save(path, cfg); err != nil {
		t.Fatalf("save config: %v", err)
	}
}

// freePort returns a loopback TCP port that was free a moment ago.
func freePort(t *testing.T) int {
	t.Helper()
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("listen: %v", err)
	}
	defer ln.Close()
	return ln.Addr().(*net.TCPAddr).Port
}

// getStatus calls GET /api/v1/status. An empty token sends no Authorization
// header. It returns the HTTP status and the decoded JSON body.
func getStatus(t *testing.T, base, token string) (int, map[string]any) {
	t.Helper()
	req, err := http.NewRequest(http.MethodGet, base+"/api/v1/status", nil)
	if err != nil {
		t.Fatal(err)
	}
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	client := &http.Client{Timeout: 3 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		t.Fatalf("GET status: %v", err)
	}
	defer resp.Body.Close()
	raw, err := io.ReadAll(resp.Body)
	if err != nil {
		t.Fatalf("read body: %v", err)
	}
	var body map[string]any
	if err := json.Unmarshal(raw, &body); err != nil {
		t.Fatalf("body is not JSON: %q: %v", raw, err)
	}
	return resp.StatusCode, body
}

// errorCode returns error.code from an error envelope.
func errorCode(t *testing.T, body map[string]any) string {
	t.Helper()
	e, ok := body["error"].(map[string]any)
	if !ok {
		t.Fatalf("body has no error object: %v", body)
	}
	code, _ := e["code"].(string)
	return code
}

// startAgent serves the API on a loopback listener with the given config and
// status deps. It returns the base URL and a stop func that waits for exit.
func startAgent(t *testing.T, cfgPath string, cfg config.Config, status server.StatusDeps) (string, func()) {
	t.Helper()
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("listen: %v", err)
	}
	logger := slog.New(slog.NewJSONHandler(io.Discard, nil))
	ctx, cancel := context.WithCancel(context.Background())
	errCh := make(chan error, 1)
	go func() {
		errCh <- serveAgent(ctx, ln, logger, cfgPath, cfg, status)
	}()
	stop := func() {
		cancel()
		select {
		case err := <-errCh:
			if err != nil {
				t.Errorf("serveAgent returned error: %v", err)
			}
		case <-time.After(10 * time.Second):
			t.Error("serveAgent did not stop within 10s")
		}
	}
	return "http://" + ln.Addr().String(), stop
}

func TestLoadConfigFileFirstRunCreatesConfigWithToken(t *testing.T) {
	path := filepath.Join(t.TempDir(), "sub", "config.json")
	cfg, events, err := loadConfigFile(path)
	if err != nil {
		t.Fatalf("loadConfigFile: %v", err)
	}
	if !pairing.ValidToken(cfg.Token) {
		t.Fatalf("token %q does not match the token format", cfg.Token)
	}
	if !hasEvent(events, config.EventFirstRun) {
		t.Fatalf("events = %+v, want a first_run event", events)
	}
	if _, err := os.Stat(path); err != nil {
		t.Fatalf("config not created: %v", err)
	}
}

func TestLoadConfigFileCorruptIsMovedAsideAndReplaced(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.json")
	const broken = `{"port":`
	if err := os.WriteFile(path, []byte(broken), 0o600); err != nil {
		t.Fatal(err)
	}

	cfg, events, err := loadConfigFile(path)
	if err != nil {
		t.Fatalf("loadConfigFile: %v", err)
	}
	if !hasEvent(events, config.EventCorruptReplaced) {
		t.Fatalf("events = %+v, want a corrupt_replaced event", events)
	}
	moved, err := os.ReadFile(path + ".corrupt")
	if err != nil {
		t.Fatalf("corrupt file missing: %v", err)
	}
	if string(moved) != broken {
		t.Errorf("corrupt file content = %q, want original %q", moved, broken)
	}
	if !pairing.ValidToken(cfg.Token) {
		t.Errorf("replacement token %q is invalid", cfg.Token)
	}
}

// TestBR11_LogEventNeverRecordsToken checks the first-run event (T9) writes no
// token value to the log.
func TestBR11_LogEventNeverRecordsToken(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.json")
	cfg, events, err := loadConfigFile(path)
	if err != nil {
		t.Fatalf("loadConfigFile: %v", err)
	}
	var buf bytes.Buffer
	logger := slog.New(slog.NewJSONHandler(&buf, nil))
	for _, ev := range events {
		logEvent(logger, ev)
	}
	out := buf.String()
	if !strings.Contains(out, `"event":"first_run"`) {
		t.Errorf("log lacks first_run event: %q", out)
	}
	if strings.Contains(out, cfg.Token) {
		t.Errorf("log contains token value: %q", out)
	}
}

// TestServeAgentStatusWithFakeOS covers GET /status end to end over a real
// loopback socket, with the fake audio port and a fake clock.
func TestServeAgentStatusWithFakeOS(t *testing.T) {
	cfgPath := filepath.Join(t.TempDir(), "config.json")
	writeRunConfig(t, cfgPath, 8765, e2eToken)
	cfg, _, err := loadConfigFile(cfgPath)
	if err != nil {
		t.Fatalf("loadConfigFile: %v", err)
	}

	audio := fake.NewAudio(40, false)
	var offset atomic.Int64 // seconds added to the start time
	start := time.Date(2026, 1, 1, 12, 0, 0, 0, time.UTC)
	status := server.StatusDeps{
		Name:      cfg.LaptopName,
		Version:   "test",
		StartedAt: start,
		Now: func() time.Time {
			return start.Add(time.Duration(offset.Load()) * time.Second)
		},
		Audio: audio,
	}
	base, stop := startAgent(t, cfgPath, cfg, status)
	defer stop()

	t.Run("no token is 401", func(t *testing.T) {
		code, body := getStatus(t, base, "")
		if code != http.StatusUnauthorized {
			t.Fatalf("status = %d, want 401", code)
		}
		if got := errorCode(t, body); got != server.CodeInvalidToken {
			t.Errorf("error code = %q, want %q", got, server.CodeInvalidToken)
		}
	})

	t.Run("valid token returns data envelope", func(t *testing.T) {
		code, body := getStatus(t, base, e2eToken)
		if code != http.StatusOK {
			t.Fatalf("status = %d, want 200", code)
		}
		data, ok := body["data"].(map[string]any)
		if !ok {
			t.Fatalf("body has no data object: %v", body)
		}
		if data["name"] != "Laptop-Kamar" || data["version"] != "test" {
			t.Errorf("name/version = %v/%v", data["name"], data["version"])
		}
		if _, exists := data["pending"]; !exists || data["pending"] != nil {
			t.Errorf("pending = %v (present %v), want null", data["pending"], exists)
		}
		volume, ok := data["volume"].(map[string]any)
		if !ok || volume["level"] != float64(40) || volume["muted"] != false {
			t.Errorf("volume = %v, want level 40 muted false", data["volume"])
		}
		if strings.Contains(strings.ToLower(stringify(body)), e2eToken) {
			t.Errorf("response contains the token")
		}
	})

	t.Run("uptime follows the clock", func(t *testing.T) {
		offset.Store(10)
		_, first := getStatus(t, base, e2eToken)
		offset.Store(52)
		_, second := getStatus(t, base, e2eToken)
		u1 := first["data"].(map[string]any)["uptimeSeconds"].(float64)
		u2 := second["data"].(map[string]any)["uptimeSeconds"].(float64)
		if u1 != 10 || u2 != 52 {
			t.Errorf("uptime = %v then %v, want 10 then 52", u1, u2)
		}
	})

	t.Run("unsupported volume reports null and still 200", func(t *testing.T) {
		audio.SetErr(control.ErrUnsupported)
		defer audio.SetErr(nil)
		code, body := getStatus(t, base, e2eToken)
		if code != http.StatusOK {
			t.Fatalf("status = %d, want 200", code)
		}
		data := body["data"].(map[string]any)
		if v, exists := data["volume"]; !exists || v != nil {
			t.Errorf("volume = %v (present %v), want null", v, exists)
		}
	})
}

// TestServeAgentTokenResetWithoutRestart checks BR-10 through the real wiring:
// a token written to config.json replaces the old one while the agent runs.
func TestServeAgentTokenResetWithoutRestart(t *testing.T) {
	cfgPath := filepath.Join(t.TempDir(), "config.json")
	writeRunConfig(t, cfgPath, 8765, e2eToken)
	cfg, _, err := loadConfigFile(cfgPath)
	if err != nil {
		t.Fatalf("loadConfigFile: %v", err)
	}
	status := server.StatusDeps{Name: "x", Version: "test", StartedAt: time.Now(), Audio: fake.NewAudio(0, false)}
	base, stop := startAgent(t, cfgPath, cfg, status)
	defer stop()

	if code, _ := getStatus(t, base, e2eToken); code != http.StatusOK {
		t.Fatalf("old token status = %d, want 200", code)
	}

	const newToken = "fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210"
	writeRunConfig(t, cfgPath, 8765, newToken)

	if code, _ := getStatus(t, base, e2eToken); code != http.StatusUnauthorized {
		t.Errorf("old token after reset = %d, want 401", code)
	}
	if code, _ := getStatus(t, base, newToken); code != http.StatusOK {
		t.Errorf("new token after reset = %d, want 200", code)
	}
}

// TestRunStartsFromConfigAndStopsOnCancel runs the real "run" command with a
// config on a free loopback port, then cancels it and expects exit 0.
func TestRunStartsFromConfigAndStopsOnCancel(t *testing.T) {
	t.Setenv("APPDATA", t.TempDir())
	port := freePort(t)
	cfgPath := filepath.Join(t.TempDir(), "config.json")
	writeRunConfig(t, cfgPath, port, e2eToken)

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	var out, errOut bytes.Buffer
	done := make(chan int, 1)
	go func() {
		done <- run(ctx, []string{"run", "--config", cfgPath}, &out, &errOut)
	}()

	base := "http://127.0.0.1:" + strconv.Itoa(port)
	deadline := time.Now().Add(5 * time.Second)
	for {
		code, body := tryStatus(base, e2eToken)
		if code == http.StatusOK {
			data := body["data"].(map[string]any)
			if data["name"] != "Laptop-Kamar" {
				t.Errorf("name = %v, want Laptop-Kamar", data["name"])
			}
			break
		}
		if time.Now().After(deadline) {
			cancel()
			t.Fatalf("agent did not answer 200 within 5s (stderr %q)", errOut.String())
		}
		time.Sleep(50 * time.Millisecond)
	}

	cancel()
	select {
	case code := <-done:
		if code != 0 {
			t.Fatalf("exit code = %d, want 0 (stderr %q)", code, errOut.String())
		}
	case <-time.After(10 * time.Second):
		t.Fatal("run did not return within 10s after cancel")
	}
}

// tryStatus is getStatus without t.Fatal, for polling while the agent starts.
func tryStatus(base, token string) (int, map[string]any) {
	req, err := http.NewRequest(http.MethodGet, base+"/api/v1/status", nil)
	if err != nil {
		return 0, nil
	}
	req.Header.Set("Authorization", "Bearer "+token)
	client := &http.Client{Timeout: time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return 0, nil
	}
	defer resp.Body.Close()
	var body map[string]any
	_ = json.NewDecoder(resp.Body).Decode(&body)
	return resp.StatusCode, body
}

// stringify renders v as JSON text for substring checks.
func stringify(v any) string {
	b, _ := json.Marshal(v)
	return string(b)
}

// hasEvent reports whether events contains kind. Extra events such as
// perm_fixed depend on the temp folder permissions and are not checked here.
func hasEvent(events []config.Event, kind config.EventKind) bool {
	for _, ev := range events {
		if ev.Kind == kind {
			return true
		}
	}
	return false
}
