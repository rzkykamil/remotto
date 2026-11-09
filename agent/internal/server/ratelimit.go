package server

import (
	"log/slog"
	"math"
	"net"
	"net/http"
	"net/netip"
	"strconv"
	"sync"
	"time"
)

// rateIdleTTL is how long a bucket may sit unused before it is dropped. A
// bucket idle this long has refilled to burst anyway, so dropping it does not
// change any decision.
const rateIdleTTL = time.Minute

// rateSweepEvery triggers an idle sweep every N requests, in addition to the
// time-based sweep, so the map stays bounded under a burst of new IPs.
const rateSweepEvery = 256

// limiterClock returns the current time. Tests inject a fake clock.
type limiterClock func() time.Time

// tokenBucket holds the tokens left for one client IP.
type tokenBucket struct {
	tokens float64
	last   time.Time
}

// rateLimiter is a per-key token bucket. Each key gets up to burst tokens and
// refills at rps tokens per second.
type rateLimiter struct {
	mu        sync.Mutex
	rps       float64
	burst     float64
	now       limiterClock
	buckets   map[string]*tokenBucket
	calls     int
	lastSweep time.Time
}

func newRateLimiter(rps, burst float64, now limiterClock) *rateLimiter {
	return &rateLimiter{
		rps:     rps,
		burst:   burst,
		now:     now,
		buckets: make(map[string]*tokenBucket),
	}
}

// allow takes one token for key. When no token is left it returns false and
// the time until the next token is available.
func (rl *rateLimiter) allow(key string) (bool, time.Duration) {
	rl.mu.Lock()
	defer rl.mu.Unlock()

	now := rl.now()
	rl.calls++
	if rl.calls%rateSweepEvery == 0 || now.Sub(rl.lastSweep) >= rateIdleTTL {
		rl.sweep(now)
	}

	b, ok := rl.buckets[key]
	if !ok {
		b = &tokenBucket{tokens: rl.burst, last: now}
		rl.buckets[key] = b
	}
	if elapsed := now.Sub(b.last); elapsed > 0 {
		b.tokens = math.Min(rl.burst, b.tokens+elapsed.Seconds()*rl.rps)
	}
	b.last = now

	if b.tokens >= 1 {
		b.tokens--
		return true, 0
	}
	wait := (1 - b.tokens) / rl.rps
	return false, time.Duration(wait * float64(time.Second))
}

// sweep drops buckets idle for longer than rateIdleTTL.
func (rl *rateLimiter) sweep(now time.Time) {
	for key, b := range rl.buckets {
		if now.Sub(b.last) > rateIdleTTL {
			delete(rl.buckets, key)
		}
	}
	rl.lastSweep = now
}

// RateLimit allows rps requests per second per client IP, with a burst of
// burst requests. Requests over the limit get 429 with code rate_limited and a
// Retry-After header in whole seconds. The handler is not called for them.
//
// rps and burst must be at least 1. now is the clock; nil means time.Now.
// logger is accepted for symmetry with the other middleware. Rejections are not
// logged here, because Logging already records the 429.
func RateLimit(logger *slog.Logger, rps, burst int, now func() time.Time) Middleware {
	if rps < 1 || burst < 1 {
		panic("server: RateLimit needs rps >= 1 and burst >= 1")
	}
	if now == nil {
		now = time.Now
	}
	rl := newRateLimiter(float64(rps), float64(burst), limiterClock(now))
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			ok, wait := rl.allow(rateKey(r.RemoteAddr))
			if !ok {
				w.Header().Set("Retry-After", strconv.Itoa(retryAfterSeconds(wait)))
				WriteError(w, http.StatusTooManyRequests, CodeRateLimited, "too many requests")
				return
			}
			next.ServeHTTP(w, r)
		})
	}
}

// retryAfterSeconds rounds a wait up to whole seconds, with a minimum of 1.
func retryAfterSeconds(wait time.Duration) int {
	secs := int(math.Ceil(wait.Seconds()))
	if secs < 1 {
		return 1
	}
	return secs
}

// rateKey returns the client IP from RemoteAddr, without the port. IPv4-mapped
// IPv6 addresses are unmapped so that one client always gets one bucket.
func rateKey(remoteAddr string) string {
	host, _, err := net.SplitHostPort(remoteAddr)
	if err != nil {
		host = remoteAddr
	}
	addr, err := netip.ParseAddr(host)
	if err != nil {
		return host
	}
	return addr.Unmap().String()
}
