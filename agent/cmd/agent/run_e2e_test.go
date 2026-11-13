package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"slices"
	"strconv"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"remotto/agent/internal/config"
	"remotto/agent/internal/control"
	"remotto/agent/internal/discovery"
	"remotto/agent/internal/instance"
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

// bumpConfigMtime moves the config mtime 2 seconds ahead. Two writes of
// same-length tokens can share one file-time tick on Windows, so this
// guarantees the agent's stat-based reload sees the change.
func bumpConfigMtime(t *testing.T, path string) {
	t.Helper()
	now := time.Now().Add(2 * time.Second)
	if err := os.Chtimes(path, now, now); err != nil {
		t.Fatalf("chtimes config: %v", err)
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
// status deps, and fake media and power ports. It returns the base URL and a
// stop func that waits for exit.
func startAgent(t *testing.T, cfgPath string, cfg config.Config, status server.StatusDeps) (string, func()) {
	t.Helper()
	return startAgentWith(t, cfgPath, cfg, status, &fake.Media{}, &fake.Power{})
}

// startAgentWith is startAgent with the media and power ports supplied by the
// test.
func startAgentWith(t *testing.T, cfgPath string, cfg config.Config, status server.StatusDeps, media control.MediaController, power control.PowerController) (string, func()) {
	t.Helper()
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("listen: %v", err)
	}
	logger := slog.New(slog.NewJSONHandler(io.Discard, nil))
	ctx, cancel := context.WithCancel(context.Background())
	errCh := make(chan error, 1)
	go func() {
		errCh <- serveAgent(ctx, ln, logger, cfgPath, cfg, status, media, status.Audio, power)
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

// TestBR10_ServeAgentTokenResetWithoutRestart checks BR-10 through the real wiring:
// a token written to config.json replaces the old one while the agent runs.
func TestBR10_ServeAgentTokenResetWithoutRestart(t *testing.T) {
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
	bumpConfigMtime(t, cfgPath)

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
	stubAcquire(t, func() (instance.Release, error) { return func() {}, nil })
	stubDiscovery(t)

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

// TestRunWithdrawsDiscoveryBeforeHTTPCloses checks the shutdown order on
// cancel: the advertisement is withdrawn while the HTTP listener still accepts
// connections, and the listener is closed after that.
func TestRunWithdrawsDiscoveryBeforeHTTPCloses(t *testing.T) {
	t.Setenv("APPDATA", t.TempDir())
	port := freePort(t)
	cfgPath := filepath.Join(t.TempDir(), "config.json")
	writeRunConfig(t, cfgPath, port, e2eToken)
	stubAcquire(t, func() (instance.Release, error) { return func() {}, nil })

	addr := "127.0.0.1:" + strconv.Itoa(port)
	var stops atomic.Int32
	var listenerOpenAtStop atomic.Bool
	prev := startDiscovery
	startDiscovery = func(_ context.Context, _ discovery.Options) func() {
		return func() {
			stops.Add(1)
			if c, err := net.DialTimeout("tcp", addr, time.Second); err == nil {
				_ = c.Close()
				listenerOpenAtStop.Store(true)
			}
		}
	}
	t.Cleanup(func() { startDiscovery = prev })

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	var out, errOut bytes.Buffer
	done := make(chan int, 1)
	go func() {
		done <- run(ctx, []string{"run", "--config", cfgPath}, &out, &errOut)
	}()

	base := "http://" + addr
	deadline := time.Now().Add(5 * time.Second)
	for {
		if code, _ := tryStatus(base, e2eToken); code == http.StatusOK {
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

	if got := stops.Load(); got != 1 {
		t.Fatalf("discovery stop calls = %d, want 1", got)
	}
	if !listenerOpenAtStop.Load() {
		t.Error("HTTP listener was already closed when discovery was withdrawn, want it open")
	}
	if c, err := net.DialTimeout("tcp", addr, time.Second); err == nil {
		_ = c.Close()
		t.Error("HTTP listener still accepts connections after run returned")
	}
}

// TestCloseAudioClosesPortAndWarnsOnError checks shutdown of the audio port: a
// port that implements io.Closer is closed once, and a failed close is logged
// as a warning. The fake port never touches COM.
func TestCloseAudioClosesPortAndWarnsOnError(t *testing.T) {
	t.Run("closed once on success without warning", func(t *testing.T) {
		var buf bytes.Buffer
		logger := slog.New(slog.NewJSONHandler(&buf, nil))
		audio := fake.NewAudio(0, false)
		closeAudio(logger, audio)
		if got := audio.CloseCalls(); got != 1 {
			t.Fatalf("Close calls = %d, want 1", got)
		}
		if strings.Contains(buf.String(), `"level":"WARN"`) {
			t.Errorf("unexpected warning: %s", buf.String())
		}
	})

	t.Run("failed close is logged as warning", func(t *testing.T) {
		var buf bytes.Buffer
		logger := slog.New(slog.NewJSONHandler(&buf, nil))
		audio := fake.NewAudio(0, false)
		audio.SetCloseErr(errors.New("device stuck"))
		closeAudio(logger, audio)
		if got := audio.CloseCalls(); got != 1 {
			t.Fatalf("Close calls = %d, want 1", got)
		}
		out := buf.String()
		if !strings.Contains(out, `"level":"WARN"`) || !strings.Contains(out, "audio close failed") {
			t.Errorf("log = %s, want an audio close warning", out)
		}
	})

	t.Run("port without Close is skipped", func(t *testing.T) {
		logger := slog.New(slog.NewJSONHandler(io.Discard, nil))
		// unsupported has no Close method, so closeAudio must not panic.
		closeAudio(logger, unsupported{})
	})
}

// postMedia calls POST /api/v1/media/<route> with the given bearer token. An
// empty token sends no Authorization header. It returns the HTTP status and the
// decoded JSON body.
func postMedia(t *testing.T, base, route, token string) (int, map[string]any) {
	t.Helper()
	return postAPI(t, base, "/media/"+route, token)
}

// postPower calls POST /api/v1/power/<route> like postMedia does for media.
func postPower(t *testing.T, base, route, token string) (int, map[string]any) {
	t.Helper()
	return postAPI(t, base, "/power/"+route, token)
}

// postAPI calls POST /api/v1<path> with the bearer token and no body. An empty
// token sends no Authorization header.
func postAPI(t *testing.T, base, path, token string) (int, map[string]any) {
	t.Helper()
	req, err := http.NewRequest(http.MethodPost, base+"/api/v1"+path, nil)
	if err != nil {
		t.Fatal(err)
	}
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	client := &http.Client{Timeout: 3 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		t.Fatalf("POST %s: %v", path, err)
	}
	defer resp.Body.Close()
	var body map[string]any
	if err := json.NewDecoder(resp.Body).Decode(&body); err != nil {
		t.Fatalf("body is not JSON: %v", err)
	}
	return resp.StatusCode, body
}

// TestServeAgentMediaWithFakeOS covers POST /media/* end to end over a real
// loopback socket, with the fake media port held by the test.
func TestServeAgentMediaWithFakeOS(t *testing.T) {
	cfgPath := filepath.Join(t.TempDir(), "config.json")
	writeRunConfig(t, cfgPath, 8765, e2eToken)
	cfg, _, err := loadConfigFile(cfgPath)
	if err != nil {
		t.Fatalf("loadConfigFile: %v", err)
	}
	media := &fake.Media{}
	status := server.StatusDeps{Name: "x", Version: "test", StartedAt: time.Now(), Audio: fake.NewAudio(0, false)}
	base, stop := startAgentWith(t, cfgPath, cfg, status, media, &fake.Power{})
	defer stop()

	t.Run("three routes with token run in order", func(t *testing.T) {
		for _, route := range []string{"play-pause", "next", "prev"} {
			code, body := postMedia(t, base, route, e2eToken)
			if code != http.StatusOK {
				t.Fatalf("%s status = %d, want 200", route, code)
			}
			data, ok := body["data"].(map[string]any)
			if !ok || data["action"] != route {
				t.Errorf("%s body data = %v, want action %q", route, body["data"], route)
			}
		}
		want := []control.MediaAction{control.MediaPlayPause, control.MediaNext, control.MediaPrev}
		if got := media.Calls(); !slices.Equal(got, want) {
			t.Errorf("calls = %v, want %v", got, want)
		}
	})

	t.Run("no token is 401 and sends nothing", func(t *testing.T) {
		before := len(media.Calls())
		code, body := postMedia(t, base, "play-pause", "")
		if code != http.StatusUnauthorized {
			t.Fatalf("status = %d, want 401", code)
		}
		if got := errorCode(t, body); got != server.CodeInvalidToken {
			t.Errorf("error code = %q, want %q", got, server.CodeInvalidToken)
		}
		if after := len(media.Calls()); after != before {
			t.Errorf("calls went from %d to %d, want no change", before, after)
		}
	})

	t.Run("media failure is 500 media_failed without detail", func(t *testing.T) {
		media.SetErr(errors.New("secret detail"))
		defer media.SetErr(nil)
		code, body := postMedia(t, base, "next", e2eToken)
		if code != http.StatusInternalServerError {
			t.Fatalf("status = %d, want 500", code)
		}
		if got := errorCode(t, body); got != server.CodeMediaFailed {
			t.Errorf("error code = %q, want %q", got, server.CodeMediaFailed)
		}
		if strings.Contains(stringify(body), "secret detail") {
			t.Errorf("response leaks the cause: %s", stringify(body))
		}
	})

	t.Run("old token is rejected after reset without restart (BR-10)", func(t *testing.T) {
		const newToken = "fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210"
		writeRunConfig(t, cfgPath, 8765, newToken)
		bumpConfigMtime(t, cfgPath)
		before := len(media.Calls())
		if code, _ := postMedia(t, base, "play-pause", e2eToken); code != http.StatusUnauthorized {
			t.Errorf("old token status = %d, want 401", code)
		}
		if after := len(media.Calls()); after != before {
			t.Errorf("calls went from %d to %d after rejected token, want no change", before, after)
		}
		if code, _ := postMedia(t, base, "play-pause", newToken); code != http.StatusOK {
			t.Errorf("new token status = %d, want 200", code)
		}
	})
}

// volumeRequest calls method on /api/v1<path> with the bearer token. An empty
// body sends no body and no Content-Type. It returns the HTTP status and the
// decoded JSON body.
func volumeRequest(t *testing.T, base, method, path, token, body string) (int, map[string]any) {
	t.Helper()
	var reader io.Reader
	if body != "" {
		reader = strings.NewReader(body)
	}
	req, err := http.NewRequest(method, base+"/api/v1"+path, reader)
	if err != nil {
		t.Fatal(err)
	}
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	if body != "" {
		req.Header.Set("Content-Type", "application/json")
	}
	client := &http.Client{Timeout: 3 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		t.Fatalf("%s %s: %v", method, path, err)
	}
	defer resp.Body.Close()
	var out map[string]any
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		t.Fatalf("body is not JSON: %v", err)
	}
	return resp.StatusCode, out
}

// TestServeAgentVolumeWithFakeOS covers /volume end to end with the fake audio
// port: PUT /volume must be visible in GET /status, and mute/up must change the
// same state.
func TestServeAgentVolumeWithFakeOS(t *testing.T) {
	cfgPath := filepath.Join(t.TempDir(), "config.json")
	writeRunConfig(t, cfgPath, 8765, e2eToken)
	cfg, _, err := loadConfigFile(cfgPath)
	if err != nil {
		t.Fatalf("loadConfigFile: %v", err)
	}
	audio := fake.NewAudio(40, false)
	status := server.StatusDeps{Name: "x", Version: "test", StartedAt: time.Now(), Audio: audio}
	base, stop := startAgentWith(t, cfgPath, cfg, status, &fake.Media{}, &fake.Power{})
	defer stop()

	// statusVolume reads data.volume from GET /status.
	statusVolume := func(t *testing.T) (float64, bool) {
		t.Helper()
		code, body := getStatus(t, base, e2eToken)
		if code != http.StatusOK {
			t.Fatalf("status = %d, want 200", code)
		}
		v, ok := body["data"].(map[string]any)["volume"].(map[string]any)
		if !ok {
			t.Fatalf("volume = %v, want object", body["data"])
		}
		return v["level"].(float64), v["muted"].(bool)
	}

	t.Run("PUT then status shows the same volume", func(t *testing.T) {
		code, body := volumeRequest(t, base, http.MethodPut, "/volume", e2eToken, `{"level":35}`)
		if code != http.StatusOK {
			t.Fatalf("PUT status = %d, want 200", code)
		}
		data := body["data"].(map[string]any)
		if data["level"] != float64(35) || data["muted"] != false {
			t.Errorf("PUT data = %v, want level 35 muted false", data)
		}
		if level, muted := statusVolume(t); level != 35 || muted {
			t.Errorf("status volume = %v/%v, want 35/false", level, muted)
		}
	})

	t.Run("mute then up unmutes and steps by 5 (BR-15, BR-16)", func(t *testing.T) {
		code, _ := volumeRequest(t, base, http.MethodPost, "/volume/mute", e2eToken, `{"muted":true}`)
		if code != http.StatusOK {
			t.Fatalf("mute status = %d, want 200", code)
		}
		if level, muted := statusVolume(t); level != 35 || !muted {
			t.Fatalf("after mute status volume = %v/%v, want 35/true", level, muted)
		}
		code, body := volumeRequest(t, base, http.MethodPost, "/volume/up", e2eToken, "")
		if code != http.StatusOK {
			t.Fatalf("up status = %d, want 200", code)
		}
		data := body["data"].(map[string]any)
		if data["level"] != float64(40) || data["muted"] != false {
			t.Errorf("up data = %v, want level 40 muted false", data)
		}
		if level, muted := statusVolume(t); level != 40 || muted {
			t.Errorf("status volume = %v/%v, want 40/false", level, muted)
		}
	})
}

// TestServeAgentPowerWithFakeOS covers POST /power/* end to end over a real
// loopback socket, with the fake power port and the real clock. The schedule is
// cancelled right away, so the test never waits for the 5 second delay and the
// fake port must record nothing.
func TestServeAgentPowerWithFakeOS(t *testing.T) {
	cfgPath := filepath.Join(t.TempDir(), "config.json")
	writeRunConfig(t, cfgPath, 8765, e2eToken)
	cfg, _, err := loadConfigFile(cfgPath)
	if err != nil {
		t.Fatalf("loadConfigFile: %v", err)
	}
	power := &fake.Power{}
	status := server.StatusDeps{Name: "x", Version: "test", StartedAt: time.Now(), Audio: fake.NewAudio(0, false)}
	base, stop := startAgentWith(t, cfgPath, cfg, status, &fake.Media{}, power)
	defer stop()

	t.Run("schedule answers 202 and status shows the countdown", func(t *testing.T) {
		code, body := postPower(t, base, "shutdown", e2eToken)
		if code != http.StatusAccepted {
			t.Fatalf("schedule status = %d, want 202 (body %s)", code, stringify(body))
		}
		data, ok := body["data"].(map[string]any)
		if !ok {
			t.Fatalf("body has no data object: %v", body)
		}
		pending, ok := data["pending"].(map[string]any)
		if !ok || pending["action"] != "shutdown" || pending["delayMs"] != float64(5000) {
			t.Fatalf("schedule pending = %v, want action shutdown delayMs 5000", data["pending"])
		}

		code, st := getStatus(t, base, e2eToken)
		if code != http.StatusOK {
			t.Fatalf("status = %d, want 200", code)
		}
		statusPending, ok := st["data"].(map[string]any)["pending"].(map[string]any)
		if !ok || statusPending["action"] != "shutdown" || statusPending["delayMs"] != float64(5000) {
			t.Errorf("status pending = %v, want action shutdown delayMs 5000", st["data"].(map[string]any)["pending"])
		}
	})

	t.Run("cancel answers 200 and clears pending", func(t *testing.T) {
		code, body := postPower(t, base, "cancel", e2eToken)
		if code != http.StatusOK {
			t.Fatalf("cancel status = %d, want 200 (body %s)", code, stringify(body))
		}
		if data, ok := body["data"].(map[string]any); !ok || data["cancelled"] != "shutdown" {
			t.Errorf("cancel data = %v, want cancelled shutdown", body["data"])
		}

		code, st := getStatus(t, base, e2eToken)
		if code != http.StatusOK {
			t.Fatalf("status = %d, want 200", code)
		}
		if v := st["data"].(map[string]any)["pending"]; v != nil {
			t.Errorf("status pending after cancel = %v, want null", v)
		}
	})

	t.Run("cancelled command never reaches the OS port", func(t *testing.T) {
		if calls := power.Calls(); len(calls) != 0 {
			t.Errorf("power calls = %v, want none", calls)
		}
	})
}

// TestServeAgentStopDiscardsPendingPower checks that stopping the agent while a
// power command is scheduled does not run it. It does not wait for the 5 second
// delay, so it only shows that nothing ran in the short window before stop
// returns. The timer cancellation itself is tested with a fake clock in
// control.TestCloseDiscardsSchedule.
//
// stop is called once, not deferred, because it waits for serveAgent to return.
func TestServeAgentStopDiscardsPendingPower(t *testing.T) {
	cfgPath := filepath.Join(t.TempDir(), "config.json")
	writeRunConfig(t, cfgPath, 8765, e2eToken)
	cfg, _, err := loadConfigFile(cfgPath)
	if err != nil {
		t.Fatalf("loadConfigFile: %v", err)
	}
	power := &fake.Power{}
	status := server.StatusDeps{Name: "x", Version: "test", StartedAt: time.Now(), Audio: fake.NewAudio(0, false)}
	base, stop := startAgentWith(t, cfgPath, cfg, status, &fake.Media{}, power)

	if code, body := postPower(t, base, "shutdown", e2eToken); code != http.StatusAccepted {
		stop()
		t.Fatalf("schedule status = %d, want 202 (body %s)", code, stringify(body))
	}
	stop()

	if calls := power.Calls(); len(calls) != 0 {
		t.Errorf("power calls after stop = %v, want none", calls)
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

// statusResponse GETs /api/v1/status with the bearer token and returns the HTTP
// status and the Retry-After header. The body is drained and closed.
func statusResponse(t *testing.T, base, token string) (int, string) {
	t.Helper()
	req, err := http.NewRequest(http.MethodGet, base+"/api/v1/status", nil)
	if err != nil {
		t.Fatal(err)
	}
	req.Header.Set("Authorization", "Bearer "+token)
	client := &http.Client{Timeout: 3 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		t.Fatalf("GET status: %v", err)
	}
	defer resp.Body.Close()
	_, _ = io.Copy(io.Discard, resp.Body)
	return resp.StatusCode, resp.Header.Get("Retry-After")
}

// TestServeAgentRateLimitWithFakeOS covers the per-IP rate limit (FR, BR-14)
// over a real loopback socket with the default config (20 rps, burst 40). A
// fast burst of 60 requests gets both 200 and 429 with Retry-After. A slider
// rate of one request every 100 ms for about 3 s never gets 429.
func TestServeAgentRateLimitWithFakeOS(t *testing.T) {
	cfgPath := filepath.Join(t.TempDir(), "config.json")
	writeRunConfig(t, cfgPath, 8765, e2eToken)
	cfg, _, err := loadConfigFile(cfgPath)
	if err != nil {
		t.Fatalf("loadConfigFile: %v", err)
	}
	status := server.StatusDeps{Name: "x", Version: "test", StartedAt: time.Now(), Audio: fake.NewAudio(0, false)}

	t.Run("fast burst gets 200 then 429 with Retry-After", func(t *testing.T) {
		base, stop := startAgentWith(t, cfgPath, cfg, status, &fake.Media{}, &fake.Power{})
		defer stop()

		var ok, limited int
		for i := 0; i < 60; i++ {
			code, retry := statusResponse(t, base, e2eToken)
			switch code {
			case http.StatusOK:
				ok++
			case http.StatusTooManyRequests:
				limited++
				if n, err := strconv.Atoi(retry); err != nil || n < 1 {
					t.Fatalf("429 Retry-After = %q, want integer >= 1", retry)
				}
			default:
				t.Fatalf("request %d status = %d, want 200 or 429", i+1, code)
			}
		}
		if ok == 0 || limited == 0 {
			t.Fatalf("200 count = %d, 429 count = %d, want both > 0", ok, limited)
		}
	})

	t.Run("slider rate never gets 429 (BR-14)", func(t *testing.T) {
		base, stop := startAgentWith(t, cfgPath, cfg, status, &fake.Media{}, &fake.Power{})
		defer stop()

		ticker := time.NewTicker(100 * time.Millisecond)
		defer ticker.Stop()
		deadline := time.After(3 * time.Second)
		for {
			select {
			case <-deadline:
				return
			case <-ticker.C:
				code, _ := statusResponse(t, base, e2eToken)
				if code == http.StatusTooManyRequests {
					t.Fatal("slider rate got 429, want never")
				}
				if code != http.StatusOK {
					t.Fatalf("status = %d, want 200", code)
				}
			}
		}
	})
}

// wrongToken is a well-formed token that is not the configured one.
const wrongToken = "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"

// apiReply is one API response with the parts the envelope tests check.
type apiReply struct {
	status      int
	contentType string
	retryAfter  string
	body        map[string]any
}

// apiCall sends method to base+/api/v1+path with the bearer token (an empty
// token sends no Authorization header) and an optional JSON body.
func apiCall(t *testing.T, base, method, path, token, body string) apiReply {
	t.Helper()
	var reader io.Reader
	if body != "" {
		reader = strings.NewReader(body)
	}
	req, err := http.NewRequest(method, base+"/api/v1"+path, reader)
	if err != nil {
		t.Fatal(err)
	}
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	if body != "" {
		req.Header.Set("Content-Type", "application/json")
	}
	client := &http.Client{Timeout: 3 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		t.Fatalf("%s %s: %v", method, path, err)
	}
	defer resp.Body.Close()
	var out map[string]any
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		t.Fatalf("%s %s: body is not JSON: %v", method, path, err)
	}
	return apiReply{
		status:      resp.StatusCode,
		contentType: resp.Header.Get("Content-Type"),
		retryAfter:  resp.Header.Get("Retry-After"),
		body:        out,
	}
}

// exhaustBurst sends GET /status with the good token until the bucket answers
// 429. It fails if that does not happen within 100 requests.
func exhaustBurst(t *testing.T, base string) {
	t.Helper()
	for i := 0; i < 100; i++ {
		if code, _ := statusResponse(t, base, e2eToken); code == http.StatusTooManyRequests {
			return
		}
	}
	t.Fatal("bucket did not run out within 100 requests")
}

// requireRateLimited checks one 429 reply: JSON content type, error.code
// rate_limited, and an integer Retry-After of at least 1.
func requireRateLimited(t *testing.T, name string, r apiReply) {
	t.Helper()
	if r.status != http.StatusTooManyRequests {
		t.Fatalf("%s status = %d, want 429", name, r.status)
	}
	if !strings.HasPrefix(r.contentType, "application/json") {
		t.Errorf("%s Content-Type = %q, want application/json", name, r.contentType)
	}
	if code := errorCode(t, r.body); code != server.CodeRateLimited {
		t.Errorf("%s error.code = %q, want %q", name, code, server.CodeRateLimited)
	}
	if n, err := strconv.Atoi(r.retryAfter); err != nil || n < 1 {
		t.Errorf("%s Retry-After = %q, want integer >= 1", name, r.retryAfter)
	}
}

// TestServeAgentRateLimitEnvelopeAllRoutes checks that every route answers the
// rate limit with the same 429 envelope. The rate limit runs before auth, so the
// bad-token subtest also gets 429 once the bucket is empty.
func TestServeAgentRateLimitEnvelopeAllRoutes(t *testing.T) {
	cfgPath := filepath.Join(t.TempDir(), "config.json")
	writeRunConfig(t, cfgPath, 8765, e2eToken)
	cfg, _, err := loadConfigFile(cfgPath)
	if err != nil {
		t.Fatalf("loadConfigFile: %v", err)
	}
	status := server.StatusDeps{Name: "x", Version: "test", StartedAt: time.Now(), Audio: fake.NewAudio(0, false)}

	t.Run("every route gets 429 envelope with valid token", func(t *testing.T) {
		base, stop := startAgentWith(t, cfgPath, cfg, status, &fake.Media{}, &fake.Power{})
		defer stop()
		exhaustBurst(t, base)

		// Route paths and bodies follow docs/api-spec.md. The spec has no
		// /power/schedule; its schedule endpoints are /power/sleep, /restart and
		// /shutdown, so /power/shutdown is used here.
		routes := []struct {
			name, method, path, body string
		}{
			{"media play-pause", http.MethodPost, "/media/play-pause", ""},
			{"volume set", http.MethodPut, "/volume", `{"level":35}`},
			{"power shutdown", http.MethodPost, "/power/shutdown", ""},
			{"status", http.MethodGet, "/status", ""},
		}
		for _, rt := range routes {
			r := apiCall(t, base, rt.method, rt.path, e2eToken, rt.body)
			requireRateLimited(t, rt.name, r)
		}
	})

	t.Run("no token or wrong token gets 429 when bucket is empty", func(t *testing.T) {
		base, stop := startAgentWith(t, cfgPath, cfg, status, &fake.Media{}, &fake.Power{})
		defer stop()

		// Before the burst is spent, a wrong token must reach auth and get 401.
		// This shows the 429 below comes from the rate limit, not from auth.
		if r := apiCall(t, base, http.MethodGet, "/status", wrongToken, ""); r.status != http.StatusUnauthorized {
			t.Fatalf("wrong token with bucket full = %d, want 401", r.status)
		}
		exhaustBurst(t, base)

		requireRateLimited(t, "no token", apiCall(t, base, http.MethodGet, "/status", "", ""))
		requireRateLimited(t, "wrong token", apiCall(t, base, http.MethodGet, "/status", wrongToken, ""))
	})
}

// TestServeAgentResetTokenRejectsAllRoutes checks that after a token reset the
// old token gets 401 invalid_token on every kind of route, and the new token
// works. The reset uses the same config write as TestBR10.
func TestServeAgentResetTokenRejectsAllRoutes(t *testing.T) {
	cfgPath := filepath.Join(t.TempDir(), "config.json")
	writeRunConfig(t, cfgPath, 8765, e2eToken)
	cfg, _, err := loadConfigFile(cfgPath)
	if err != nil {
		t.Fatalf("loadConfigFile: %v", err)
	}
	status := server.StatusDeps{Name: "x", Version: "test", StartedAt: time.Now(), Audio: fake.NewAudio(0, false)}
	power := &fake.Power{}
	base, stop := startAgentWith(t, cfgPath, cfg, status, &fake.Media{}, power)
	defer stop()

	if code, _ := getStatus(t, base, e2eToken); code != http.StatusOK {
		t.Fatalf("old token before reset = %d, want 200", code)
	}

	const newToken = "fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210"
	writeRunConfig(t, cfgPath, 8765, newToken)
	bumpConfigMtime(t, cfgPath)

	oldRoutes := []struct {
		name, method, path, body string
	}{
		{"status", http.MethodGet, "/status", ""},
		{"media play-pause", http.MethodPost, "/media/play-pause", ""},
		{"volume set", http.MethodPut, "/volume", `{"level":35}`},
		// Spec path for schedule, see the note in the rate limit test.
		{"power shutdown", http.MethodPost, "/power/shutdown", ""},
	}
	for _, rt := range oldRoutes {
		t.Run("old token rejected on "+rt.name, func(t *testing.T) {
			r := apiCall(t, base, rt.method, rt.path, e2eToken, rt.body)
			if r.status != http.StatusUnauthorized {
				t.Fatalf("status = %d, want 401", r.status)
			}
			if code := errorCode(t, r.body); code != server.CodeInvalidToken {
				t.Errorf("error.code = %q, want %q", code, server.CodeInvalidToken)
			}
		})
	}

	if code, _ := getStatus(t, base, newToken); code != http.StatusOK {
		t.Errorf("new token after reset = %d, want 200", code)
	}
	if got := power.Calls(); len(got) != 0 {
		t.Errorf("power calls = %v, want none: rejected requests must not schedule power", got)
	}
}

// fakeDiscovery records the calls startDiscovery receives. Its stop func counts
// withdrawals. It never opens a multicast socket.
type fakeDiscovery struct {
	starts []discovery.Options
	stops  atomic.Int32
}

// stubDiscovery replaces startDiscovery for the test and restores it afterwards.
func stubDiscovery(t *testing.T) *fakeDiscovery {
	t.Helper()
	fd := &fakeDiscovery{}
	prev := startDiscovery
	startDiscovery = func(_ context.Context, opts discovery.Options) func() {
		fd.starts = append(fd.starts, opts)
		return func() { fd.stops.Add(1) }
	}
	t.Cleanup(func() { startDiscovery = prev })
	return fd
}

// readAgentIDFromConfig returns the agentId saved in the config file at path.
func readAgentIDFromConfig(t *testing.T, path string) string {
	t.Helper()
	cfg, err := config.Load(path, config.Default("host", time.Now()))
	if err != nil {
		t.Fatalf("load config: %v", err)
	}
	return cfg.AgentID
}

// TestRunOldConfigGetsAgentIDAndDiscoveryUsesIt runs the real "run" command on
// a config without agentId. EnsureAgentID must create and save one, and the
// same id must reach GET /status and the discovery Options. Stopping the agent
// must withdraw the advertisement once.
func TestRunOldConfigGetsAgentIDAndDiscoveryUsesIt(t *testing.T) {
	t.Setenv("APPDATA", t.TempDir())
	port := freePort(t)
	dir := t.TempDir()
	cfgPath := filepath.Join(dir, "config.json")
	writeRunConfig(t, cfgPath, port, e2eToken)
	if id := readAgentIDFromConfig(t, cfgPath); id != "" {
		t.Fatalf("precondition: old config has agentId %q, want empty", id)
	}
	stubAcquire(t, func() (instance.Release, error) { return func() {}, nil })
	fd := stubDiscovery(t)

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	var out, errOut bytes.Buffer
	done := make(chan int, 1)
	go func() {
		done <- run(ctx, []string{"run", "--config", cfgPath}, &out, &errOut)
	}()

	base := "http://127.0.0.1:" + strconv.Itoa(port)
	var statusID string
	deadline := time.Now().Add(5 * time.Second)
	for {
		code, body := tryStatus(base, e2eToken)
		if code == http.StatusOK {
			statusID, _ = body["data"].(map[string]any)["agentId"].(string)
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

	saved := readAgentIDFromConfig(t, cfgPath)
	if !discovery.ValidAgentID(saved) {
		t.Fatalf("saved agentId %q is not valid", saved)
	}
	if statusID != saved {
		t.Errorf("GET /status agentId = %q, saved = %q", statusID, saved)
	}
	if len(fd.starts) != 1 {
		t.Fatalf("startDiscovery calls = %d, want 1", len(fd.starts))
	}
	opts := fd.starts[0]
	if opts.AgentID != saved {
		t.Errorf("discovery AgentID = %q, want %q", opts.AgentID, saved)
	}
	if !opts.Enabled {
		t.Error("discovery Enabled = false, want true by default")
	}
	if opts.Name != "Laptop-Kamar" || opts.Port != port {
		t.Errorf("discovery Name/Port = %q/%d, want Laptop-Kamar/%d", opts.Name, opts.Port, port)
	}
	if got := fd.stops.Load(); got != 1 {
		t.Errorf("discovery stop calls = %d, want 1 after cancel", got)
	}
	logData, err := os.ReadFile(filepath.Join(dir, "logs", "agent.log"))
	if err != nil {
		t.Fatalf("read agent.log: %v", err)
	}
	if !strings.Contains(string(logData), `"event":"agent_id_created"`) {
		t.Errorf("agent.log lacks the agent_id_created event")
	}
	if strings.Contains(string(logData), saved) {
		t.Errorf("agent.log leaks the agent id value")
	}
}

// TestRunDiscoveryDisabledIsPassedThrough checks that discovery.enabled=false
// in the config reaches discovery.Options as Enabled=false.
func TestRunDiscoveryDisabledIsPassedThrough(t *testing.T) {
	t.Setenv("APPDATA", t.TempDir())
	port := freePort(t)
	cfgPath := filepath.Join(t.TempDir(), "config.json")
	cfg := config.Default("host", time.Now())
	cfg.LaptopName = "Laptop-Kamar"
	cfg.BindAddress = "127.0.0.1"
	cfg.Port = port
	cfg.Token = e2eToken
	cfg.TokenCreatedAt = "2026-01-01T00:00:00Z"
	cfg.Discovery.Enabled = false
	if err := config.Save(cfgPath, cfg); err != nil {
		t.Fatalf("save config: %v", err)
	}
	stubAcquire(t, func() (instance.Release, error) { return func() {}, nil })
	fd := stubDiscovery(t)

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
		if code, _ := tryStatus(base, e2eToken); code == http.StatusOK {
			break
		}
		if time.Now().After(deadline) {
			cancel()
			t.Fatalf("agent did not answer 200 within 5s (stderr %q)", errOut.String())
		}
		time.Sleep(50 * time.Millisecond)
	}
	cancel()
	if code := <-done; code != 0 {
		t.Fatalf("exit code = %d, want 0 (stderr %q)", code, errOut.String())
	}
	if len(fd.starts) != 1 {
		t.Fatalf("startDiscovery calls = %d, want 1", len(fd.starts))
	}
	if fd.starts[0].Enabled {
		t.Error("discovery Enabled = true, want false from config")
	}
	if !discovery.ValidAgentID(fd.starts[0].AgentID) {
		t.Errorf("discovery AgentID %q is not valid", fd.starts[0].AgentID)
	}
}
