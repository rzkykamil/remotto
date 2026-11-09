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

// powerStart is the fake clock start. Its offset is +07:00, so scheduledAt
// reads like a laptop clock in Indonesia.
var powerStart = time.Date(2026, 1, 1, 23, 40, 0, 0, time.FixedZone("WIB", 7*3600))

// powerScheduledAt is the scheduledAt value of a schedule made at powerStart.
const powerScheduledAt = "2026-01-01T23:40:00+07:00"

// powerPaths lists the four /power routes (docs/api-spec.md, section "Daya").
var powerPaths = []string{"/power/sleep", "/power/restart", "/power/shutdown", "/power/cancel"}

// schedulePaths lists the three schedule routes.
var schedulePaths = []struct {
	path   string
	action control.PowerAction
}{
	{"/power/sleep", control.PowerSleep},
	{"/power/restart", control.PowerRestart},
	{"/power/shutdown", control.PowerShutdown},
}

// holdPower is a PowerController whose Execute blocks until Unblock. It
// forwards the call to inner once released, so tests can still read the calls.
type holdPower struct {
	inner   *fake.Power
	started chan control.PowerAction
	release chan struct{}
	once    sync.Once
}

func newHoldPower() *holdPower {
	return &holdPower{
		inner:   &fake.Power{},
		started: make(chan control.PowerAction, 1),
		release: make(chan struct{}),
	}
}

func (p *holdPower) Execute(ctx context.Context, action control.PowerAction) error {
	p.started <- action
	<-p.release
	return p.inner.Execute(ctx, action)
}

// Unblock lets a blocked Execute return. It is safe to call more than once.
func (p *holdPower) Unblock() {
	p.once.Do(func() { close(p.release) })
}

// powerEnv is the full handler with a fake clock and a PowerScheduler over ctrl.
type powerEnv struct {
	clock *fake.Clock
	h     http.Handler
	logs  *bytes.Buffer
}

func newPowerEnv(t *testing.T, ctrl control.PowerController) *powerEnv {
	t.Helper()
	clock := fake.NewClock(powerStart)
	logs := &bytes.Buffer{}
	logger := newTestLogger(logs)
	sched := control.NewPowerScheduler(ctrl, control.PowerOptions{Clock: clock, Logger: logger})
	t.Cleanup(sched.Close)
	deps := StatusDeps{
		Name:      "Laptop-Test",
		Version:   "test",
		StartedAt: powerStart,
		Now:       clock.Now,
		Audio:     fake.NewAudio(35, false),
	}
	h := NewAPIHandler(logger, staticToken(testTokenA), deps, WithPower(sched))
	return &powerEnv{clock: clock, h: h, logs: logs}
}

// powerRequest sends one request from addr with the given Authorization header.
func powerRequest(h http.Handler, method, path, addr, authHeader string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(method, path, nil)
	req.RemoteAddr = addr
	if authHeader != "" {
		req.Header.Set("Authorization", authHeader)
	}
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	return rec
}

// powerPost sends an authorized POST from the LAN to path under APIPrefix.
func powerPost(h http.Handler, path string) *httptest.ResponseRecorder {
	return powerRequest(h, http.MethodPost, APIPrefix+path, lanAddr, bearer(testTokenA))
}

// statusPending returns the pending value of a 200 status response.
func statusPending(t *testing.T, h http.Handler) any {
	t.Helper()
	rec := statusRequest(h, lanAddr, bearer(testTokenA))
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200: %s", rec.Code, rec.Body.String())
	}
	return decodeStatus(t, rec.Body.Bytes())["pending"]
}

// assertFastResponse fails when elapsed reaches 100 ms (docs/technical-spec.md).
func assertFastResponse(t *testing.T, what string, elapsed time.Duration) {
	t.Helper()
	if elapsed >= 100*time.Millisecond {
		t.Errorf("%s took %v, want < 100ms", what, elapsed)
	}
}

// advanceAsync runs clock.Advance in its own goroutine. The returned channel is
// closed when Advance returns.
func advanceAsync(clock *fake.Clock, d time.Duration) <-chan struct{} {
	done := make(chan struct{})
	go func() {
		clock.Advance(d)
		close(done)
	}()
	return done
}

// waitStarted waits until holdPower.Execute begins and returns its action.
func waitStarted(t *testing.T, p *holdPower) control.PowerAction {
	t.Helper()
	select {
	case a := <-p.started:
		return a
	case <-time.After(5 * time.Second):
		t.Fatal("Execute was not called within 5s")
		return ""
	}
}

// waitDone fails the test when done is not closed within 5s.
func waitDone(t *testing.T, done <-chan struct{}) {
	t.Helper()
	select {
	case <-done:
	case <-time.After(5 * time.Second):
		t.Fatal("Advance did not return within 5s")
	}
}

// BR-4: each schedule route answers 202 with the full Pending object, and the
// OS is not called yet.
func TestBR4_ScheduleAcceptedWithPendingObject(t *testing.T) {
	for _, tt := range schedulePaths {
		t.Run(tt.path, func(t *testing.T) {
			fp := &fake.Power{}
			env := newPowerEnv(t, fp)

			rec := powerPost(env.h, tt.path)
			if rec.Code != http.StatusAccepted {
				t.Fatalf("status = %d, want 202 (body %q)", rec.Code, rec.Body.String())
			}
			if ct := rec.Header().Get("Content-Type"); ct != "application/json; charset=utf-8" {
				t.Errorf("Content-Type = %q", ct)
			}
			want := `{"data":{"pending":{"action":"` + string(tt.action) +
				`","remainingMs":5000,"delayMs":5000,"scheduledAt":"` + powerScheduledAt + `"}}}`
			if got := rec.Body.String(); got != want {
				t.Errorf("body = %s\nwant   %s", got, want)
			}
			if calls := fp.Calls(); len(calls) != 0 {
				t.Errorf("Execute called before the delay: %v", calls)
			}
		})
	}
}

// BR-4: the schedule answer and the status read stay fast while Execute is
// blocked, so no request waits for the OS.
func TestBR4_ResponsesFastWhileExecuteBlocked(t *testing.T) {
	hp := newHoldPower()
	t.Cleanup(hp.Unblock)
	env := newPowerEnv(t, hp)

	start := time.Now()
	if rec := powerPost(env.h, "/power/sleep"); rec.Code != http.StatusAccepted {
		t.Fatalf("schedule status = %d, want 202", rec.Code)
	}
	assertFastResponse(t, "schedule", time.Since(start))

	done := advanceAsync(env.clock, control.PowerDelay)
	if got := waitStarted(t, hp); got != control.PowerSleep {
		t.Fatalf("Execute action = %q, want sleep", got)
	}

	start = time.Now()
	rec := statusRequest(env.h, lanAddr, bearer(testTokenA))
	assertFastResponse(t, "status while executing", time.Since(start))
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", rec.Code)
	}

	start = time.Now()
	rec = powerPost(env.h, "/power/restart")
	assertFastResponse(t, "schedule while executing", time.Since(start))
	if rec.Code != http.StatusConflict {
		t.Fatalf("schedule while executing status = %d, want 409", rec.Code)
	}

	hp.Unblock()
	waitDone(t, done)
}

// BR-4: the command runs once, after the full 5 s delay, and the pending state
// is cleared afterwards.
func TestBR4_ExecutesOnceAfterDelay(t *testing.T) {
	fp := &fake.Power{}
	env := newPowerEnv(t, fp)

	if rec := powerPost(env.h, "/power/restart"); rec.Code != http.StatusAccepted {
		t.Fatalf("schedule status = %d, want 202", rec.Code)
	}

	env.clock.Advance(control.PowerDelay - time.Millisecond)
	if calls := fp.Calls(); len(calls) != 0 {
		t.Fatalf("Execute called at 4999ms: %v", calls)
	}
	p, ok := statusPending(t, env.h).(map[string]any)
	if !ok || p["remainingMs"] != float64(1) {
		t.Fatalf("pending at 4999ms = %v, want remainingMs 1", p)
	}

	env.clock.Advance(time.Millisecond)
	if calls := fp.Calls(); len(calls) != 1 || calls[0] != control.PowerRestart {
		t.Fatalf("Calls() = %v, want [restart]", calls)
	}
	if got := statusPending(t, env.h); got != nil {
		t.Errorf("pending after execution = %v, want null", got)
	}

	rec := powerPost(env.h, "/power/cancel")
	if !strings.Contains(rec.Body.String(), `"code":"`+CodeNoPendingPower+`"`) {
		t.Errorf("cancel after execution: body %q, want no_pending_power", rec.Body.String())
	}
}

// BR-5: a second schedule is 409 power_pending. The first schedule stays and
// /status keeps showing it.
func TestBR5_SecondScheduleRejected(t *testing.T) {
	fp := &fake.Power{}
	env := newPowerEnv(t, fp)

	if rec := powerPost(env.h, "/power/sleep"); rec.Code != http.StatusAccepted {
		t.Fatalf("first schedule status = %d, want 202", rec.Code)
	}
	env.clock.Advance(2 * time.Second)

	rec := powerPost(env.h, "/power/shutdown")
	if rec.Code != http.StatusConflict {
		t.Fatalf("second schedule status = %d, want 409 (body %q)", rec.Code, rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), `"code":"`+CodePowerPending+`"`) {
		t.Errorf("body %q lacks power_pending", rec.Body.String())
	}

	p, ok := statusPending(t, env.h).(map[string]any)
	if !ok {
		t.Fatalf("pending = %v, want the first schedule", p)
	}
	if p["action"] != "sleep" || p["remainingMs"] != float64(3000) {
		t.Errorf("pending = %v, want sleep with remainingMs 3000", p)
	}

	env.clock.Advance(3 * time.Second)
	if calls := fp.Calls(); len(calls) != 1 || calls[0] != control.PowerSleep {
		t.Errorf("Calls() = %v, want [sleep] only", calls)
	}
}

// BR-17: cancel removes the schedule. The OS is not called afterwards, and
// /status reports pending null.
func TestBR17_CancelSucceeds(t *testing.T) {
	fp := &fake.Power{}
	env := newPowerEnv(t, fp)

	if rec := powerPost(env.h, "/power/shutdown"); rec.Code != http.StatusAccepted {
		t.Fatalf("schedule status = %d, want 202", rec.Code)
	}
	env.clock.Advance(time.Second)

	rec := powerPost(env.h, "/power/cancel")
	if rec.Code != http.StatusOK {
		t.Fatalf("cancel status = %d, want 200 (body %q)", rec.Code, rec.Body.String())
	}
	if got, want := rec.Body.String(), `{"data":{"cancelled":"shutdown","pending":null}}`; got != want {
		t.Errorf("body = %s, want %s", got, want)
	}

	if !strings.Contains(statusRequest(env.h, lanAddr, bearer(testTokenA)).Body.String(), `"pending":null`) {
		t.Errorf("status after cancel does not report pending null")
	}

	env.clock.Advance(10 * time.Second)
	if calls := fp.Calls(); len(calls) != 0 {
		t.Errorf("Calls() = %v after cancel, want none", calls)
	}
}

// BR-17: cancel with nothing scheduled is 409 no_pending_power.
func TestBR17_CancelWithoutScheduleIsConflict(t *testing.T) {
	fp := &fake.Power{}
	env := newPowerEnv(t, fp)

	rec := powerPost(env.h, "/power/cancel")
	if rec.Code != http.StatusConflict {
		t.Fatalf("status = %d, want 409 (body %q)", rec.Code, rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), `"code":"`+CodeNoPendingPower+`"`) {
		t.Errorf("body %q lacks no_pending_power", rec.Body.String())
	}
	if calls := fp.Calls(); len(calls) != 0 {
		t.Errorf("Calls() = %v, want none", calls)
	}
}

// BR-17: cancel after the OS call started is 409 power_executing. /status shows
// the command as executing (remainingMs 0). Schedules are rejected meanwhile.
func TestBR17_CancelWhileExecutingIsConflict(t *testing.T) {
	hp := newHoldPower()
	t.Cleanup(hp.Unblock)
	env := newPowerEnv(t, hp)

	if rec := powerPost(env.h, "/power/sleep"); rec.Code != http.StatusAccepted {
		t.Fatalf("schedule status = %d, want 202", rec.Code)
	}
	done := advanceAsync(env.clock, control.PowerDelay)
	if got := waitStarted(t, hp); got != control.PowerSleep {
		t.Fatalf("Execute action = %q, want sleep", got)
	}

	rec := powerPost(env.h, "/power/cancel")
	if rec.Code != http.StatusConflict {
		t.Fatalf("cancel status = %d, want 409 (body %q)", rec.Code, rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), `"code":"`+CodePowerExecuting+`"`) {
		t.Errorf("body %q lacks power_executing", rec.Body.String())
	}

	p, ok := statusPending(t, env.h).(map[string]any)
	if !ok {
		t.Fatalf("pending = %v, want the executing schedule", p)
	}
	if p["action"] != "sleep" || p["remainingMs"] != float64(0) || p["delayMs"] != float64(5000) {
		t.Errorf("pending = %v, want sleep with remainingMs 0 and delayMs 5000", p)
	}

	hp.Unblock()
	waitDone(t, done)
	if calls := hp.inner.Calls(); len(calls) != 1 || calls[0] != control.PowerSleep {
		t.Errorf("Calls() = %v, want exactly [sleep]", calls)
	}
}

// Without WithPower the routes exist and fail closed: 500 power_failed with a
// generic message. The cause is logged only.
func TestPowerWithoutSchedulerFailsClosed(t *testing.T) {
	var logs bytes.Buffer
	deps := StatusDeps{Name: "x", Version: "1", StartedAt: powerStart, Now: func() time.Time { return powerStart }}
	h := NewAPIHandler(newTestLogger(&logs), staticToken(testTokenA), deps)

	for _, tt := range schedulePaths {
		t.Run(tt.path, func(t *testing.T) {
			rec := powerPost(h, tt.path)
			if rec.Code != http.StatusInternalServerError {
				t.Fatalf("status = %d, want 500 (body %q)", rec.Code, rec.Body.String())
			}
			want := `{"error":{"code":"power_failed","message":"power scheduling failed"}}`
			if got := rec.Body.String(); got != want {
				t.Errorf("body = %s, want %s", got, want)
			}
		})
	}
	if !strings.Contains(logs.String(), "power failed") {
		t.Errorf("log lacks power failed: %s", logs.String())
	}
	if !strings.Contains(logs.String(), "operation not supported") {
		t.Errorf("log lacks the cause: %s", logs.String())
	}
	if got := statusPending(t, h); got != nil {
		t.Errorf("pending = %v, want null", got)
	}
}

// An OS failure after the delay does not change the 202 already sent. The
// schedule is cleared, and the error reaches the log only.
func TestPowerExecuteFailureClearsScheduleAndLogs(t *testing.T) {
	fp := &fake.Power{}
	fp.SetErr(errors.New("secret os detail"))
	env := newPowerEnv(t, fp)

	rec := powerPost(env.h, "/power/shutdown")
	if rec.Code != http.StatusAccepted {
		t.Fatalf("schedule status = %d, want 202", rec.Code)
	}

	env.clock.Advance(control.PowerDelay)
	if calls := fp.Calls(); len(calls) != 1 || calls[0] != control.PowerShutdown {
		t.Errorf("Calls() = %v, want [shutdown]", calls)
	}
	if got := statusPending(t, env.h); got != nil {
		t.Errorf("pending after failed execute = %v, want null", got)
	}

	statusBody := statusRequest(env.h, lanAddr, bearer(testTokenA)).Body.String()
	if strings.Contains(statusBody, "secret os detail") {
		t.Errorf("status leaks OS detail: %s", statusBody)
	}
	if !strings.Contains(env.logs.String(), "power execute failed") {
		t.Errorf("log lacks power execute failed: %s", env.logs.String())
	}
	if !strings.Contains(env.logs.String(), "secret os detail") {
		t.Errorf("log lacks OS cause: %s", env.logs.String())
	}

	if rec := powerPost(env.h, "/power/cancel"); !strings.Contains(rec.Body.String(), CodeNoPendingPower) {
		t.Errorf("cancel after failed execute: body %q, want no_pending_power", rec.Body.String())
	}
}

// BR-1: every /power route refuses a missing or wrong token before the
// scheduler is touched. A wrong-token cancel leaves the schedule alone.
func TestPowerRequiresToken(t *testing.T) {
	for _, path := range powerPaths {
		for _, auth := range []string{"", bearer(testTokenB)} {
			t.Run(path+" auth="+auth, func(t *testing.T) {
				fp := &fake.Power{}
				env := newPowerEnv(t, fp)

				rec := powerRequest(env.h, http.MethodPost, APIPrefix+path, lanAddr, auth)
				if rec.Code != http.StatusUnauthorized {
					t.Fatalf("status = %d, want 401", rec.Code)
				}
				if !strings.Contains(rec.Body.String(), `"code":"`+CodeInvalidToken+`"`) {
					t.Errorf("body %q lacks invalid_token", rec.Body.String())
				}
				env.clock.Advance(10 * time.Second)
				if calls := fp.Calls(); len(calls) != 0 {
					t.Errorf("Calls() = %v, want none", calls)
				}
			})
		}
	}

	fp := &fake.Power{}
	env := newPowerEnv(t, fp)
	if rec := powerPost(env.h, "/power/sleep"); rec.Code != http.StatusAccepted {
		t.Fatalf("schedule status = %d, want 202", rec.Code)
	}
	rec := powerRequest(env.h, http.MethodPost, APIPrefix+"/power/cancel", lanAddr, bearer(testTokenB))
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("cancel with wrong token status = %d, want 401", rec.Code)
	}
	if p, ok := statusPending(t, env.h).(map[string]any); !ok || p["action"] != "sleep" {
		t.Errorf("pending = %v, want the sleep schedule kept", p)
	}
}

// G-7: every /power route is registered on the real handler. A GET is 405
// (the route exists), not 404.
func TestPowerRoutesRegisteredAndMethodChecked(t *testing.T) {
	env := newPowerEnv(t, &fake.Power{})
	for _, path := range powerPaths {
		t.Run(path, func(t *testing.T) {
			rec := powerRequest(env.h, http.MethodGet, APIPrefix+path, lanAddr, bearer(testTokenA))
			if rec.Code != http.StatusMethodNotAllowed {
				t.Fatalf("GET status = %d, want 405", rec.Code)
			}
			if allow := rec.Header().Get("Allow"); allow != "POST" {
				t.Errorf("Allow = %q, want POST", allow)
			}
		})
	}
}

// BR-11: no token, query token, or OS detail reaches the log or a response
// body on the power routes.
func TestBR11_PowerNeverLogsOrEchoesSecrets(t *testing.T) {
	fp := &fake.Power{}
	env := newPowerEnv(t, fp)

	bodies := []string{}
	record := func(rec *httptest.ResponseRecorder) { bodies = append(bodies, rec.Body.String()) }

	record(powerPost(env.h, "/power/sleep"))
	record(powerPost(env.h, "/power/cancel"))
	record(powerRequest(env.h, http.MethodPost, APIPrefix+"/power/restart?token="+testTokenA, lanAddr, ""))
	record(powerRequest(env.h, http.MethodPost, APIPrefix+"/power/restart", lanAddr, bearer(wrongToken)))

	for _, b := range bodies {
		assertNoSecrets(t, "response body", b)
	}
	assertNoSecrets(t, "log", env.logs.String())
}

// Confirm the JSON shape of a 202 body, so the Pending object stays in step
// with docs/api-spec.md.
func TestPendingViewJSONFields(t *testing.T) {
	raw, err := json.Marshal(pendingView(control.PendingPower{
		Action:      control.PowerShutdown,
		Remaining:   4 * time.Second,
		Delay:       control.PowerDelay,
		ScheduledAt: powerStart,
	}))
	if err != nil {
		t.Fatal(err)
	}
	want := `{"action":"shutdown","remainingMs":4000,"delayMs":5000,"scheduledAt":"` + powerScheduledAt + `"}`
	if got := string(raw); got != want {
		t.Errorf("pending = %s, want %s", got, want)
	}
}
