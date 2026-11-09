package server

import (
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strconv"
	"testing"
	"time"
)

// rateClock is a manually advanced clock for rate limit tests.
type rateClock struct {
	now time.Time
}

func (c *rateClock) Now() time.Time { return c.now }

func (c *rateClock) Advance(d time.Duration) { c.now = c.now.Add(d) }

var rateTestStart = time.Date(2026, 1, 1, 12, 0, 0, 0, time.UTC)

func newRateTestHandler(rps, burst int, clk *rateClock, calls *int) http.Handler {
	logger := slog.New(slog.NewTextHandler(io.Discard, nil))
	inner := http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		*calls++
		w.WriteHeader(http.StatusOK)
	})
	return Chain(inner, RateLimit(logger, rps, burst, clk.Now))
}

func serveFrom(h http.Handler, remoteAddr string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(http.MethodGet, "/status", nil)
	req.RemoteAddr = remoteAddr
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	return rec
}

func TestRateLimitBurstThenTooManyRequests(t *testing.T) {
	cases := []struct {
		name    string
		rps     int
		burst   int
		allowed int
	}{
		{name: "default 20/40", rps: 20, burst: 40, allowed: 40},
		{name: "burst 2", rps: 1, burst: 2, allowed: 2},
		{name: "burst 1", rps: 3, burst: 1, allowed: 1},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			clk := &rateClock{now: rateTestStart}
			calls := 0
			h := newRateTestHandler(tc.rps, tc.burst, clk, &calls)

			for i := 0; i < tc.allowed; i++ {
				if rec := serveFrom(h, "192.0.2.10:5000"); rec.Code != http.StatusOK {
					t.Fatalf("request %d: status = %d, want 200", i+1, rec.Code)
				}
			}

			rec := serveFrom(h, "192.0.2.10:5000")
			if rec.Code != http.StatusTooManyRequests {
				t.Fatalf("over burst: status = %d, want 429", rec.Code)
			}
			secs, err := strconv.Atoi(rec.Header().Get("Retry-After"))
			if err != nil || secs < 1 {
				t.Fatalf("Retry-After = %q, want integer >= 1", rec.Header().Get("Retry-After"))
			}
			if calls != tc.allowed {
				t.Fatalf("inner handler calls = %d, want %d (429 must not reach handler)", calls, tc.allowed)
			}
		})
	}
}

func TestRateLimitRefillsOverTime(t *testing.T) {
	clk := &rateClock{now: rateTestStart}
	calls := 0
	h := newRateTestHandler(2, 1, clk, &calls) // one token every 500 ms

	if rec := serveFrom(h, "192.0.2.10:1"); rec.Code != http.StatusOK {
		t.Fatalf("first request: status = %d, want 200", rec.Code)
	}
	if rec := serveFrom(h, "192.0.2.10:1"); rec.Code != http.StatusTooManyRequests {
		t.Fatalf("second request: status = %d, want 429", rec.Code)
	}

	clk.Advance(499 * time.Millisecond)
	if rec := serveFrom(h, "192.0.2.10:1"); rec.Code != http.StatusTooManyRequests {
		t.Fatalf("at 499ms: status = %d, want 429", rec.Code)
	}

	clk.Advance(1 * time.Millisecond)
	if rec := serveFrom(h, "192.0.2.10:1"); rec.Code != http.StatusOK {
		t.Fatalf("at 500ms: status = %d, want 200", rec.Code)
	}
}

func TestRateLimitRefillCappedAtBurst(t *testing.T) {
	clk := &rateClock{now: rateTestStart}
	calls := 0
	h := newRateTestHandler(10, 2, clk, &calls)

	clk.Advance(time.Hour) // long idle must not build up more than burst
	for i := 0; i < 2; i++ {
		if rec := serveFrom(h, "192.0.2.10:1"); rec.Code != http.StatusOK {
			t.Fatalf("request %d after idle: status = %d, want 200", i+1, rec.Code)
		}
	}
	if rec := serveFrom(h, "192.0.2.10:1"); rec.Code != http.StatusTooManyRequests {
		t.Fatalf("third request: status = %d, want 429 (burst is 2)", rec.Code)
	}
}

func TestRateLimitKeysByIP(t *testing.T) {
	cases := []struct {
		name     string
		first    string
		second   string
		wantSame bool // true when second should share first's bucket
	}{
		{name: "different IPs are independent", first: "192.0.2.1:1000", second: "192.0.2.2:1000", wantSame: false},
		{name: "same IP different port shares bucket", first: "192.0.2.1:1000", second: "192.0.2.1:2000", wantSame: true},
		{name: "IPv4-mapped IPv6 shares bucket with IPv4", first: "192.0.2.1:1000", second: "[::ffff:192.0.2.1]:2000", wantSame: true},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			clk := &rateClock{now: rateTestStart}
			calls := 0
			h := newRateTestHandler(1, 1, clk, &calls)

			if rec := serveFrom(h, tc.first); rec.Code != http.StatusOK {
				t.Fatalf("first IP first request: status = %d, want 200", rec.Code)
			}
			rec := serveFrom(h, tc.second)
			limited := rec.Code == http.StatusTooManyRequests
			if limited != tc.wantSame {
				t.Fatalf("second request limited = %v, want %v (status %d)", limited, tc.wantSame, rec.Code)
			}
		})
	}
}

func TestRateLimitRetryAfterRounding(t *testing.T) {
	cases := []struct {
		wait time.Duration
		want int
	}{
		{wait: 0, want: 1},
		{wait: 50 * time.Millisecond, want: 1},
		{wait: time.Second, want: 1},
		{wait: 1200 * time.Millisecond, want: 2},
		{wait: 2 * time.Second, want: 2},
	}
	for _, tc := range cases {
		if got := retryAfterSeconds(tc.wait); got != tc.want {
			t.Errorf("retryAfterSeconds(%v) = %d, want %d", tc.wait, got, tc.want)
		}
	}
}

func TestRateLimitBodyIsRateLimitedEnvelope(t *testing.T) {
	clk := &rateClock{now: rateTestStart}
	calls := 0
	h := newRateTestHandler(1, 1, clk, &calls)
	serveFrom(h, "192.0.2.10:1")

	rec := serveFrom(h, "192.0.2.10:1")
	if rec.Code != http.StatusTooManyRequests {
		t.Fatalf("status = %d, want 429", rec.Code)
	}
	var body struct {
		Error struct {
			Code    string `json:"code"`
			Message string `json:"message"`
		} `json:"error"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("body is not JSON: %v: %q", err, rec.Body.String())
	}
	if body.Error.Code != "rate_limited" {
		t.Fatalf("error.code = %q, want rate_limited", body.Error.Code)
	}
	if body.Error.Message == "" {
		t.Fatal("error.message is empty")
	}
}

// TestBR14_SliderEvery100msNeverLimited covers BR-14: the slider sends at most
// one request every 100 ms, which is 10 per second for 30 seconds. With the
// default 20/s and burst 40 this must never be limited.
func TestBR14_SliderEvery100msNeverLimited(t *testing.T) {
	clk := &rateClock{now: rateTestStart}
	calls := 0
	h := newRateTestHandler(20, 40, clk, &calls)

	const requests = 300 // 30 s at 100 ms
	for i := 0; i < requests; i++ {
		clk.now = rateTestStart.Add(time.Duration(i) * 100 * time.Millisecond)
		rec := serveFrom(h, "192.0.2.10:5000")
		if rec.Code != http.StatusOK {
			t.Fatalf("slider request %d at %v: status = %d, want 200", i, clk.now.Sub(rateTestStart), rec.Code)
		}
	}
	if calls != requests {
		t.Fatalf("inner handler calls = %d, want %d", calls, requests)
	}
}

func TestRateLimitSweepsIdleBuckets(t *testing.T) {
	clk := &rateClock{now: rateTestStart}
	rl := newRateLimiter(20, 40, clk.Now)

	rl.allow("192.0.2.1")
	clk.Advance(2 * time.Minute)
	rl.allow("192.0.2.2")

	if n := len(rl.buckets); n != 1 {
		t.Fatalf("buckets after idle sweep = %d, want 1", n)
	}
	if _, ok := rl.buckets["192.0.2.2"]; !ok {
		t.Fatal("active bucket was removed")
	}
}
