package server

import (
	"bytes"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"remotto/agent/internal/config"
)

const (
	testTokenA = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
	testTokenB = "fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210"
)

// apiRoutes lists every endpoint from docs/api-spec.md, section "Ringkasan endpoint".
var apiRoutes = []struct {
	method string
	path   string
}{
	{http.MethodGet, "/api/v1/status"},
	{http.MethodPost, "/api/v1/media/play-pause"},
	{http.MethodPost, "/api/v1/media/next"},
	{http.MethodPost, "/api/v1/media/prev"},
	{http.MethodGet, "/api/v1/volume"},
	{http.MethodPut, "/api/v1/volume"},
	{http.MethodPost, "/api/v1/volume/up"},
	{http.MethodPost, "/api/v1/volume/down"},
	{http.MethodPost, "/api/v1/volume/mute"},
	{http.MethodPost, "/api/v1/power/sleep"},
	{http.MethodPost, "/api/v1/power/restart"},
	{http.MethodPost, "/api/v1/power/shutdown"},
	{http.MethodPost, "/api/v1/power/cancel"},
}

// staticToken is a TokenSource with a fixed value.
type staticToken string

func (s staticToken) Token() string { return string(s) }

// newAuthTestHandler puts Auth in front of a router that serves every API
// route with 200, the same way NewHandler will place it.
func newAuthTestHandler(src TokenSource) http.Handler {
	router := NewRouter()
	ok := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		WriteData(w, http.StatusOK, map[string]string{"ok": "yes"})
	})
	for _, rt := range apiRoutes {
		router.Handle(rt.method, rt.path, ok)
	}
	return Chain(router, Auth(src))
}

func bearer(token string) string {
	return "Bearer " + token
}

func doRequest(h http.Handler, method, path, authHeader string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(method, path, nil)
	if authHeader != "" {
		req.Header.Set("Authorization", authHeader)
	}
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	return rec
}

// writeTestConfig saves a valid config.json with token at path.
func writeTestConfig(t *testing.T, path, token string) {
	t.Helper()
	cfg := config.Default("host", time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC))
	cfg.Token = token
	cfg.TokenCreatedAt = "2026-01-01T00:00:00Z"
	if err := config.Save(path, cfg); err != nil {
		t.Fatalf("save config: %v", err)
	}
}

// bumpModTime moves path's modification time forward so a rewrite is always
// seen as a change, even on a coarse filesystem clock.
func bumpModTime(t *testing.T, path string, delta time.Duration) {
	t.Helper()
	fi, err := os.Stat(path)
	if err != nil {
		t.Fatalf("stat: %v", err)
	}
	later := fi.ModTime().Add(delta)
	if err := os.Chtimes(path, later, later); err != nil {
		t.Fatalf("chtimes: %v", err)
	}
}

func TestAuthRejectsBadAuthorizationHeaders(t *testing.T) {
	// BR-2: only "Bearer <exact token>" passes. Scheme is case-insensitive.
	tests := []struct {
		name   string
		header string
		want   int
	}{
		{"no header", "", http.StatusUnauthorized},
		{"bearer only", "Bearer", http.StatusUnauthorized},
		{"bearer with empty token", "Bearer ", http.StatusUnauthorized},
		{"token too short", bearer(testTokenA[:63]), http.StatusUnauthorized},
		{"token too long", bearer(testTokenA + "0"), http.StatusUnauthorized},
		{"uppercase token", bearer(strings.ToUpper(testTokenA)), http.StatusUnauthorized},
		{"wrong token", bearer(testTokenB), http.StatusUnauthorized},
		{"wrong scheme", "Token " + testTokenA, http.StatusUnauthorized},
		{"raw token without scheme", testTokenA, http.StatusUnauthorized},
		{"extra leading space", "Bearer  " + testTokenA, http.StatusUnauthorized},
		{"correct token", bearer(testTokenA), http.StatusOK},
		{"lowercase scheme", "bearer " + testTokenA, http.StatusOK},
		{"uppercase scheme", "BEARER " + testTokenA, http.StatusOK},
	}
	h := newAuthTestHandler(staticToken(testTokenA))
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			rec := doRequest(h, http.MethodGet, "/api/v1/status", tt.header)
			if rec.Code != tt.want {
				t.Fatalf("status = %d, want %d", rec.Code, tt.want)
			}
			if tt.want == http.StatusUnauthorized {
				want := `{"error":{"code":"invalid_token","message":"invalid token"}}`
				if got := rec.Body.String(); got != want {
					t.Errorf("body = %s, want %s", got, want)
				}
			}
		})
	}
}

func TestBR1AllAPIRoutesRequireToken(t *testing.T) {
	// BR-1: every endpoint in api-spec, including ones not built yet, refuses
	// requests without a valid token.
	h := newAuthTestHandler(staticToken(testTokenA))
	for _, rt := range apiRoutes {
		t.Run(rt.method+" "+rt.path, func(t *testing.T) {
			noToken := doRequest(h, rt.method, rt.path, "")
			if noToken.Code != http.StatusUnauthorized {
				t.Errorf("without token: status = %d, want 401", noToken.Code)
			}
			wrong := doRequest(h, rt.method, rt.path, bearer(testTokenB))
			if wrong.Code != http.StatusUnauthorized {
				t.Errorf("wrong token: status = %d, want 401", wrong.Code)
			}
			withToken := doRequest(h, rt.method, rt.path, bearer(testTokenA))
			if withToken.Code != http.StatusOK {
				t.Errorf("valid token: status = %d, want 200", withToken.Code)
			}
		})
	}
}

func TestAuthUnknownRouteAndMethodAreProtected(t *testing.T) {
	// Auth sits outside the router, so unknown routes need a token before they
	// reveal 404 or 405.
	h := newAuthTestHandler(staticToken(testTokenA))
	tests := []struct {
		name   string
		method string
		path   string
		auth   string
		want   int
	}{
		{"unknown route no token", http.MethodGet, "/api/v1/nope", "", http.StatusUnauthorized},
		{"unknown route with token", http.MethodGet, "/api/v1/nope", bearer(testTokenA), http.StatusNotFound},
		{"wrong method no token", http.MethodPost, "/api/v1/status", "", http.StatusUnauthorized},
		{"wrong method with token", http.MethodPost, "/api/v1/status", bearer(testTokenA), http.StatusMethodNotAllowed},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			rec := doRequest(h, tt.method, tt.path, tt.auth)
			if rec.Code != tt.want {
				t.Fatalf("status = %d, want %d", rec.Code, tt.want)
			}
		})
	}
}

func TestAuthEmptyTokenRejectsEverything(t *testing.T) {
	// Fail closed: an empty source token rejects every request, even an empty
	// Bearer value.
	h := newAuthTestHandler(staticToken(""))
	for _, header := range []string{"", "Bearer ", bearer(testTokenA)} {
		rec := doRequest(h, http.MethodGet, "/api/v1/status", header)
		if rec.Code != http.StatusUnauthorized {
			t.Errorf("header %q: status = %d, want 401", header, rec.Code)
		}
	}
}

func TestNewConfigTokenSourceRejectsInvalidInitial(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.json")
	logger := slog.New(slog.NewJSONHandler(&bytes.Buffer{}, nil))
	for _, initial := range []string{"", "short", strings.ToUpper(testTokenA)} {
		src := NewConfigTokenSource(path, initial, logger)
		if got := src.Token(); got != "" {
			t.Errorf("initial %q: Token() = %q, want empty", initial, got)
		}
	}
}

func TestBR10TokenResetTakesEffectWithoutRestart(t *testing.T) {
	// BR-10: rewriting config.json changes the accepted token at once. The old
	// token gets 401 and the new one gets 200, with no restart.
	path := filepath.Join(t.TempDir(), "config.json")
	writeTestConfig(t, path, testTokenA)

	logger := slog.New(slog.NewJSONHandler(&bytes.Buffer{}, nil))
	src := NewConfigTokenSource(path, testTokenA, logger)
	h := newAuthTestHandler(src)

	if rec := doRequest(h, http.MethodGet, "/api/v1/status", bearer(testTokenA)); rec.Code != http.StatusOK {
		t.Fatalf("old token before reset: status = %d, want 200", rec.Code)
	}

	writeTestConfig(t, path, testTokenB)
	bumpModTime(t, path, time.Hour)

	if rec := doRequest(h, http.MethodGet, "/api/v1/status", bearer(testTokenA)); rec.Code != http.StatusUnauthorized {
		t.Errorf("old token after reset: status = %d, want 401", rec.Code)
	}
	if rec := doRequest(h, http.MethodGet, "/api/v1/status", bearer(testTokenB)); rec.Code != http.StatusOK {
		t.Errorf("new token after reset: status = %d, want 200", rec.Code)
	}
}

func TestConfigTokenSourceKeepsLastTokenOnReloadFailure(t *testing.T) {
	// A broken config.json keeps the last valid token, and the warning never
	// contains a token value.
	path := filepath.Join(t.TempDir(), "config.json")
	writeTestConfig(t, path, testTokenA)

	var logBuf bytes.Buffer
	logger := slog.New(slog.NewJSONHandler(&logBuf, nil))
	src := NewConfigTokenSource(path, testTokenA, logger)

	if err := os.WriteFile(path, []byte(`{"port":`), 0o600); err != nil {
		t.Fatalf("write broken config: %v", err)
	}
	bumpModTime(t, path, time.Hour)

	if got := src.Token(); got != testTokenA {
		t.Fatalf("Token() after broken file = %q, want last valid token", got)
	}
	if !strings.Contains(logBuf.String(), "keeping last token") {
		t.Errorf("expected reload warning, log = %s", logBuf.String())
	}
	if strings.Contains(logBuf.String(), testTokenA) {
		t.Errorf("log leaks token value: %s", logBuf.String())
	}
}

func TestConfigTokenSourceInvalidTokenInFileFailsClosed(t *testing.T) {
	// A file that parses but holds an invalid token is not kept as "last valid":
	// every request is rejected until the file is fixed.
	path := filepath.Join(t.TempDir(), "config.json")
	writeTestConfig(t, path, testTokenA)

	logger := slog.New(slog.NewJSONHandler(&bytes.Buffer{}, nil))
	src := NewConfigTokenSource(path, testTokenA, logger)
	h := newAuthTestHandler(src)

	// An empty token passes config.Save and config.Load, but must still be rejected.
	writeTestConfig(t, path, "")
	bumpModTime(t, path, time.Hour)

	if rec := doRequest(h, http.MethodGet, "/api/v1/status", bearer(testTokenA)); rec.Code != http.StatusUnauthorized {
		t.Errorf("status = %d, want 401 after token cleared", rec.Code)
	}
}

func TestConfigTokenSourceMissingFileKeepsToken(t *testing.T) {
	// A file that is missing or unreadable keeps the last valid token, so a
	// short gap during an atomic rename does not lock the phone out.
	path := filepath.Join(t.TempDir(), "config.json")
	writeTestConfig(t, path, testTokenA)

	logger := slog.New(slog.NewJSONHandler(&bytes.Buffer{}, nil))
	src := NewConfigTokenSource(path, testTokenA, logger)
	if err := os.Remove(path); err != nil {
		t.Fatalf("remove: %v", err)
	}
	if got := src.Token(); got != testTokenA {
		t.Fatalf("Token() with missing file = %q, want last token", got)
	}
}
