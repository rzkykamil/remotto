package oswin

import (
	"context"
	"errors"
	"strings"
	"sync"
	"testing"
	"time"

	"golang.org/x/sys/windows"

	"remotto/agent/internal/control"
)

// These tests never call NewAudio or any COM function. They drive the worker
// with fakeDevice, so no volume is read or changed on the machine.

// fakeDevice stands in for the default render endpoint. Its hooks are one-shot.
type fakeDevice struct {
	mu        sync.Mutex
	scalar    float32
	muted     bool
	opens     int
	closes    int
	threads   []uint32  // OS thread of every factory call and backend operation
	levelSets []float32 // scalars passed to writeLevel
	muteSets  []bool    // values passed to writeMuted

	openErr   error         // returned by the next factory call
	failNext  error         // returned by the next backend operation
	panicNext bool          // the next backend operation panics
	block     chan struct{} // the next read waits until this is closed
}

func (d *fakeDevice) factory() (audioBackend, error) {
	d.mu.Lock()
	defer d.mu.Unlock()
	d.opens++
	d.threads = append(d.threads, windows.GetCurrentThreadId())
	if err := d.openErr; err != nil {
		d.openErr = nil
		return nil, err
	}
	return &fakeBackend{d: d}, nil
}

// fakeBackend is one open handle to fakeDevice.
type fakeBackend struct{ d *fakeDevice }

// begin records the calling thread and consumes the one-shot failure hooks.
// It returns the error to report, or panics when a panic was requested.
func (b *fakeBackend) begin() error {
	d := b.d
	d.mu.Lock()
	defer d.mu.Unlock()
	d.threads = append(d.threads, windows.GetCurrentThreadId())
	if d.panicNext {
		d.panicNext = false
		panic("secret device detail")
	}
	err := d.failNext
	d.failNext = nil
	return err
}

func (b *fakeBackend) read() (float32, bool, error) {
	b.d.mu.Lock()
	block := b.d.block
	b.d.block = nil
	b.d.mu.Unlock()
	if block != nil {
		<-block
	}
	if err := b.begin(); err != nil {
		return 0, false, err
	}
	b.d.mu.Lock()
	defer b.d.mu.Unlock()
	return b.d.scalar, b.d.muted, nil
}

func (b *fakeBackend) writeLevel(scalar float32) error {
	if err := b.begin(); err != nil {
		return err
	}
	b.d.mu.Lock()
	defer b.d.mu.Unlock()
	b.d.scalar = scalar
	b.d.levelSets = append(b.d.levelSets, scalar)
	return nil
}

func (b *fakeBackend) writeMuted(muted bool) error {
	if err := b.begin(); err != nil {
		return err
	}
	b.d.mu.Lock()
	defer b.d.mu.Unlock()
	b.d.muted = muted
	b.d.muteSets = append(b.d.muteSets, muted)
	return nil
}

func (b *fakeBackend) close() {
	b.d.mu.Lock()
	defer b.d.mu.Unlock()
	b.d.closes++
}

// snapshot reads the counters under the lock.
func (d *fakeDevice) snapshot() (opens, closes int) {
	d.mu.Lock()
	defer d.mu.Unlock()
	return d.opens, d.closes
}

func newTestAudio(t *testing.T, d *fakeDevice) *Audio {
	t.Helper()
	a := newAudioWith(d.factory)
	t.Cleanup(a.Close)
	return a
}

func TestScalarToLevel(t *testing.T) {
	tests := []struct {
		name   string
		scalar float32
		want   int
	}{
		{name: "zero", scalar: 0.0, want: 0},
		{name: "thirty-five", scalar: 0.35, want: 35},
		{name: "rounds down near 99", scalar: 0.994, want: 99},
		{name: "full", scalar: 1.0, want: 100},
		{name: "negative clamps to zero", scalar: -0.2, want: 0},
		{name: "above one clamps to 100", scalar: 1.3, want: 100},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := scalarToLevel(tt.scalar); got != tt.want {
				t.Fatalf("scalarToLevel(%v) = %d, want %d", tt.scalar, got, tt.want)
			}
		})
	}
}

func TestLevelToScalar(t *testing.T) {
	tests := []struct {
		level int
		want  float32
	}{
		{level: 0, want: 0},
		{level: 35, want: 0.35},
		{level: 100, want: 1},
		{level: -5, want: 0},
		{level: 150, want: 1},
	}
	for _, tt := range tests {
		if got := levelToScalar(tt.level); got != tt.want {
			t.Errorf("levelToScalar(%d) = %v, want %v", tt.level, got, tt.want)
		}
	}
}

func TestVolumeReadsDevice(t *testing.T) {
	d := &fakeDevice{}
	a := newTestAudio(t, d)

	tests := []struct {
		name   string
		scalar float32
		muted  bool
		want   control.Volume
	}{
		{name: "0.0", scalar: 0.0, want: control.Volume{Level: 0}},
		{name: "0.35", scalar: 0.35, want: control.Volume{Level: 35}},
		{name: "0.994", scalar: 0.994, want: control.Volume{Level: 99}},
		{name: "1.0", scalar: 1.0, want: control.Volume{Level: 100}},
		{name: "muted keeps level", scalar: 0.5, muted: true, want: control.Volume{Level: 50, Muted: true}},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			d.mu.Lock()
			d.scalar, d.muted = tt.scalar, tt.muted
			d.mu.Unlock()
			got, err := a.Volume(context.Background())
			if err != nil {
				t.Fatalf("Volume() error = %v", err)
			}
			if got != tt.want {
				t.Fatalf("Volume() = %+v, want %+v", got, tt.want)
			}
		})
	}
}

func TestSetLevelWritesScalar(t *testing.T) {
	d := &fakeDevice{}
	a := newTestAudio(t, d)

	if err := a.SetLevel(context.Background(), 35); err != nil {
		t.Fatalf("SetLevel(35) error = %v", err)
	}
	if len(d.levelSets) != 1 || d.levelSets[0] != float32(0.35) {
		t.Fatalf("writeLevel calls = %v, want [0.35]", d.levelSets)
	}
	if err := a.SetLevel(context.Background(), 0); err != nil {
		t.Fatalf("SetLevel(0) error = %v", err)
	}
	if err := a.SetLevel(context.Background(), 100); err != nil {
		t.Fatalf("SetLevel(100) error = %v", err)
	}
	want := []float32{0.35, 0, 1}
	if len(d.levelSets) != len(want) {
		t.Fatalf("writeLevel calls = %v, want %v", d.levelSets, want)
	}
	for i := range want {
		if d.levelSets[i] != want[i] {
			t.Fatalf("writeLevel calls = %v, want %v", d.levelSets, want)
		}
	}
}

func TestSetMutedWritesMute(t *testing.T) {
	d := &fakeDevice{scalar: 0.35}
	a := newTestAudio(t, d)

	if err := a.SetMuted(context.Background(), true); err != nil {
		t.Fatalf("SetMuted(true) error = %v", err)
	}
	got, err := a.Volume(context.Background())
	if err != nil {
		t.Fatalf("Volume() error = %v", err)
	}
	if got != (control.Volume{Level: 35, Muted: true}) {
		t.Fatalf("Volume() after SetMuted(true) = %+v", got)
	}
	if len(d.muteSets) != 1 || !d.muteSets[0] {
		t.Fatalf("writeMuted calls = %v, want [true]", d.muteSets)
	}
	if len(d.levelSets) != 0 {
		t.Fatalf("SetMuted must not touch the level, writeLevel calls = %v", d.levelSets)
	}
}

func TestAllOperationsRunOnOneThread(t *testing.T) {
	d := &fakeDevice{}
	a := newTestAudio(t, d)
	ctx := context.Background()

	_, _ = a.Volume(ctx)
	_ = a.SetLevel(ctx, 40)
	_ = a.SetMuted(ctx, true)
	_, _ = a.Volume(ctx)

	d.mu.Lock()
	defer d.mu.Unlock()
	if len(d.threads) == 0 {
		t.Fatal("no operation recorded")
	}
	first := d.threads[0]
	for i, id := range d.threads {
		if id != first {
			t.Fatalf("operation %d ran on thread %d, first ran on %d", i, id, first)
		}
	}
}

func TestBackendFailureReopensNextRequest(t *testing.T) {
	d := &fakeDevice{scalar: 0.2, failNext: errors.New("com: E_FAIL secret detail")}
	a := newTestAudio(t, d)
	ctx := context.Background()

	_, err := a.Volume(ctx)
	if !errors.Is(err, control.ErrAudio) {
		t.Fatalf("Volume() error = %v, want ErrAudio", err)
	}
	if strings.Contains(err.Error(), "secret") {
		t.Fatalf("error message leaks device detail: %q", err.Error())
	}
	if opens, closes := d.snapshot(); opens != 1 || closes != 1 {
		t.Fatalf("after failure opens=%d closes=%d, want 1 and 1", opens, closes)
	}

	got, err := a.Volume(ctx)
	if err != nil {
		t.Fatalf("Volume() after failure error = %v", err)
	}
	if got.Level != 20 {
		t.Fatalf("Volume() after reopen = %+v, want level 20", got)
	}
	if opens, _ := d.snapshot(); opens != 2 {
		t.Fatalf("opens = %d, want 2", opens)
	}
}

func TestFactoryFailureThenRecovers(t *testing.T) {
	d := &fakeDevice{openErr: errors.New("no default endpoint")}
	a := newTestAudio(t, d)
	ctx := context.Background()

	if err := a.SetLevel(ctx, 10); !errors.Is(err, control.ErrAudio) {
		t.Fatalf("SetLevel() error = %v, want ErrAudio", err)
	}
	if err := a.SetLevel(ctx, 10); err != nil {
		t.Fatalf("SetLevel() after factory recovered error = %v", err)
	}
}

func TestPanicIsRecoveredAndWorkerSurvives(t *testing.T) {
	d := &fakeDevice{panicNext: true}
	a := newTestAudio(t, d)
	ctx := context.Background()

	err := a.SetLevel(ctx, 10)
	if !errors.Is(err, control.ErrAudio) {
		t.Fatalf("SetLevel() after panic error = %v, want ErrAudio", err)
	}
	if strings.Contains(err.Error(), "secret") {
		t.Fatalf("error message leaks panic value: %q", err.Error())
	}
	if err := a.SetLevel(ctx, 10); err != nil {
		t.Fatalf("SetLevel() after panic error = %v", err)
	}
	if opens, closes := d.snapshot(); opens != 2 || closes != 1 {
		t.Fatalf("opens=%d closes=%d, want 2 and 1", opens, closes)
	}
}

func TestTimeoutDoesNotBlockWorker(t *testing.T) {
	gate := make(chan struct{})
	d := &fakeDevice{scalar: 0.5, block: gate}
	a := newTestAudio(t, d)
	a.timeout = 20 * time.Millisecond

	_, err := a.Volume(context.Background())
	if !errors.Is(err, control.ErrAudio) {
		t.Fatalf("Volume() error = %v, want ErrAudio", err)
	}
	if !errors.Is(err, context.DeadlineExceeded) {
		t.Fatalf("Volume() cause = %v, want DeadlineExceeded", err)
	}

	// The device call unblocks later. The worker must still serve requests.
	close(gate)
	a.timeout = time.Second
	got, err := a.Volume(context.Background())
	if err != nil {
		t.Fatalf("Volume() after timeout error = %v", err)
	}
	if got.Level != 50 {
		t.Fatalf("Volume() after timeout = %+v, want level 50", got)
	}
}

func TestCanceledContext(t *testing.T) {
	t.Run("already canceled does not touch device", func(t *testing.T) {
		d := &fakeDevice{}
		a := newTestAudio(t, d)
		ctx, cancel := context.WithCancel(context.Background())
		cancel()

		err := a.SetLevel(ctx, 10)
		if !errors.Is(err, control.ErrAudio) || !errors.Is(err, context.Canceled) {
			t.Fatalf("SetLevel() error = %v, want ErrAudio and Canceled", err)
		}
		if opens, _ := d.snapshot(); opens != 0 {
			t.Fatalf("factory called %d times for a canceled request", opens)
		}
		if len(d.levelSets) != 0 {
			t.Fatalf("device written after cancel: %v", d.levelSets)
		}
	})

	t.Run("canceled while waiting for a stuck device", func(t *testing.T) {
		gate := make(chan struct{})
		d := &fakeDevice{block: gate}
		a := newTestAudio(t, d)
		ctx, cancel := context.WithCancel(context.Background())
		go func() {
			time.Sleep(10 * time.Millisecond)
			cancel()
		}()

		_, err := a.Volume(ctx)
		if !errors.Is(err, control.ErrAudio) || !errors.Is(err, context.Canceled) {
			t.Fatalf("Volume() error = %v, want ErrAudio and Canceled", err)
		}
		close(gate)
	})
}

func TestCloseStopsWorker(t *testing.T) {
	d := &fakeDevice{}
	a := newAudioWith(d.factory)
	ctx := context.Background()

	if _, err := a.Volume(ctx); err != nil {
		t.Fatalf("Volume() before Close error = %v", err)
	}
	a.Close()
	if _, closes := d.snapshot(); closes != 1 {
		t.Fatalf("closes = %d after Close, want 1", closes)
	}
	if _, err := a.Volume(ctx); !errors.Is(err, control.ErrAudio) {
		t.Fatalf("Volume() after Close error = %v, want ErrAudio", err)
	}
	a.Close() // a second Close must not panic or block
}
