package server

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"remotto/agent/internal/oscontrol/fake"
)

// unlistedRoutes are paths that look like discovery or identity endpoints but
// are not in docs/api-spec.md. They must stay behind the token like every
// other path.
var unlistedRoutes = []string{
	APIPrefix + "/discovery",
	APIPrefix + "/agentId",
	APIPrefix + "/mdns",
	"/_remotto",
	"/",
}

// routeRequest sends a GET from a LAN address, so NetworkFilter lets it
// through and the auth decision is what the test observes.
func routeRequest(h http.Handler, path, authHeader string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(http.MethodGet, path, nil)
	req.RemoteAddr = lanAddr
	if authHeader != "" {
		req.Header.Set("Authorization", authHeader)
	}
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	return rec
}

// newRoutesHandler wires the full handler with a static token, the same way
// status_test does.
func newRoutesHandler(t *testing.T) http.Handler {
	t.Helper()
	clock := &fakeClock{now: time.Date(2026, 1, 1, 10, 0, 0, 0, time.UTC)}
	deps := StatusDeps{
		Name:      "Laptop-Test",
		Version:   "1.0.0",
		StartedAt: clock.Now(),
		Now:       clock.Now,
		Audio:     fake.NewAudio(10, false),
	}
	return NewAPIHandler(newTestLogger(&bytes.Buffer{}), staticToken(testTokenA), deps)
}

// errorCodeOf returns error.code from an error envelope, failing when the body
// is not the envelope.
func errorCodeOf(t *testing.T, body []byte) string {
	t.Helper()
	var env struct {
		Error *struct {
			Code    string `json:"code"`
			Message string `json:"message"`
		} `json:"error"`
	}
	if err := json.Unmarshal(body, &env); err != nil {
		t.Fatalf("body is not JSON: %v: %s", err, body)
	}
	if env.Error == nil || env.Error.Code == "" || env.Error.Message == "" {
		t.Fatalf("body is not an error envelope: %s", body)
	}
	return env.Error.Code
}

// BR-1: no route outside the API is reachable without a valid token. A
// missing or wrong token gets 401 invalid_token, so an unauthenticated caller
// cannot tell an unknown path from a protected one.
func TestBR1_UnlistedRoutesRequireTokenFirst(t *testing.T) {
	h := newRoutesHandler(t)
	headers := map[string]string{
		"no header":    "",
		"wrong token":  bearer("0000000000000000000000000000000000000000000000000000000000000000"),
		"basic scheme": "Basic " + testTokenA,
	}
	for _, path := range unlistedRoutes {
		for name, hdr := range headers {
			t.Run(path+" "+name, func(t *testing.T) {
				rec := routeRequest(h, path, hdr)
				if rec.Code != http.StatusUnauthorized {
					t.Fatalf("status = %d, want 401: %s", rec.Code, rec.Body.String())
				}
				if code := errorCodeOf(t, rec.Body.Bytes()); code != CodeInvalidToken {
					t.Errorf("error code = %q, want %q", code, CodeInvalidToken)
				}
			})
		}
	}
}

// With a valid token, paths outside docs/api-spec.md are still unknown: 404
// with the error envelope, not a page or a new route.
func TestBR1_UnlistedRoutesAreNotFoundWithToken(t *testing.T) {
	h := newRoutesHandler(t)
	for _, path := range unlistedRoutes {
		t.Run(path, func(t *testing.T) {
			rec := routeRequest(h, path, bearer(testTokenA))
			if rec.Code != http.StatusNotFound {
				t.Fatalf("status = %d, want 404: %s", rec.Code, rec.Body.String())
			}
			if code := errorCodeOf(t, rec.Body.Bytes()); code != CodeNotFound {
				t.Errorf("error code = %q, want %q", code, CodeNotFound)
			}
		})
	}
}

// The real status route still answers with the token, so the 401 and 404
// checks above are not passing just because everything fails.
func TestBR1_StatusStillAnswersWithToken(t *testing.T) {
	h := newRoutesHandler(t)
	rec := routeRequest(h, APIPrefix+"/status", bearer(testTokenA))
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200: %s", rec.Code, rec.Body.String())
	}
}
