package discovery

import (
	"bytes"
	"context"
	"errors"
	"io"
	"log/slog"
	"net"
	"net/netip"
	"sync"
	"testing"
	"time"
)

// testAgentID is declared in txt_test.go.

const (
	testName    = "Laptop Kantor"
	testPort    = 8787
	harnessWait = 2 * time.Second
)

// fakeRegistrar records registrations and withdrawals in order. failNext makes
// that many upcoming Register calls fail.
type fakeRegistrar struct {
	mu       sync.Mutex
	failNext int
	attempts int
	services []Service
	events   []string
}

func (r *fakeRegistrar) Register(s Service) (io.Closer, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.attempts++
	if r.failNext > 0 {
		r.failNext--
		return nil, errors.New("fake register failure")
	}
	r.services = append(r.services, s)
	r.events = append(r.events, "register "+ipList(s.IPs))
	return &fakeCloser{reg: r}, nil
}

func (r *fakeRegistrar) eventLog() []string {
	r.mu.Lock()
	defer r.mu.Unlock()
	return append([]string(nil), r.events...)
}

func (r *fakeRegistrar) serviceList() []Service {
	r.mu.Lock()
	defer r.mu.Unlock()
	return append([]Service(nil), r.services...)
}

func (r *fakeRegistrar) attemptCount() int {
	r.mu.Lock()
	defer r.mu.Unlock()
	return r.attempts
}

// fakeCloser withdraws its registration on the fake registrar. A second Close
// is recorded as "close again" so tests catch double withdrawals.
type fakeCloser struct {
	reg    *fakeRegistrar
	closed bool
}

func (c *fakeCloser) Close() error {
	c.reg.mu.Lock()
	defer c.reg.mu.Unlock()
	if c.closed {
		c.reg.events = append(c.reg.events, "close again")
		return nil
	}
	c.closed = true
	c.reg.events = append(c.reg.events, "close")
	return nil
}

// fakeLister returns a settable interface list and counts List calls.
type fakeLister struct {
	mu     sync.Mutex
	ifaces []Iface
	err    error
	calls  int
}

func (l *fakeLister) List() ([]Iface, error) {
	l.mu.Lock()
	defer l.mu.Unlock()
	l.calls++
	if l.err != nil {
		return nil, l.err
	}
	return append([]Iface(nil), l.ifaces...), nil
}

func (l *fakeLister) set(ifaces []Iface, err error) {
	l.mu.Lock()
	defer l.mu.Unlock()
	l.ifaces = ifaces
	l.err = err
}

func (l *fakeLister) callCount() int {
	l.mu.Lock()
	defer l.mu.Unlock()
	return l.calls
}

// fakeClock replaces time.After. Each call parks a channel that the test
// releases with tick, so the test decides exactly when the next poll runs.
type fakeClock struct {
	parked    chan chan time.Time
	mu        sync.Mutex
	durations []time.Duration
}

func newFakeClock() *fakeClock {
	return &fakeClock{parked: make(chan chan time.Time, 100)}
}

func (c *fakeClock) After(d time.Duration) <-chan time.Time {
	c.mu.Lock()
	c.durations = append(c.durations, d)
	c.mu.Unlock()
	ch := make(chan time.Time, 1)
	c.parked <- ch
	return ch
}

func (c *fakeClock) intervals() []time.Duration {
	c.mu.Lock()
	defer c.mu.Unlock()
	return append([]time.Duration(nil), c.durations...)
}

// syncBuffer is a log sink that is safe to read while Run writes to it.
type syncBuffer struct {
	mu  sync.Mutex
	buf bytes.Buffer
}

func (b *syncBuffer) Write(p []byte) (int, error) {
	b.mu.Lock()
	defer b.mu.Unlock()
	return b.buf.Write(p)
}

func (b *syncBuffer) String() string {
	b.mu.Lock()
	defer b.mu.Unlock()
	return b.buf.String()
}

// runHarness runs Run in a goroutine against the fakes. The test drives it
// with park and poll.
type runHarness struct {
	t      *testing.T
	opts   Options
	reg    *fakeRegistrar
	lister *fakeLister
	clock  *fakeClock
	logs   *syncBuffer
	parked chan time.Time
	done   chan struct{}
	cancel context.CancelFunc
}

// newHarness builds the fakes and options without starting Run, so a test can
// configure the lister first.
func newHarness(t *testing.T, o Options) *runHarness {
	t.Helper()
	h := &runHarness{
		t:      t,
		reg:    &fakeRegistrar{},
		lister: &fakeLister{},
		clock:  newFakeClock(),
		logs:   &syncBuffer{},
		done:   make(chan struct{}),
	}
	if o.Logger == nil {
		o.Logger = slog.New(slog.NewTextHandler(h.logs, &slog.HandlerOptions{Level: slog.LevelDebug}))
	}
	o.Registrar = h.reg
	o.Lister = h.lister
	o.After = h.clock.After
	h.opts = o
	return h
}

// start launches Run. Call after the lister is configured.
func (h *runHarness) start() {
	h.t.Helper()
	ctx, cancel := context.WithCancel(context.Background())
	h.cancel = cancel
	h.t.Cleanup(cancel)
	go func() {
		defer close(h.done)
		Run(ctx, h.opts)
	}()
}

// park waits until Run has finished its current poll and is waiting on the
// fake clock.
func (h *runHarness) park() {
	h.t.Helper()
	select {
	case ch := <-h.clock.parked:
		h.parked = ch
	case <-h.done:
		h.t.Fatal("run returned while it should keep polling")
	case <-time.After(harnessWait):
		h.t.Fatal("run did not reach its wait in time")
	}
}

// poll lets Run do one more poll, then waits until it is parked again.
func (h *runHarness) poll() {
	h.t.Helper()
	h.parked <- time.Time{}
	h.park()
}

// stop cancels the context and waits for Run to return.
func (h *runHarness) stop() {
	h.t.Helper()
	h.cancel()
	h.waitDone()
}

func (h *runHarness) waitDone() {
	h.t.Helper()
	select {
	case <-h.done:
	case <-time.After(harnessWait):
		h.t.Fatal("run did not return in time")
	}
}

// testOptions returns enabled options with a valid agentId.
func testOptions() Options {
	return Options{
		Enabled: true,
		AgentID: testAgentID,
		Name:    testName,
		Port:    testPort,
	}
}

// lanIface builds an up, multicast, gateway-bearing interface with the given
// IPv4 addresses.
func lanIface(name string, index int, ips ...string) Iface {
	f := Iface{
		Name:       name,
		Up:         true,
		Multicast:  true,
		HasGateway: true,
		Raw: net.Interface{
			Name:  name,
			Index: index,
			Flags: net.FlagUp | net.FlagMulticast,
		},
	}
	for _, s := range ips {
		f.IPv4 = append(f.IPv4, netip.MustParseAddr(s))
	}
	return f
}

func equalStrings(a, b []string) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}
