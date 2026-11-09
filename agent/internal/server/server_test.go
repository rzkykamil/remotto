package server

import (
	"bytes"
	"context"
	"io"
	"log/slog"
	"net"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	"remotto/agent/internal/control"
)

// syncBuffer is a bytes.Buffer safe for concurrent writes from server goroutines.
type syncBuffer struct {
	mu  sync.Mutex
	buf bytes.Buffer
}

func (s *syncBuffer) Write(p []byte) (int, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.buf.Write(p)
}

func (s *syncBuffer) String() string {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.buf.String()
}

func TestNewHTTPServerTimeouts(t *testing.T) {
	srv := NewHTTPServer("127.0.0.1:0", http.NotFoundHandler())

	tests := []struct {
		name string
		got  time.Duration
		want time.Duration
	}{
		{"ReadHeaderTimeout", srv.ReadHeaderTimeout, 2 * time.Second},
		{"ReadTimeout", srv.ReadTimeout, 3 * time.Second},
		{"WriteTimeout", srv.WriteTimeout, 5 * time.Second},
		{"IdleTimeout", srv.IdleTimeout, 60 * time.Second},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if tt.got != tt.want {
				t.Fatalf("%s = %v, want %v", tt.name, tt.got, tt.want)
			}
		})
	}
	if srv.MaxHeaderBytes != 8<<10 {
		t.Fatalf("MaxHeaderBytes = %d, want %d", srv.MaxHeaderBytes, 8<<10)
	}
	if srv.Addr != "127.0.0.1:0" {
		t.Fatalf("Addr = %q, want %q", srv.Addr, "127.0.0.1:0")
	}
}

func TestNewHandlerRecoversPanicAndLogsRequests(t *testing.T) {
	router := NewRouter()
	router.Handle(http.MethodGet, "/api/v1/ping", http.HandlerFunc(func(http.ResponseWriter, *http.Request) {
		panic("boom")
	}))

	var buf bytes.Buffer
	h := NewHandler(router, newTestLogger(&buf))

	tests := []struct {
		name       string
		path       string
		wantStatus int
		wantCode   string
	}{
		{"panicking route", "/api/v1/ping", http.StatusInternalServerError, CodeInternal},
		{"unknown route", "/api/v1/unknown", http.StatusNotFound, CodeNotFound},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			rec := httptest.NewRecorder()
			h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, tt.path, nil))
			if rec.Code != tt.wantStatus {
				t.Fatalf("status = %d, want %d", rec.Code, tt.wantStatus)
			}
			if !bytes.Contains(rec.Body.Bytes(), []byte(`"code":"`+tt.wantCode+`"`)) {
				t.Fatalf("body %q missing code %q", rec.Body.String(), tt.wantCode)
			}
		})
	}

	lines := requestLines(t, &buf)
	if len(lines) != 2 {
		t.Fatalf("request log lines = %d, want 2", len(lines))
	}
	if lines[0]["status"] != float64(http.StatusInternalServerError) {
		t.Errorf("first request status = %v, want 500", lines[0]["status"])
	}
	if lines[1]["status"] != float64(http.StatusNotFound) {
		t.Errorf("second request status = %v, want 404", lines[1]["status"])
	}
}

func TestServeStopsGracefully(t *testing.T) {
	router := NewRouter()
	router.Handle(http.MethodGet, "/api/v1/ping", http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = io.WriteString(w, "pong")
	}))

	var buf syncBuffer
	logger := slog.New(slog.NewJSONHandler(&buf, nil))

	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("listen: %v", err)
	}
	addr := ln.Addr().String()
	srv := NewHTTPServer(addr, NewHandler(router, logger))

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	errCh := make(chan error, 1)
	go func() {
		errCh <- Serve(ctx, srv, ln, logger)
	}()

	client := &http.Client{Timeout: 2 * time.Second}
	resp, err := client.Get("http://" + addr + "/api/v1/ping")
	if err != nil {
		cancel()
		t.Fatalf("GET before shutdown: %v", err)
	}
	_, _ = io.Copy(io.Discard, resp.Body)
	_ = resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("status = %d, want 200", resp.StatusCode)
	}

	cancel()
	select {
	case err := <-errCh:
		if err != nil {
			t.Fatalf("Serve returned error: %v", err)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("Serve did not return within 5s after cancel")
	}

	if _, err := client.Get("http://" + addr + "/api/v1/ping"); err == nil {
		t.Fatal("GET after shutdown succeeded, want connection failure")
	}

	out := buf.String()
	for _, msg := range []string{"server started", "server stopped"} {
		if !bytes.Contains([]byte(out), []byte(`"msg":"`+msg+`"`)) {
			t.Errorf("log missing %q line: %s", msg, out)
		}
	}
}

// TestServeFinishesInFlightRequest checks graceful shutdown: a request that is
// still running when ctx is cancelled gets its 200 response, and Serve returns
// nil only after that request has finished.
func TestServeFinishesInFlightRequest(t *testing.T) {
	entered := make(chan struct{})
	release := make(chan struct{})
	router := NewRouter()
	router.Handle(http.MethodGet, "/api/v1/slow", http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		close(entered)
		<-release
		_, _ = io.WriteString(w, "done")
	}))

	logger := slog.New(slog.NewJSONHandler(io.Discard, nil))
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("listen: %v", err)
	}
	addr := ln.Addr().String()
	srv := NewHTTPServer(addr, NewHandler(router, logger))

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	serveErr := make(chan error, 1)
	go func() {
		serveErr <- Serve(ctx, srv, ln, logger)
	}()

	type result struct {
		code int
		body string
		err  error
	}
	resCh := make(chan result, 1)
	go func() {
		client := &http.Client{Timeout: 5 * time.Second}
		resp, err := client.Get("http://" + addr + "/api/v1/slow")
		if err != nil {
			resCh <- result{err: err}
			return
		}
		defer resp.Body.Close()
		body, _ := io.ReadAll(resp.Body)
		resCh <- result{code: resp.StatusCode, body: string(body)}
	}()

	select {
	case <-entered:
	case <-time.After(5 * time.Second):
		t.Fatal("handler was not reached within 5s")
	}

	cancel()
	select {
	case err := <-serveErr:
		t.Fatalf("Serve returned while a request was still running: %v", err)
	case <-time.After(200 * time.Millisecond):
	}

	close(release)
	res := <-resCh
	if res.err != nil {
		t.Fatalf("in-flight request failed after cancel: %v", res.err)
	}
	if res.code != http.StatusOK || res.body != "done" {
		t.Fatalf("in-flight response = %d %q, want 200 \"done\"", res.code, res.body)
	}

	select {
	case err := <-serveErr:
		if err != nil {
			t.Fatalf("Serve returned error: %v", err)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("Serve did not return within 5s after the request finished")
	}
}

// TestServeForceClosesAfterTimeout checks that a request which never finishes
// does not hold Serve forever: after shutdownTimeout the connection is closed,
// the client sees an error, and Serve returns nil. The handler stays blocked
// until the test ends, so Shutdown can only fail on the timeout, not by chance.
func TestServeForceClosesAfterTimeout(t *testing.T) {
	prev := shutdownTimeout
	shutdownTimeout = 50 * time.Millisecond
	t.Cleanup(func() { shutdownTimeout = prev })

	entered := make(chan struct{})
	release := make(chan struct{})
	router := NewRouter()
	router.Handle(http.MethodGet, "/api/v1/stuck", http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		close(entered)
		<-release
	}))

	logger := slog.New(slog.NewJSONHandler(io.Discard, nil))
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("listen: %v", err)
	}
	addr := ln.Addr().String()
	srv := NewHTTPServer(addr, NewHandler(router, logger))

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	serveErr := make(chan error, 1)
	go func() {
		serveErr <- Serve(ctx, srv, ln, logger)
	}()

	clientErr := make(chan error, 1)
	go func() {
		client := &http.Client{Timeout: 5 * time.Second}
		resp, err := client.Get("http://" + addr + "/api/v1/stuck")
		if err == nil {
			_ = resp.Body.Close()
		}
		clientErr <- err
	}()

	select {
	case <-entered:
	case <-time.After(5 * time.Second):
		close(release)
		t.Fatal("handler was not reached within 5s")
	}

	cancel()
	select {
	case err := <-serveErr:
		if err != nil {
			t.Errorf("Serve returned error: %v", err)
		}
	case <-time.After(5 * time.Second):
		close(release)
		t.Fatal("Serve did not force-close within 5s")
	}

	if err := <-clientErr; err == nil {
		t.Error("stuck request succeeded after force close, want connection error")
	}
	close(release)
}

// panicMedia is a MediaController whose Send always panics. The panic text
// must reach neither the response body nor the client.
type panicMedia struct{}

const panicDetail = `C:\secret path boom`

func (panicMedia) Send(context.Context, control.MediaAction) error {
	panic(panicDetail)
}

// TestPanicInOneHandlerDoesNotStopServer covers FR-6.5. A panic in one route
// answers 500 internal with a safe body and no panic text, stack, or token.
// The next request to another route still gets 200.
func TestPanicInOneHandlerDoesNotStopServer(t *testing.T) {
	var logs syncBuffer
	logger := slog.New(slog.NewJSONHandler(&logs, nil))
	h := NewAPIHandler(logger, staticToken(testTokenA), StatusDeps{}, WithMedia(panicMedia{}))
	srv := httptest.NewServer(h)
	defer srv.Close()

	get := func(method, path string) (int, string) {
		t.Helper()
		req, err := http.NewRequest(method, srv.URL+path, nil)
		if err != nil {
			t.Fatalf("new request: %v", err)
		}
		req.Header.Set("Authorization", bearer(testTokenA))
		resp, err := srv.Client().Do(req)
		if err != nil {
			t.Fatalf("%s %s: %v", method, path, err)
		}
		defer resp.Body.Close()
		body, err := io.ReadAll(resp.Body)
		if err != nil {
			t.Fatalf("read body: %v", err)
		}
		return resp.StatusCode, string(body)
	}

	code, body := get(http.MethodPost, APIPrefix+"/media/next")
	if code != http.StatusInternalServerError {
		t.Fatalf("panicking route status = %d, want 500", code)
	}
	want := `{"error":{"code":"internal","message":"internal error"}}`
	if body != want {
		t.Errorf("panic body = %q, want %q", body, want)
	}
	for _, leak := range []string{panicDetail, "boom", "goroutine", "panic", testTokenA, "Bearer"} {
		if strings.Contains(body, leak) {
			t.Errorf("panic body leaks %q: %q", leak, body)
		}
	}

	code, _ = get(http.MethodGet, APIPrefix+"/status")
	if code != http.StatusOK {
		t.Fatalf("status after panic = %d, want 200", code)
	}
}

// lanRequest is a request from a LAN address, so NetworkFilter lets it through
// and the test reaches the rate limit and auth.
func lanRequest(method, path, authHeader string) *http.Request {
	req := httptest.NewRequest(method, path, nil)
	req.RemoteAddr = "192.168.1.10:5000"
	if authHeader != "" {
		req.Header.Set("Authorization", authHeader)
	}
	return req
}

// TestRateLimitBeforeAuth checks that the limit runs before the token check: with
// burst 2 and no token, the first two requests get 401 and the third gets 429
// with Retry-After. Unknown routes are limited too.
func TestRateLimitBeforeAuth(t *testing.T) {
	h := NewAPIHandler(slog.New(slog.NewJSONHandler(io.Discard, nil)), staticToken(testTokenA), StatusDeps{}, WithRateLimit(1, 2))

	statuses := make([]int, 0, 3)
	var last *httptest.ResponseRecorder
	for _, path := range []string{APIPrefix + "/status", APIPrefix + "/nope", APIPrefix + "/status"} {
		rec := httptest.NewRecorder()
		h.ServeHTTP(rec, lanRequest(http.MethodGet, path, ""))
		statuses = append(statuses, rec.Code)
		last = rec
	}
	want := []int{http.StatusUnauthorized, http.StatusUnauthorized, http.StatusTooManyRequests}
	for i := range want {
		if statuses[i] != want[i] {
			t.Fatalf("statuses = %v, want %v", statuses, want)
		}
	}
	if last.Header().Get("Retry-After") == "" {
		t.Fatal("429 has no Retry-After header")
	}
	if !strings.Contains(last.Body.String(), `"rate_limited"`) {
		t.Fatalf("429 body = %q, want rate_limited code", last.Body.String())
	}
}

// TestNoRateLimitWithoutOption checks that a handler built without WithRateLimit
// never answers 429.
func TestNoRateLimitWithoutOption(t *testing.T) {
	h := NewAPIHandler(slog.New(slog.NewJSONHandler(io.Discard, nil)), staticToken(testTokenA), StatusDeps{})
	for i := 0; i < 100; i++ {
		rec := httptest.NewRecorder()
		h.ServeHTTP(rec, lanRequest(http.MethodGet, APIPrefix+"/status", bearer(testTokenA)))
		if rec.Code == http.StatusTooManyRequests {
			t.Fatalf("request %d got 429 without WithRateLimit", i+1)
		}
	}
}
