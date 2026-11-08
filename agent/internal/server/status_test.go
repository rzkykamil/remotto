package server

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	"remotto/agent/internal/control"
	"remotto/agent/internal/oscontrol/fake"
)

// fakeClock is a manually advanced clock for uptime tests.
type fakeClock struct {
	mu  sync.Mutex
	now time.Time
}

func (c *fakeClock) Now() time.Time {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.now
}

func (c *fakeClock) Advance(d time.Duration) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.now = c.now.Add(d)
}

// lanAddr is a private LAN source address, so NetworkFilter lets the request through.
const lanAddr = "192.168.1.20:50000"

// statusRequest sends GET /api/v1/status from addr with the given Authorization header.
func statusRequest(h http.Handler, addr, authHeader string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(http.MethodGet, APIPrefix+"/status", nil)
	req.RemoteAddr = addr
	if authHeader != "" {
		req.Header.Set("Authorization", authHeader)
	}
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	return rec
}

// newStatusTestHandler wires NewAPIHandler with a static token and a fake clock.
func newStatusTestHandler(t *testing.T, clock *fakeClock, audio *fake.Audio, logger *bytes.Buffer) http.Handler {
	t.Helper()
	deps := StatusDeps{
		Name:      "Laptop-Test",
		Version:   "1.0.0",
		StartedAt: clock.Now(),
		Now:       clock.Now,
		Audio:     audio,
	}
	return NewAPIHandler(newTestLogger(logger), staticToken(testTokenA), deps)
}

// decodeStatus returns the data object of a 200 status response.
func decodeStatus(t *testing.T, body []byte) map[string]any {
	t.Helper()
	var env map[string]map[string]any
	if err := json.Unmarshal(body, &env); err != nil {
		t.Fatalf("body is not JSON: %v: %s", err, body)
	}
	data, ok := env["data"]
	if !ok {
		t.Fatalf("body missing data envelope: %s", body)
	}
	return data
}

func TestStatusShapeAndValues(t *testing.T) {
	// BR-6 / api-spec Status: exact field set, pending null in M1.
	clock := &fakeClock{now: time.Date(2026, 1, 1, 10, 0, 0, 0, time.UTC)}
	audio := fake.NewAudio(35, false)
	var logs bytes.Buffer
	h := newStatusTestHandler(t, clock, audio, &logs)

	clock.Advance(11520 * time.Second)
	rec := statusRequest(h, lanAddr, bearer(testTokenA))

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200: %s", rec.Code, rec.Body.String())
	}
	if ct := rec.Header().Get("Content-Type"); ct != "application/json; charset=utf-8" {
		t.Errorf("Content-Type = %q", ct)
	}
	want := `{"data":{"name":"Laptop-Test","version":"1.0.0","uptimeSeconds":11520,"volume":{"level":35,"muted":false},"pending":null}}`
	if got := rec.Body.String(); got != want {
		t.Fatalf("body = %s\nwant   %s", got, want)
	}
	data := decodeStatus(t, rec.Body.Bytes())
	if len(data) != 5 {
		t.Errorf("data has %d fields, want 5: %v", len(data), data)
	}
}

func TestStatusUptimeFollowsClock(t *testing.T) {
	clock := &fakeClock{now: time.Date(2026, 1, 1, 10, 0, 0, 0, time.UTC)}
	h := newStatusTestHandler(t, clock, fake.NewAudio(10, false), &bytes.Buffer{})

	tests := []struct {
		advance time.Duration
		want    float64
	}{
		{0, 0},
		{1500 * time.Millisecond, 1}, // whole seconds, rounded down
		{58 * time.Second, 59},
	}
	for _, tt := range tests {
		clock.Advance(tt.advance)
		data := decodeStatus(t, statusRequest(h, lanAddr, bearer(testTokenA)).Body.Bytes())
		if data["uptimeSeconds"] != tt.want {
			t.Errorf("uptimeSeconds = %v, want %v", data["uptimeSeconds"], tt.want)
		}
	}
}

func TestStatusUptimeNeverNegative(t *testing.T) {
	clock := &fakeClock{now: time.Date(2026, 1, 1, 10, 0, 0, 0, time.UTC)}
	deps := StatusDeps{Name: "x", Version: "1", StartedAt: clock.Now().Add(time.Minute), Now: clock.Now, Audio: fake.NewAudio(1, false)}
	h := NewAPIHandler(newTestLogger(&bytes.Buffer{}), staticToken(testTokenA), deps)

	data := decodeStatus(t, statusRequest(h, lanAddr, bearer(testTokenA)).Body.Bytes())
	if data["uptimeSeconds"] != float64(0) {
		t.Errorf("uptimeSeconds = %v, want 0", data["uptimeSeconds"])
	}
}

func TestStatusVolumeNullWhenAudioFails(t *testing.T) {
	// api-spec Status: volume null when Core Audio fails, still 200.
	clock := &fakeClock{now: time.Date(2026, 1, 1, 10, 0, 0, 0, time.UTC)}
	audio := fake.NewAudio(35, false)
	audio.SetErr(errors.New("core audio down"))
	h := newStatusTestHandler(t, clock, audio, &bytes.Buffer{})

	rec := statusRequest(h, lanAddr, bearer(testTokenA))
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", rec.Code)
	}
	data := decodeStatus(t, rec.Body.Bytes())
	if v, ok := data["volume"]; !ok || v != nil {
		t.Errorf("volume = %v (present=%v), want null", v, ok)
	}
	if strings.Contains(rec.Body.String(), "core audio down") {
		t.Errorf("body leaks internal error: %s", rec.Body.String())
	}
}

func TestStatusLogsWarningWhenAudioFails(t *testing.T) {
	// Audio failure stays a 200 with volume null, but the cause must reach the log
	// without leaking into the response body.
	clock := &fakeClock{now: time.Date(2026, 1, 1, 10, 0, 0, 0, time.UTC)}
	audio := fake.NewAudio(35, false)
	audio.SetErr(errors.New("core audio down"))
	var logs bytes.Buffer
	h := newStatusTestHandler(t, clock, audio, &logs)

	rec := statusRequest(h, lanAddr, bearer(testTokenA))
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", rec.Code)
	}
	data := decodeStatus(t, rec.Body.Bytes())
	if v, ok := data["volume"]; !ok || v != nil {
		t.Errorf("volume = %v (present=%v), want null", v, ok)
	}
	if strings.Contains(rec.Body.String(), "core audio down") {
		t.Errorf("body leaks internal error: %s", rec.Body.String())
	}
	if !strings.Contains(logs.String(), "status audio read failed") {
		t.Errorf("log missing warning message: %s", logs.String())
	}
	if !strings.Contains(logs.String(), "core audio down") {
		t.Errorf("log missing error detail: %s", logs.String())
	}
}

func TestStatusNilAudioReportsNullVolume(t *testing.T) {
	deps := StatusDeps{Name: "x", Version: "1", StartedAt: time.Now()}
	h := NewAPIHandler(newTestLogger(&bytes.Buffer{}), staticToken(testTokenA), deps)

	data := decodeStatus(t, statusRequest(h, lanAddr, bearer(testTokenA)).Body.Bytes())
	if data["volume"] != nil {
		t.Errorf("volume = %v, want null", data["volume"])
	}
}

func TestStatusPendingFromDeps(t *testing.T) {
	deps := StatusDeps{
		Name: "x", Version: "1", StartedAt: time.Now(),
		Audio: fake.NewAudio(1, false),
		Pending: func() any {
			return map[string]any{"action": "sleep", "remainingMs": 3000, "delayMs": 5000}
		},
	}
	h := NewAPIHandler(newTestLogger(&bytes.Buffer{}), staticToken(testTokenA), deps)

	data := decodeStatus(t, statusRequest(h, lanAddr, bearer(testTokenA)).Body.Bytes())
	p, ok := data["pending"].(map[string]any)
	if !ok || p["action"] != "sleep" || p["remainingMs"] != float64(3000) {
		t.Errorf("pending = %v, want sleep schedule", data["pending"])
	}
}

// BR-5 / api-spec Status: pending is the full Pending object while a schedule
// is active, with the same field names as the /power responses.
func TestStatusPendingObjectWhileScheduled(t *testing.T) {
	clock := fake.NewClock(powerStart)
	sched := control.NewPowerScheduler(&fake.Power{}, control.PowerOptions{Clock: clock, Logger: newTestLogger(&bytes.Buffer{})})
	t.Cleanup(sched.Close)
	deps := StatusDeps{Name: "x", Version: "1", StartedAt: powerStart, Now: clock.Now, Audio: fake.NewAudio(1, false)}
	h := NewAPIHandler(newTestLogger(&bytes.Buffer{}), staticToken(testTokenA), deps, WithPower(sched))

	if _, err := sched.Schedule(context.Background(), control.PowerRestart); err != nil {
		t.Fatalf("Schedule() error = %v", err)
	}
	clock.Advance(2 * time.Second)

	rec := statusRequest(h, lanAddr, bearer(testTokenA))
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", rec.Code)
	}
	want := `"pending":{"action":"restart","remainingMs":3000,"delayMs":5000,"scheduledAt":"` + powerScheduledAt + `"}`
	if !strings.Contains(rec.Body.String(), want) {
		t.Errorf("body = %s, want it to contain %s", rec.Body.String(), want)
	}
	data := decodeStatus(t, rec.Body.Bytes())
	p, ok := data["pending"].(map[string]any)
	if !ok || len(p) != 4 {
		t.Fatalf("pending = %v, want an object with 4 fields", data["pending"])
	}
}

// api-spec Status: pending is null when nothing is scheduled, with the power
// scheduler wired in.
func TestStatusPendingNullWhenIdleWithScheduler(t *testing.T) {
	clock := fake.NewClock(powerStart)
	sched := control.NewPowerScheduler(&fake.Power{}, control.PowerOptions{Clock: clock, Logger: newTestLogger(&bytes.Buffer{})})
	t.Cleanup(sched.Close)
	deps := StatusDeps{Name: "x", Version: "1", StartedAt: powerStart, Now: clock.Now, Audio: fake.NewAudio(1, false)}
	h := NewAPIHandler(newTestLogger(&bytes.Buffer{}), staticToken(testTokenA), deps, WithPower(sched))

	rec := statusRequest(h, lanAddr, bearer(testTokenA))
	if !strings.Contains(rec.Body.String(), `"pending":null`) {
		t.Errorf("body = %s, want pending null", rec.Body.String())
	}
	if data := decodeStatus(t, rec.Body.Bytes()); data["pending"] != nil {
		t.Errorf("pending = %v, want null", data["pending"])
	}
}

func TestStatusRequiresToken(t *testing.T) {
	// BR-1 / BR-2: no token, malformed, short, wrong case, or wrong value -> 401.
	clock := &fakeClock{now: time.Now()}
	h := newStatusTestHandler(t, clock, fake.NewAudio(1, false), &bytes.Buffer{})

	tests := []struct {
		name   string
		header string
	}{
		{"no header", ""},
		{"no scheme", testTokenA},
		{"short token", bearer(testTokenA[:10])},
		{"upper-case token", bearer(strings.ToUpper(testTokenA))},
		{"wrong token", bearer(testTokenB)},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			rec := statusRequest(h, lanAddr, tt.header)
			if rec.Code != http.StatusUnauthorized {
				t.Fatalf("status = %d, want 401", rec.Code)
			}
			if !strings.Contains(rec.Body.String(), `"code":"invalid_token"`) {
				t.Errorf("body = %s, want invalid_token", rec.Body.String())
			}
		})
	}
}

func TestStatusForbiddenFromPublicIPBeforeAuth(t *testing.T) {
	// BR-12: NetworkFilter runs before Auth, so a public source gets 403
	// even without a token.
	clock := &fakeClock{now: time.Now()}
	h := newStatusTestHandler(t, clock, fake.NewAudio(1, false), &bytes.Buffer{})

	for _, header := range []string{"", bearer(testTokenA)} {
		rec := statusRequest(h, "8.8.8.8:50000", header)
		if rec.Code != http.StatusForbidden {
			t.Fatalf("header %q: status = %d, want 403", header, rec.Code)
		}
		if !strings.Contains(rec.Body.String(), `"code":"forbidden_network"`) {
			t.Errorf("body = %s, want forbidden_network", rec.Body.String())
		}
	}
}

func TestStatusMethodNotAllowed(t *testing.T) {
	clock := &fakeClock{now: time.Now()}
	h := newStatusTestHandler(t, clock, fake.NewAudio(1, false), &bytes.Buffer{})

	req := httptest.NewRequest(http.MethodPost, APIPrefix+"/status", nil)
	req.RemoteAddr = lanAddr
	req.Header.Set("Authorization", bearer(testTokenA))
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)

	if rec.Code != http.StatusMethodNotAllowed {
		t.Fatalf("status = %d, want 405", rec.Code)
	}
	if allow := rec.Header().Get("Allow"); allow != "GET" {
		t.Errorf("Allow = %q, want GET", allow)
	}
}

func TestStatusNeverContainsToken(t *testing.T) {
	clock := &fakeClock{now: time.Now()}
	var logs bytes.Buffer
	h := newStatusTestHandler(t, clock, fake.NewAudio(1, false), &logs)

	rec := statusRequest(h, lanAddr, bearer(testTokenA))
	if strings.Contains(rec.Body.String(), testTokenA) {
		t.Fatalf("response contains token: %s", rec.Body.String())
	}
	if strings.Contains(logs.String(), testTokenA) {
		t.Fatalf("log contains token: %s", logs.String())
	}
}

func TestStatusHandlerUsesContextFromRequest(t *testing.T) {
	// The audio read gets a bounded context derived from the request.
	ctxAudio := &ctxRecordingAudio{}
	deps := StatusDeps{Name: "x", Version: "1", StartedAt: time.Now(), Audio: ctxAudio}
	h := newStatusHandler(deps, nil)

	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, APIPrefix+"/status", nil))
	if ctxAudio.deadline.IsZero() {
		t.Fatal("audio context has no deadline")
	}
}

// ctxRecordingAudio records the context passed to Volume.
type ctxRecordingAudio struct {
	fake.Audio
	deadline time.Time
}

func (c *ctxRecordingAudio) Volume(ctx context.Context) (control.Volume, error) {
	c.deadline, _ = ctx.Deadline()
	return control.Volume{Level: 1}, nil
}

func TestUptimeSeconds(t *testing.T) {
	tests := []struct {
		d    time.Duration
		want int64
	}{
		{-time.Second, 0},
		{0, 0},
		{999 * time.Millisecond, 0},
		{time.Second, 1},
		{11520 * time.Second, 11520},
	}
	for _, tt := range tests {
		if got := uptimeSeconds(tt.d); got != tt.want {
			t.Errorf("uptimeSeconds(%v) = %d, want %d", tt.d, got, tt.want)
		}
	}
}
