package server

import (
	"bytes"
	"encoding/json"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"reflect"
	"strings"
	"testing"
)

// newTestLogger returns a JSON logger that writes into buf.
func newTestLogger(buf *bytes.Buffer) *slog.Logger {
	return slog.New(slog.NewJSONHandler(buf, nil))
}

// logLines decodes every JSON line in buf.
func logLines(t *testing.T, buf *bytes.Buffer) []map[string]any {
	t.Helper()
	var out []map[string]any
	for _, line := range strings.Split(strings.TrimSpace(buf.String()), "\n") {
		if line == "" {
			continue
		}
		var m map[string]any
		if err := json.Unmarshal([]byte(line), &m); err != nil {
			t.Fatalf("log line is not JSON: %v: %q", err, line)
		}
		out = append(out, m)
	}
	return out
}

// requestLines returns only the access log lines (msg "request").
func requestLines(t *testing.T, buf *bytes.Buffer) []map[string]any {
	t.Helper()
	var out []map[string]any
	for _, m := range logLines(t, buf) {
		if m["msg"] == "request" {
			out = append(out, m)
		}
	}
	return out
}

func TestRecoverPanicReturnsInternalEnvelope(t *testing.T) {
	var buf bytes.Buffer
	h := Chain(http.HandlerFunc(func(http.ResponseWriter, *http.Request) {
		panic("secret boom")
	}), Recover(newTestLogger(&buf)))

	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/api/v1/x", nil))

	if rec.Code != http.StatusInternalServerError {
		t.Fatalf("status = %d, want 500", rec.Code)
	}
	body := rec.Body.String()
	if !strings.Contains(body, `"code":"internal"`) {
		t.Errorf("body %q lacks code internal", body)
	}
	if strings.Contains(body, "secret boom") {
		t.Errorf("response leaks panic text: %q", body)
	}
	if !strings.Contains(buf.String(), `"msg":"panic"`) {
		t.Errorf("log lacks panic line: %q", buf.String())
	}
}

func TestRecoverRepanicsErrAbortHandler(t *testing.T) {
	var buf bytes.Buffer
	h := Recover(newTestLogger(&buf))(http.HandlerFunc(func(http.ResponseWriter, *http.Request) {
		panic(http.ErrAbortHandler)
	}))

	defer func() {
		if v := recover(); v != http.ErrAbortHandler {
			t.Fatalf("recovered %v, want http.ErrAbortHandler", v)
		}
	}()
	h.ServeHTTP(httptest.NewRecorder(), httptest.NewRequest(http.MethodGet, "/", nil))
	t.Fatal("ServeHTTP did not re-panic")
}

func TestLoggingSuccessLine(t *testing.T) {
	var buf bytes.Buffer
	h := Chain(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusCreated)
	}), Logging(newTestLogger(&buf)))

	req := httptest.NewRequest(http.MethodPost, "/api/v1/status", nil)
	req.RemoteAddr = "192.168.1.20:51234"
	h.ServeHTTP(httptest.NewRecorder(), req)

	lines := requestLines(t, &buf)
	if len(lines) != 1 {
		t.Fatalf("got %d request lines, want 1: %q", len(lines), buf.String())
	}
	m := lines[0]
	checks := map[string]any{
		"ip":     "192.168.1.20",
		"method": "POST",
		"path":   "/api/v1/status",
		"status": float64(http.StatusCreated),
	}
	for k, want := range checks {
		if !reflect.DeepEqual(m[k], want) {
			t.Errorf("%s = %v, want %v", k, m[k], want)
		}
	}
	if _, ok := m["durationMs"]; !ok {
		t.Errorf("durationMs missing: %v", m)
	}
	if _, ok := m["errorCode"]; ok {
		t.Errorf("errorCode present on success: %v", m)
	}
}

func TestLoggingImplicitStatusIs200(t *testing.T) {
	var buf bytes.Buffer
	h := Chain(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte("ok"))
	}), Logging(newTestLogger(&buf)))

	h.ServeHTTP(httptest.NewRecorder(), httptest.NewRequest(http.MethodGet, "/", nil))

	lines := requestLines(t, &buf)
	if len(lines) != 1 || lines[0]["status"] != float64(http.StatusOK) {
		t.Fatalf("want one request line with status 200, got %q", buf.String())
	}
}

func TestLoggingErrorCodeFromWriteError(t *testing.T) {
	var buf bytes.Buffer
	h := Chain(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		WriteError(w, http.StatusUnauthorized, CodeInvalidToken, "invalid token")
	}), Logging(newTestLogger(&buf)))

	h.ServeHTTP(httptest.NewRecorder(), httptest.NewRequest(http.MethodGet, "/api/v1/status", nil))

	out := buf.String()
	if !strings.Contains(out, `"errorCode":"invalid_token"`) {
		t.Errorf("log lacks errorCode invalid_token: %q", out)
	}
	if !strings.Contains(out, `"status":401`) {
		t.Errorf("log lacks status 401: %q", out)
	}
}

func TestBR11_LoggingNeverRecordsSecrets(t *testing.T) {
	var buf bytes.Buffer
	h := Chain(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		WriteError(w, http.StatusUnauthorized, CodeInvalidToken, "invalid token")
	}), Logging(newTestLogger(&buf)))

	req := httptest.NewRequest(http.MethodGet, "/api/v1/status?token=abc123secret", nil)
	req.Header.Set("Authorization", "Bearer abc123secret")
	h.ServeHTTP(httptest.NewRecorder(), req)

	out := buf.String()
	for _, forbidden := range []string{"abc123secret", "Authorization", "?"} {
		if strings.Contains(out, forbidden) {
			t.Errorf("log contains %q: %q", forbidden, out)
		}
	}
	lines := requestLines(t, &buf)
	if len(lines) != 1 || lines[0]["path"] != "/api/v1/status" {
		t.Errorf("path field must be path only: %q", out)
	}
}

func TestChainAndLoggingPanicRecordsRequest500(t *testing.T) {
	var buf bytes.Buffer
	l := newTestLogger(&buf)
	h := Chain(http.HandlerFunc(func(http.ResponseWriter, *http.Request) {
		panic("boom")
	}), Recover(l), Logging(l))

	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/api/v1/x", nil))

	if rec.Code != http.StatusInternalServerError {
		t.Fatalf("status = %d, want 500", rec.Code)
	}
	lines := requestLines(t, &buf)
	if len(lines) != 1 {
		t.Fatalf("got %d request lines, want 1: %q", len(lines), buf.String())
	}
	if lines[0]["status"] != float64(http.StatusInternalServerError) {
		t.Errorf("status = %v, want 500", lines[0]["status"])
	}
	if lines[0]["errorCode"] != CodeInternal {
		t.Errorf("errorCode = %v, want %s", lines[0]["errorCode"], CodeInternal)
	}
}

func TestChainOrderOutermostFirst(t *testing.T) {
	var order []string
	mk := func(name string) Middleware {
		return func(next http.Handler) http.Handler {
			return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				order = append(order, name+"-in")
				next.ServeHTTP(w, r)
				order = append(order, name+"-out")
			})
		}
	}
	h := Chain(http.HandlerFunc(func(http.ResponseWriter, *http.Request) {
		order = append(order, "handler")
	}), mk("a"), mk("b"), mk("c"))

	h.ServeHTTP(httptest.NewRecorder(), httptest.NewRequest(http.MethodGet, "/", nil))

	want := []string{"a-in", "b-in", "c-in", "handler", "c-out", "b-out", "a-out"}
	if !reflect.DeepEqual(order, want) {
		t.Errorf("order = %v, want %v", order, want)
	}
}
