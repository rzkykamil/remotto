package server

import (
	"bytes"
	"context"
	"io"
	"log/slog"
	"net"
	"net/http"
	"net/http/httptest"
	"sync"
	"testing"
	"time"
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
