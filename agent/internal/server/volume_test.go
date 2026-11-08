package server

import (
	"bytes"
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"remotto/agent/internal/control"
	"remotto/agent/internal/oscontrol/fake"
)

// newVolumeTestHandler wires NewAPIHandler with a static token and the given
// audio controller. Logs go to buf.
func newVolumeTestHandler(buf *bytes.Buffer, a control.AudioController) http.Handler {
	opts := []APIOption{}
	if a != nil {
		opts = append(opts, WithAudio(a))
	}
	return NewAPIHandler(newTestLogger(buf), staticToken(testTokenA), StatusDeps{}, opts...)
}

// volumeRequest sends one request to /volume. contentType is set only when non-empty.
func volumeRequest(h http.Handler, method, addr, authHeader, contentType, body string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(method, APIPrefix+"/volume", strings.NewReader(body))
	req.RemoteAddr = addr
	if contentType != "" {
		req.Header.Set("Content-Type", contentType)
	}
	if authHeader != "" {
		req.Header.Set("Authorization", authHeader)
	}
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	return rec
}

func TestVolumeGetReturnsVolume(t *testing.T) {
	a := fake.NewAudio(35, false)
	h := newVolumeTestHandler(&bytes.Buffer{}, a)

	rec := volumeRequest(h, http.MethodGet, lanAddr, bearer(testTokenA), "", "")
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200 (body %q)", rec.Code, rec.Body.String())
	}
	if got, want := rec.Body.String(), `{"data":{"level":35,"muted":false}}`; got != want {
		t.Errorf("body = %q, want %q", got, want)
	}
	if ct := rec.Header().Get("Content-Type"); ct != "application/json; charset=utf-8" {
		t.Errorf("Content-Type = %q", ct)
	}
}

func TestVolumePutSetsLevel(t *testing.T) {
	a := fake.NewAudio(20, false)
	h := newVolumeTestHandler(&bytes.Buffer{}, a)

	rec := volumeRequest(h, http.MethodPut, lanAddr, bearer(testTokenA), "application/json", `{"level":35}`)
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200 (body %q)", rec.Code, rec.Body.String())
	}
	if got, want := rec.Body.String(), `{"data":{"level":35,"muted":false}}`; got != want {
		t.Errorf("body = %q, want %q", got, want)
	}
	if calls := a.SetLevelCalls(); len(calls) != 1 || calls[0] != 35 {
		t.Errorf("SetLevelCalls() = %v, want [35]", calls)
	}
}

// BR-15: a level change also clears mute, and the response shows it.
func TestBR15_PutUnmutes(t *testing.T) {
	a := fake.NewAudio(20, true)
	h := newVolumeTestHandler(&bytes.Buffer{}, a)

	rec := volumeRequest(h, http.MethodPut, lanAddr, bearer(testTokenA), "application/json", `{"level":35}`)
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200 (body %q)", rec.Code, rec.Body.String())
	}
	if got, want := rec.Body.String(), `{"data":{"level":35,"muted":false}}`; got != want {
		t.Errorf("body = %q, want %q", got, want)
	}
}

// BR-3: levels outside 0-100 and values that are not integers are rejected
// with 400 invalid_level before the OS is touched.
func TestBR3_PutRejectsInvalidLevel(t *testing.T) {
	tests := []struct {
		name string
		body string
	}{
		{"minus one", `{"level":-1}`},
		{"101", `{"level":101}`},
		{"1000", `{"level":1000}`},
		{"huge", `{"level":99999999999999999999999}`},
		{"decimal", `{"level":35.5}`},
		{"exponent", `{"level":1e2}`},
		{"string", `{"level":"35"}`},
		{"null", `{"level":null}`},
		{"true", `{"level":true}`},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			a := fake.NewAudio(35, true)
			h := newVolumeTestHandler(&bytes.Buffer{}, a)

			rec := volumeRequest(h, http.MethodPut, lanAddr, bearer(testTokenA), "application/json", tt.body)
			if rec.Code != http.StatusBadRequest {
				t.Fatalf("status = %d, want 400 (body %q)", rec.Code, rec.Body.String())
			}
			if !strings.Contains(rec.Body.String(), `"code":"`+CodeInvalidLevel+`"`) {
				t.Errorf("body %q lacks invalid_level", rec.Body.String())
			}
			if calls := a.SetLevelCalls(); len(calls) != 0 {
				t.Errorf("SetLevelCalls() = %v, want none", calls)
			}
			v, _ := a.Volume(context.Background())
			if v != (control.Volume{Level: 35, Muted: true}) {
				t.Errorf("state = %+v, want unchanged {35 true}", v)
			}
		})
	}
}

// BR-3: 0 and 100 are valid and are not clamped.
func TestBR3_PutAcceptsBoundaries(t *testing.T) {
	for _, level := range []string{"0", "100"} {
		t.Run(level, func(t *testing.T) {
			a := fake.NewAudio(35, false)
			h := newVolumeTestHandler(&bytes.Buffer{}, a)

			rec := volumeRequest(h, http.MethodPut, lanAddr, bearer(testTokenA), "application/json", `{"level":`+level+`}`)
			if rec.Code != http.StatusOK {
				t.Fatalf("status = %d, want 200 (body %q)", rec.Code, rec.Body.String())
			}
			if got, want := rec.Body.String(), `{"data":{"level":`+level+`,"muted":false}}`; got != want {
				t.Errorf("body = %q, want %q", got, want)
			}
		})
	}
}

func TestVolumePutInvalidRequest(t *testing.T) {
	big := `{"level":35,"pad":"` + strings.Repeat("a", 1100) + `"}`
	tests := []struct {
		name        string
		contentType string
		body        string
	}{
		{"missing level", "application/json", `{}`},
		{"unknown field", "application/json", `{"level":35,"x":1}`},
		{"empty body", "application/json", ``},
		{"broken json", "application/json", `{"level":`},
		{"two values", "application/json", `{"level":35}{"level":36}`},
		{"wrong content type", "text/plain", `{"level":35}`},
		{"no content type", "", `{"level":35}`},
		{"body over 1 KiB", "application/json", big},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			a := fake.NewAudio(35, false)
			h := newVolumeTestHandler(&bytes.Buffer{}, a)

			rec := volumeRequest(h, http.MethodPut, lanAddr, bearer(testTokenA), tt.contentType, tt.body)
			if rec.Code != http.StatusBadRequest {
				t.Fatalf("status = %d, want 400 (body %q)", rec.Code, rec.Body.String())
			}
			if !strings.Contains(rec.Body.String(), `"code":"`+CodeInvalidRequest+`"`) {
				t.Errorf("body %q lacks invalid_request", rec.Body.String())
			}
			if calls := a.SetLevelCalls(); len(calls) != 0 {
				t.Errorf("SetLevelCalls() = %v, want none", calls)
			}
		})
	}
}

func TestVolumeRequiresToken(t *testing.T) {
	// BR-1: a missing or wrong token is refused before the OS is touched.
	tests := []struct {
		name       string
		authHeader string
	}{
		{"no token", ""},
		{"wrong token", bearer(testTokenB)},
	}
	for _, method := range []string{http.MethodGet, http.MethodPut} {
		for _, tt := range tests {
			t.Run(method+" "+tt.name, func(t *testing.T) {
				a := fake.NewAudio(35, false)
				h := newVolumeTestHandler(&bytes.Buffer{}, a)

				rec := volumeRequest(h, method, lanAddr, tt.authHeader, "application/json", `{"level":50}`)
				if rec.Code != http.StatusUnauthorized {
					t.Fatalf("status = %d, want 401", rec.Code)
				}
				if !strings.Contains(rec.Body.String(), `"code":"`+CodeInvalidToken+`"`) {
					t.Errorf("body %q lacks invalid_token", rec.Body.String())
				}
				if calls := a.SetLevelCalls(); len(calls) != 0 {
					t.Errorf("SetLevelCalls() = %v, want none", calls)
				}
			})
		}
	}
}

func TestVolumeForbiddenFromPublicAddress(t *testing.T) {
	for _, method := range []string{http.MethodGet, http.MethodPut} {
		t.Run(method, func(t *testing.T) {
			a := fake.NewAudio(35, false)
			h := newVolumeTestHandler(&bytes.Buffer{}, a)

			rec := volumeRequest(h, method, "8.8.8.8:4444", bearer(testTokenA), "application/json", `{"level":50}`)
			if rec.Code != http.StatusForbidden {
				t.Fatalf("status = %d, want 403", rec.Code)
			}
			if !strings.Contains(rec.Body.String(), `"code":"`+CodeForbiddenNetwork+`"`) {
				t.Errorf("body %q lacks forbidden_network", rec.Body.String())
			}
			if calls := a.SetLevelCalls(); len(calls) != 0 {
				t.Errorf("SetLevelCalls() = %v, want none", calls)
			}
		})
	}
}

func TestVolumeRejectsPostWithAllowGetPut(t *testing.T) {
	a := fake.NewAudio(35, false)
	h := newVolumeTestHandler(&bytes.Buffer{}, a)

	rec := volumeRequest(h, http.MethodPost, lanAddr, bearer(testTokenA), "application/json", `{"level":50}`)
	if rec.Code != http.StatusMethodNotAllowed {
		t.Fatalf("status = %d, want 405", rec.Code)
	}
	if allow := rec.Header().Get("Allow"); allow != "GET, PUT" {
		t.Errorf("Allow = %q, want %q", allow, "GET, PUT")
	}
	if calls := a.SetLevelCalls(); len(calls) != 0 {
		t.Errorf("SetLevelCalls() = %v, want none", calls)
	}
}

func TestVolumeAudioFailureDoesNotLeak(t *testing.T) {
	// The OS detail reaches the log only. The response carries the safe
	// message and neither the detail nor the token.
	for _, method := range []string{http.MethodGet, http.MethodPut} {
		t.Run(method, func(t *testing.T) {
			var logs bytes.Buffer
			a := fake.NewAudio(35, false)
			a.SetErr(errors.New("secret detail"))
			h := newVolumeTestHandler(&logs, a)

			rec := volumeRequest(h, method, lanAddr, bearer(testTokenA), "application/json", `{"level":50}`)
			if rec.Code != http.StatusInternalServerError {
				t.Fatalf("status = %d, want 500", rec.Code)
			}
			if !strings.Contains(rec.Body.String(), `"code":"`+CodeAudioFailed+`"`) {
				t.Errorf("body %q lacks audio_failed", rec.Body.String())
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
			if lines[0]["errorCode"] != CodeAudioFailed {
				t.Errorf("errorCode = %v, want %s", lines[0]["errorCode"], CodeAudioFailed)
			}
		})
	}
}

func TestVolumeWithoutControllerFailsClosed(t *testing.T) {
	for _, method := range []string{http.MethodGet, http.MethodPut} {
		t.Run(method, func(t *testing.T) {
			h := newVolumeTestHandler(&bytes.Buffer{}, nil)

			rec := volumeRequest(h, method, lanAddr, bearer(testTokenA), "application/json", `{"level":50}`)
			if rec.Code != http.StatusInternalServerError {
				t.Fatalf("status = %d, want 500", rec.Code)
			}
			if !strings.Contains(rec.Body.String(), `"code":"`+CodeAudioFailed+`"`) {
				t.Errorf("body %q lacks audio_failed", rec.Body.String())
			}
		})
	}
}

func TestVolumeRepeatedPutBothSucceed(t *testing.T) {
	a := fake.NewAudio(20, false)
	h := newVolumeTestHandler(&bytes.Buffer{}, a)

	for i := 0; i < 2; i++ {
		rec := volumeRequest(h, http.MethodPut, lanAddr, bearer(testTokenA), "application/json", `{"level":35}`)
		if rec.Code != http.StatusOK {
			t.Fatalf("attempt %d: status = %d, want 200 (body %q)", i+1, rec.Code, rec.Body.String())
		}
	}
}

// volumeRequestAt sends one request to path. contentType is set only when non-empty.
func volumeRequestAt(h http.Handler, method, path, addr, authHeader, contentType, body string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(method, path, strings.NewReader(body))
	req.RemoteAddr = addr
	if contentType != "" {
		req.Header.Set("Content-Type", contentType)
	}
	if authHeader != "" {
		req.Header.Set("Authorization", authHeader)
	}
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	return rec
}

// BR-16: up and down move the level by 5 and unmute.
func TestBR16_UpDownStep5(t *testing.T) {
	tests := []struct {
		name  string
		path  string
		start int
		want  string
	}{
		{"up", "/up", 35, `{"data":{"level":40,"muted":false}}`},
		{"down", "/down", 35, `{"data":{"level":30,"muted":false}}`},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			a := fake.NewAudio(tt.start, false)
			h := newVolumeTestHandler(&bytes.Buffer{}, a)

			rec := volumeRequestAt(h, http.MethodPost, APIPrefix+"/volume"+tt.path, lanAddr, bearer(testTokenA), "", "")
			if rec.Code != http.StatusOK {
				t.Fatalf("status = %d, want 200 (body %q)", rec.Code, rec.Body.String())
			}
			if got := rec.Body.String(); got != tt.want {
				t.Errorf("body = %q, want %q", got, tt.want)
			}
		})
	}
}

// BR-16: at the limits the level stops at 0 or 100 and the request still
// succeeds.
func TestBR16_ClampsAtLimits(t *testing.T) {
	tests := []struct {
		name  string
		path  string
		start int
		want  string
	}{
		{"up from 98 stops at 100", "/up", 98, `{"data":{"level":100,"muted":false}}`},
		{"up at 100 stays 100", "/up", 100, `{"data":{"level":100,"muted":false}}`},
		{"down from 2 stops at 0", "/down", 2, `{"data":{"level":0,"muted":false}}`},
		{"down at 0 stays 0", "/down", 0, `{"data":{"level":0,"muted":false}}`},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			a := fake.NewAudio(tt.start, false)
			h := newVolumeTestHandler(&bytes.Buffer{}, a)

			rec := volumeRequestAt(h, http.MethodPost, APIPrefix+"/volume"+tt.path, lanAddr, bearer(testTokenA), "", "")
			if rec.Code != http.StatusOK {
				t.Fatalf("status = %d, want 200 (body %q)", rec.Code, rec.Body.String())
			}
			if got := rec.Body.String(); got != tt.want {
				t.Errorf("body = %q, want %q", got, tt.want)
			}
		})
	}
}

// BR-15: a step also clears mute, and the response shows it.
func TestBR15_StepUnmutes(t *testing.T) {
	for _, path := range []string{"/up", "/down"} {
		t.Run(path, func(t *testing.T) {
			a := fake.NewAudio(35, true)
			h := newVolumeTestHandler(&bytes.Buffer{}, a)

			rec := volumeRequestAt(h, http.MethodPost, APIPrefix+"/volume"+path, lanAddr, bearer(testTokenA), "", "")
			if rec.Code != http.StatusOK {
				t.Fatalf("status = %d, want 200 (body %q)", rec.Code, rec.Body.String())
			}
			if !strings.Contains(rec.Body.String(), `"muted":false`) {
				t.Errorf("body %q does not show muted:false", rec.Body.String())
			}
		})
	}
}

// The step body is ignored, so a body that is not valid for this route still
// succeeds.
func TestVolumeStepIgnoresBody(t *testing.T) {
	for _, body := range []string{`{"x":1}`, ``} {
		t.Run(body, func(t *testing.T) {
			a := fake.NewAudio(35, false)
			h := newVolumeTestHandler(&bytes.Buffer{}, a)

			rec := volumeRequestAt(h, http.MethodPost, APIPrefix+"/volume/up", lanAddr, bearer(testTokenA), "application/json", body)
			if rec.Code != http.StatusOK {
				t.Fatalf("status = %d, want 200 (body %q)", rec.Code, rec.Body.String())
			}
			if got, want := rec.Body.String(), `{"data":{"level":40,"muted":false}}`; got != want {
				t.Errorf("body = %q, want %q", got, want)
			}
		})
	}
}

// Steps are not deduplicated: each POST moves the level again.
func TestVolumeStepNotDeduplicated(t *testing.T) {
	a := fake.NewAudio(35, false)
	h := newVolumeTestHandler(&bytes.Buffer{}, a)

	want := []string{
		`{"data":{"level":40,"muted":false}}`,
		`{"data":{"level":45,"muted":false}}`,
	}
	for i, w := range want {
		rec := volumeRequestAt(h, http.MethodPost, APIPrefix+"/volume/up", lanAddr, bearer(testTokenA), "", "")
		if rec.Code != http.StatusOK {
			t.Fatalf("attempt %d: status = %d, want 200 (body %q)", i+1, rec.Code, rec.Body.String())
		}
		if rec.Body.String() != w {
			t.Errorf("attempt %d: body = %q, want %q", i+1, rec.Body.String(), w)
		}
	}
}

// volumeMutateRoutes lists the POST routes that change the OS state, with a
// body that is valid for each one.
var volumeMutateRoutes = []struct {
	name string
	path string
	body string
}{
	{"up", APIPrefix + "/volume/up", ""},
	{"down", APIPrefix + "/volume/down", ""},
	{"mute", APIPrefix + "/volume/mute", `{"muted":true}`},
}

// BR-1 and BR-12: every POST volume route is refused without a valid token or
// from a public address, and the OS is not touched.
func TestVolumePostRoutesRequireTokenAndLAN(t *testing.T) {
	cases := []struct {
		name       string
		addr       string
		authHeader string
		wantStatus int
		wantCode   string
	}{
		{"no token", lanAddr, "", http.StatusUnauthorized, CodeInvalidToken},
		{"wrong token", lanAddr, bearer(testTokenB), http.StatusUnauthorized, CodeInvalidToken},
		{"public address", "8.8.8.8:4444", bearer(testTokenA), http.StatusForbidden, CodeForbiddenNetwork},
	}
	for _, rt := range volumeMutateRoutes {
		for _, tt := range cases {
			t.Run(rt.name+" "+tt.name, func(t *testing.T) {
				a := fake.NewAudio(35, true)
				h := newVolumeTestHandler(&bytes.Buffer{}, a)

				rec := volumeRequestAt(h, http.MethodPost, rt.path, tt.addr, tt.authHeader, "application/json", rt.body)
				if rec.Code != tt.wantStatus {
					t.Fatalf("status = %d, want %d", rec.Code, tt.wantStatus)
				}
				if !strings.Contains(rec.Body.String(), `"code":"`+tt.wantCode+`"`) {
					t.Errorf("body %q lacks %s", rec.Body.String(), tt.wantCode)
				}
				if v, _ := a.Volume(context.Background()); v != (control.Volume{Level: 35, Muted: true}) {
					t.Errorf("state = %+v, want unchanged {35 true}", v)
				}
			})
		}
	}
}

func TestVolumeStepRejectsGetWithAllowPost(t *testing.T) {
	for _, path := range []string{"/volume/up", "/volume/down", "/volume/mute"} {
		t.Run(path, func(t *testing.T) {
			a := fake.NewAudio(35, false)
			h := newVolumeTestHandler(&bytes.Buffer{}, a)

			rec := volumeRequestAt(h, http.MethodGet, APIPrefix+path, lanAddr, bearer(testTokenA), "", "")
			if rec.Code != http.StatusMethodNotAllowed {
				t.Fatalf("status = %d, want 405", rec.Code)
			}
			if allow := rec.Header().Get("Allow"); allow != "POST" {
				t.Errorf("Allow = %q, want POST", allow)
			}
		})
	}
}

// The OS detail for a step or mute failure reaches the log only. The response
// carries the safe message.
func TestVolumePostAudioFailureDoesNotLeak(t *testing.T) {
	for _, rt := range volumeMutateRoutes {
		t.Run(rt.name, func(t *testing.T) {
			var logs bytes.Buffer
			a := fake.NewAudio(35, false)
			a.SetErr(errors.New("secret detail"))
			h := newVolumeTestHandler(&logs, a)

			rec := volumeRequestAt(h, http.MethodPost, rt.path, lanAddr, bearer(testTokenA), "application/json", rt.body)
			if rec.Code != http.StatusInternalServerError {
				t.Fatalf("status = %d, want 500", rec.Code)
			}
			if !strings.Contains(rec.Body.String(), `"code":"`+CodeAudioFailed+`"`) {
				t.Errorf("body %q lacks audio_failed", rec.Body.String())
			}
			if strings.Contains(rec.Body.String(), "secret detail") {
				t.Errorf("response leaks OS detail: %q", rec.Body.String())
			}
			if !strings.Contains(logs.String(), "secret detail") {
				t.Errorf("log lacks OS cause: %q", logs.String())
			}
			assertNoSecrets(t, "response body", rec.Body.String())
			assertNoSecrets(t, "log", logs.String())
		})
	}
}

// Mute sets the flag and leaves the level alone (BR-15 does not apply here).
func TestVolumeMuteSetsFlagKeepsLevel(t *testing.T) {
	tests := []struct {
		name  string
		start bool
		body  string
		want  string
	}{
		{"mute on", false, `{"muted":true}`, `{"data":{"level":35,"muted":true}}`},
		{"mute off", true, `{"muted":false}`, `{"data":{"level":35,"muted":false}}`},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			a := fake.NewAudio(35, tt.start)
			h := newVolumeTestHandler(&bytes.Buffer{}, a)

			rec := volumeRequestAt(h, http.MethodPost, APIPrefix+"/volume/mute", lanAddr, bearer(testTokenA), "application/json", tt.body)
			if rec.Code != http.StatusOK {
				t.Fatalf("status = %d, want 200 (body %q)", rec.Code, rec.Body.String())
			}
			if got := rec.Body.String(); got != tt.want {
				t.Errorf("body = %q, want %q", got, tt.want)
			}
		})
	}
}

// Mute is set, not toggled: the same request twice gives the same state.
func TestVolumeMuteIsIdempotent(t *testing.T) {
	a := fake.NewAudio(35, false)
	h := newVolumeTestHandler(&bytes.Buffer{}, a)

	for i := 0; i < 2; i++ {
		rec := volumeRequestAt(h, http.MethodPost, APIPrefix+"/volume/mute", lanAddr, bearer(testTokenA), "application/json", `{"muted":true}`)
		if rec.Code != http.StatusOK {
			t.Fatalf("attempt %d: status = %d, want 200 (body %q)", i+1, rec.Code, rec.Body.String())
		}
		if got, want := rec.Body.String(), `{"data":{"level":35,"muted":true}}`; got != want {
			t.Errorf("attempt %d: body = %q, want %q", i+1, got, want)
		}
	}
}

func TestVolumeMuteInvalidRequest(t *testing.T) {
	big := `{"muted":true,"pad":"` + strings.Repeat("a", 1100) + `"}`
	tests := []struct {
		name        string
		contentType string
		body        string
	}{
		{"missing muted", "application/json", `{}`},
		{"muted string", "application/json", `{"muted":"true"}`},
		{"muted number", "application/json", `{"muted":1}`},
		{"muted null", "application/json", `{"muted":null}`},
		{"unknown field", "application/json", `{"muted":true,"x":1}`},
		{"empty body", "application/json", ``},
		{"broken json", "application/json", `{"muted":`},
		{"two values", "application/json", `{"muted":true}{"muted":false}`},
		{"wrong content type", "text/plain", `{"muted":true}`},
		{"body over 1 KiB", "application/json", big},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			a := fake.NewAudio(35, false)
			h := newVolumeTestHandler(&bytes.Buffer{}, a)

			rec := volumeRequestAt(h, http.MethodPost, APIPrefix+"/volume/mute", lanAddr, bearer(testTokenA), tt.contentType, tt.body)
			if rec.Code != http.StatusBadRequest {
				t.Fatalf("status = %d, want 400 (body %q)", rec.Code, rec.Body.String())
			}
			if !strings.Contains(rec.Body.String(), `"code":"`+CodeInvalidRequest+`"`) {
				t.Errorf("body %q lacks invalid_request", rec.Body.String())
			}
			if v, _ := a.Volume(context.Background()); v != (control.Volume{Level: 35, Muted: false}) {
				t.Errorf("state = %+v, want unchanged {35 false}", v)
			}
		})
	}
}

// A broken mute write must not fail a level change on an unmuted device.
func TestVolumePutSucceedsWhenMuteWriteBrokenAndNotMuted(t *testing.T) {
	a := fake.NewAudio(35, false)
	a.SetMuteErr(errors.New("Incorrect function."))
	h := newVolumeTestHandler(&bytes.Buffer{}, a)

	rec := volumeRequest(h, http.MethodPut, lanAddr, bearer(testTokenA), "application/json", `{"level":50}`)
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200 (body %q)", rec.Code, rec.Body.String())
	}
	if got, want := rec.Body.String(), `{"data":{"level":50,"muted":false}}`; got != want {
		t.Errorf("body = %q, want %q", got, want)
	}
}

// Up and down behave the same way on an unmuted device with a broken mute write.
func TestVolumeStepSucceedsWhenMuteWriteBrokenAndNotMuted(t *testing.T) {
	tests := []struct {
		path string
		want string
	}{
		{"/up", `{"data":{"level":40,"muted":false}}`},
		{"/down", `{"data":{"level":30,"muted":false}}`},
	}
	for _, tt := range tests {
		t.Run(tt.path, func(t *testing.T) {
			a := fake.NewAudio(35, false)
			a.SetMuteErr(errors.New("Incorrect function."))
			h := newVolumeTestHandler(&bytes.Buffer{}, a)

			rec := volumeRequestAt(h, http.MethodPost, APIPrefix+"/volume"+tt.path, lanAddr, bearer(testTokenA), "", "")
			if rec.Code != http.StatusOK {
				t.Fatalf("status = %d, want 200 (body %q)", rec.Code, rec.Body.String())
			}
			if got := rec.Body.String(); got != tt.want {
				t.Errorf("body = %q, want %q", got, tt.want)
			}
		})
	}
}

// A muted device whose unmute fails returns 500 audio_failed. The OS cause
// reaches the log only.
func TestVolumePutFailsWhenUnmuteFailsAndMuted(t *testing.T) {
	const cause = "Incorrect function."
	var logs bytes.Buffer
	a := fake.NewAudio(35, true)
	a.SetMuteErr(errors.New(cause))
	h := newVolumeTestHandler(&logs, a)

	rec := volumeRequest(h, http.MethodPut, lanAddr, bearer(testTokenA), "application/json", `{"level":50}`)
	if rec.Code != http.StatusInternalServerError {
		t.Fatalf("status = %d, want 500 (body %q)", rec.Code, rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), `"code":"`+CodeAudioFailed+`"`) {
		t.Errorf("body %q lacks audio_failed", rec.Body.String())
	}
	if strings.Contains(rec.Body.String(), cause) {
		t.Errorf("response leaks OS detail: %q", rec.Body.String())
	}
	if !strings.Contains(logs.String(), cause) {
		t.Errorf("log lacks OS cause: %q", logs.String())
	}
	assertNoSecrets(t, "response body", rec.Body.String())
	assertNoSecrets(t, "log", logs.String())
}
