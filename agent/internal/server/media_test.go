package server

import (
	"bytes"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"remotto/agent/internal/control"
	"remotto/agent/internal/oscontrol/fake"
)

// mediaRoutes lists the three media endpoints with the action each one sends.
var mediaRoutes = []struct {
	path   string
	action control.MediaAction
}{
	{APIPrefix + "/media/play-pause", control.MediaPlayPause},
	{APIPrefix + "/media/next", control.MediaNext},
	{APIPrefix + "/media/prev", control.MediaPrev},
}

// newMediaTestHandler wires NewAPIHandler with a static token and the fake
// media controller. Logs go to buf.
func newMediaTestHandler(buf *bytes.Buffer, m control.MediaController) http.Handler {
	opts := []APIOption{}
	if m != nil {
		opts = append(opts, WithMedia(m))
	}
	return NewAPIHandler(newTestLogger(buf), staticToken(testTokenA), StatusDeps{}, opts...)
}

// mediaRequest sends method and path from addr with an optional Authorization
// header and body.
func mediaRequest(h http.Handler, method, path, addr, authHeader, body string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(method, path, strings.NewReader(body))
	req.RemoteAddr = addr
	if body != "" {
		req.Header.Set("Content-Type", "application/json")
	}
	if authHeader != "" {
		req.Header.Set("Authorization", authHeader)
	}
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	return rec
}

func TestMediaRoutesSendActionWithValidToken(t *testing.T) {
	for _, rt := range mediaRoutes {
		t.Run(string(rt.action), func(t *testing.T) {
			m := &fake.Media{}
			h := newMediaTestHandler(&bytes.Buffer{}, m)

			rec := mediaRequest(h, http.MethodPost, rt.path, lanAddr, bearer(testTokenA), "")
			if rec.Code != http.StatusOK {
				t.Fatalf("status = %d, want 200 (body %q)", rec.Code, rec.Body.String())
			}
			if got, want := rec.Body.String(), `{"data":{"action":"`+string(rt.action)+`"}}`; got != want {
				t.Errorf("body = %q, want %q", got, want)
			}
			if ct := rec.Header().Get("Content-Type"); ct != "application/json; charset=utf-8" {
				t.Errorf("Content-Type = %q", ct)
			}
			if calls := m.Calls(); len(calls) != 1 || calls[0] != rt.action {
				t.Errorf("calls = %v, want [%s]", calls, rt.action)
			}
		})
	}
}

func TestMediaRequiresToken(t *testing.T) {
	// BR-1: a missing or wrong token is refused before the OS is touched.
	tests := []struct {
		name       string
		authHeader string
	}{
		{"no token", ""},
		{"wrong token", bearer(testTokenB)},
	}
	for _, rt := range mediaRoutes {
		for _, tt := range tests {
			t.Run(string(rt.action)+" "+tt.name, func(t *testing.T) {
				m := &fake.Media{}
				h := newMediaTestHandler(&bytes.Buffer{}, m)

				rec := mediaRequest(h, http.MethodPost, rt.path, lanAddr, tt.authHeader, "")
				if rec.Code != http.StatusUnauthorized {
					t.Fatalf("status = %d, want 401", rec.Code)
				}
				if !strings.Contains(rec.Body.String(), `"code":"`+CodeInvalidToken+`"`) {
					t.Errorf("body %q lacks invalid_token", rec.Body.String())
				}
				if calls := m.Calls(); len(calls) != 0 {
					t.Errorf("calls = %v, want none", calls)
				}
			})
		}
	}
}

func TestMediaForbiddenFromPublicAddress(t *testing.T) {
	for _, rt := range mediaRoutes {
		t.Run(string(rt.action), func(t *testing.T) {
			m := &fake.Media{}
			h := newMediaTestHandler(&bytes.Buffer{}, m)

			rec := mediaRequest(h, http.MethodPost, rt.path, "8.8.8.8:4444", bearer(testTokenA), "")
			if rec.Code != http.StatusForbidden {
				t.Fatalf("status = %d, want 403", rec.Code)
			}
			if !strings.Contains(rec.Body.String(), `"code":"`+CodeForbiddenNetwork+`"`) {
				t.Errorf("body %q lacks forbidden_network", rec.Body.String())
			}
			if calls := m.Calls(); len(calls) != 0 {
				t.Errorf("calls = %v, want none", calls)
			}
		})
	}
}

func TestMediaRejectsGetWithAllowPost(t *testing.T) {
	for _, rt := range mediaRoutes {
		t.Run(string(rt.action), func(t *testing.T) {
			m := &fake.Media{}
			h := newMediaTestHandler(&bytes.Buffer{}, m)

			rec := mediaRequest(h, http.MethodGet, rt.path, lanAddr, bearer(testTokenA), "")
			if rec.Code != http.StatusMethodNotAllowed {
				t.Fatalf("status = %d, want 405", rec.Code)
			}
			if allow := rec.Header().Get("Allow"); allow != "POST" {
				t.Errorf("Allow = %q, want POST", allow)
			}
			if calls := m.Calls(); len(calls) != 0 {
				t.Errorf("calls = %v, want none", calls)
			}
		})
	}
}

func TestBR11_MediaFailureLogsCauseWithoutToken(t *testing.T) {
	// The OS detail reaches the log only. The response carries the safe
	// message and neither the detail nor the token.
	var logs bytes.Buffer
	m := &fake.Media{}
	m.SetErr(errors.New("secret detail"))
	h := newMediaTestHandler(&logs, m)

	rec := mediaRequest(h, http.MethodPost, APIPrefix+"/media/play-pause", lanAddr, bearer(testTokenA), "")
	if rec.Code != http.StatusInternalServerError {
		t.Fatalf("status = %d, want 500", rec.Code)
	}
	if !strings.Contains(rec.Body.String(), `"code":"`+CodeMediaFailed+`"`) {
		t.Errorf("body %q lacks media_failed", rec.Body.String())
	}
	if strings.Contains(rec.Body.String(), "secret detail") {
		t.Errorf("response leaks OS detail: %q", rec.Body.String())
	}
	if !strings.Contains(logs.String(), "secret detail") {
		t.Errorf("log lacks OS cause: %q", logs.String())
	}
	assertNoSecrets(t, "response body", rec.Body.String())
	assertNoSecrets(t, "log", logs.String())

	lines := requestLines(t, &logs)
	if len(lines) != 1 {
		t.Fatalf("request lines = %d, want 1", len(lines))
	}
	if lines[0]["errorCode"] != CodeMediaFailed {
		t.Errorf("errorCode = %v, want %s", lines[0]["errorCode"], CodeMediaFailed)
	}
}

func TestMediaUnsupportedMapsToMediaFailed(t *testing.T) {
	m := &fake.Media{}
	m.SetErr(control.ErrUnsupported)
	h := newMediaTestHandler(&bytes.Buffer{}, m)

	rec := mediaRequest(h, http.MethodPost, APIPrefix+"/media/next", lanAddr, bearer(testTokenA), "")
	if rec.Code != http.StatusInternalServerError {
		t.Fatalf("status = %d, want 500", rec.Code)
	}
	if !strings.Contains(rec.Body.String(), `"code":"`+CodeMediaFailed+`"`) {
		t.Errorf("body %q lacks media_failed", rec.Body.String())
	}
}

func TestMediaWithoutControllerFailsClosed(t *testing.T) {
	for _, rt := range mediaRoutes {
		t.Run(string(rt.action), func(t *testing.T) {
			h := newMediaTestHandler(&bytes.Buffer{}, nil)

			rec := mediaRequest(h, http.MethodPost, rt.path, lanAddr, bearer(testTokenA), "")
			if rec.Code != http.StatusInternalServerError {
				t.Fatalf("status = %d, want 500", rec.Code)
			}
			if !strings.Contains(rec.Body.String(), `"code":"`+CodeMediaFailed+`"`) {
				t.Errorf("body %q lacks media_failed", rec.Body.String())
			}
		})
	}
}

func TestMediaIgnoresRequestBody(t *testing.T) {
	m := &fake.Media{}
	h := newMediaTestHandler(&bytes.Buffer{}, m)

	rec := mediaRequest(h, http.MethodPost, APIPrefix+"/media/play-pause", lanAddr, bearer(testTokenA), `{"x":1}`)
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200 (body %q)", rec.Code, rec.Body.String())
	}
	if calls := m.Calls(); len(calls) != 1 {
		t.Errorf("calls = %v, want 1", calls)
	}
}

func TestMediaRepeatedPostsAreNotDeduplicated(t *testing.T) {
	m := &fake.Media{}
	h := newMediaTestHandler(&bytes.Buffer{}, m)

	for i := range 2 {
		rec := mediaRequest(h, http.MethodPost, APIPrefix+"/media/play-pause", lanAddr, bearer(testTokenA), "")
		if rec.Code != http.StatusOK {
			t.Fatalf("post %d: status = %d, want 200", i, rec.Code)
		}
	}
	if calls := m.Calls(); len(calls) != 2 {
		t.Errorf("calls = %d, want 2", len(calls))
	}
}

func TestMediaHandlerIsFast(t *testing.T) {
	m := &fake.Media{}
	h := newMediaTestHandler(&bytes.Buffer{}, m)

	start := time.Now()
	rec := mediaRequest(h, http.MethodPost, APIPrefix+"/media/prev", lanAddr, bearer(testTokenA), "")
	if elapsed := time.Since(start); elapsed > 100*time.Millisecond {
		t.Errorf("handler took %v, want < 100ms", elapsed)
	}
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", rec.Code)
	}
}
