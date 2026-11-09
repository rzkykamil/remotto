package oswin

import (
	"context"
	"errors"
	"fmt"
	"io"
	"math"
	"runtime"
	"sync"
	"time"

	"github.com/go-ole/go-ole"
	"github.com/moutend/go-wca/pkg/wca"

	"remotto/agent/internal/control"
)

// audioOpTimeout bounds one audio operation, from submit to reply. A stuck
// device must not hold an HTTP handler; the COM call itself cannot be cancelled.
const audioOpTimeout = time.Second

// audioBackend is the device surface used by the worker. comBackend is the
// Core Audio implementation; tests inject a fake so no COM call reaches the OS.
type audioBackend interface {
	read() (scalar float32, muted bool, err error)
	writeLevel(scalar float32) error
	writeMuted(muted bool) error
	close()
}

// audioResult is the outcome of one operation.
type audioResult struct {
	scalar float32
	muted  bool
	err    error
}

// audioRequest is one operation for the worker. res is buffered, so the worker
// never blocks on a caller that has already given up.
type audioRequest struct {
	ctx context.Context
	fn  func(b audioBackend) audioResult
	res chan audioResult
}

var (
	_ control.AudioController = (*Audio)(nil)
	_ io.Closer               = (*Audio)(nil)
)

// Audio controls the master volume of the default render endpoint. Every COM
// call runs on one goroutine locked to one OS thread, which COM requires.
type Audio struct {
	factory func() (audioBackend, error)
	timeout time.Duration
	reqs    chan audioRequest
	quit    chan struct{}
	done    chan struct{}
	once    sync.Once
}

// NewAudio returns an Audio backed by Core Audio and starts its COM worker. It
// changes no volume until a method is called. Call Close to stop the worker.
func NewAudio() *Audio {
	return newAudioWith(newCOMBackend)
}

// newAudioWith starts a worker that opens its backends with factory. The
// factory runs on the worker thread.
func newAudioWith(factory func() (audioBackend, error)) *Audio {
	a := &Audio{
		factory: factory,
		timeout: audioOpTimeout,
		reqs:    make(chan audioRequest),
		quit:    make(chan struct{}),
		done:    make(chan struct{}),
	}
	go a.run()
	return a
}

// run is the worker loop. It owns the backend and is the only goroutine that
// touches COM.
func (a *Audio) run() {
	runtime.LockOSThread()
	defer runtime.UnlockOSThread()
	defer close(a.done)

	var b audioBackend
	for {
		select {
		case <-a.quit:
			if b != nil {
				closeBackend(b)
			}
			return
		case req := <-a.reqs:
			b = a.serve(b, req)
		}
	}
}

// serve runs one request and returns the backend to keep. A failed or
// panicking operation closes the backend, so the next request opens a new one.
func (a *Audio) serve(b audioBackend, req audioRequest) audioBackend {
	if err := req.ctx.Err(); err != nil {
		// The caller gave up before the worker got to it; do not touch the device.
		req.res <- audioResult{err: err}
		return b
	}
	if b == nil {
		nb, err := a.factory()
		if err != nil {
			req.res <- audioResult{err: fmt.Errorf("open audio backend: %w", err)}
			return nil
		}
		b = nb
	}
	res, ok := runSafely(b, req.fn)
	if !ok || res.err != nil {
		closeBackend(b)
		b = nil
	}
	req.res <- res
	return b
}

// runSafely calls fn and turns a panic into an error, so the worker survives.
func runSafely(b audioBackend, fn func(audioBackend) audioResult) (res audioResult, ok bool) {
	defer func() {
		if r := recover(); r != nil {
			res = audioResult{err: fmt.Errorf("panic in audio operation: %v", r)}
			ok = false
		}
	}()
	return fn(b), true
}

// closeBackend closes b and ignores a panic, because the backend may be broken.
func closeBackend(b audioBackend) {
	defer func() { _ = recover() }()
	b.close()
}

// do submits fn to the worker and waits for the outcome, bounded by ctx and
// a.timeout. Every returned error matches control.ErrAudio.
func (a *Audio) do(ctx context.Context, fn func(b audioBackend) audioResult) (audioResult, error) {
	if err := ctx.Err(); err != nil {
		return audioResult{}, control.Wrap(control.ErrAudio, err)
	}
	ctx, cancel := context.WithTimeout(ctx, a.timeout)
	defer cancel()

	req := audioRequest{ctx: ctx, fn: fn, res: make(chan audioResult, 1)}
	select {
	case a.reqs <- req:
	case <-a.quit:
		return audioResult{}, control.Wrap(control.ErrAudio, errors.New("audio worker closed"))
	case <-ctx.Done():
		return audioResult{}, control.Wrap(control.ErrAudio, ctx.Err())
	}
	select {
	case res := <-req.res:
		if res.err != nil {
			return audioResult{}, control.Wrap(control.ErrAudio, res.err)
		}
		return res, nil
	case <-ctx.Done():
		return audioResult{}, control.Wrap(control.ErrAudio, ctx.Err())
	}
}

// Volume reads the master level and mute state.
func (a *Audio) Volume(ctx context.Context) (control.Volume, error) {
	res, err := a.do(ctx, func(b audioBackend) audioResult {
		scalar, muted, err := b.read()
		return audioResult{scalar: scalar, muted: muted, err: err}
	})
	if err != nil {
		return control.Volume{}, err
	}
	return control.Volume{Level: scalarToLevel(res.scalar), Muted: res.muted}, nil
}

// SetLevel sets the master level. level is clamped to 0-100; the domain
// rejects out-of-range values before they reach this point.
func (a *Audio) SetLevel(ctx context.Context, level int) error {
	scalar := levelToScalar(level)
	_, err := a.do(ctx, func(b audioBackend) audioResult {
		return audioResult{err: b.writeLevel(scalar)}
	})
	return err
}

// SetMuted sets the mute state without changing the level.
func (a *Audio) SetMuted(ctx context.Context, muted bool) error {
	_, err := a.do(ctx, func(b audioBackend) audioResult {
		return audioResult{err: b.writeMuted(muted)}
	})
	return err
}

// Close stops the worker and closes its backend. Later calls return an error
// that matches control.ErrAudio. Close waits at most a.timeout for the worker;
// if the worker is still stuck in a COM call after that, Close returns an error
// that matches control.ErrAudio and the goroutine is left to finish on its own.
func (a *Audio) Close() error {
	a.once.Do(func() { close(a.quit) })
	select {
	case <-a.done:
		return nil
	case <-time.After(a.timeout):
		return control.Wrap(control.ErrAudio, errors.New("audio worker did not stop in time"))
	}
}

// scalarToLevel maps a Core Audio scalar (0.0-1.0) to a level (0-100), rounding
// to the nearest step. NaN maps to 0.
func scalarToLevel(scalar float32) int {
	f := math.Round(float64(scalar) * 100)
	switch {
	case !(f >= 0):
		return 0
	case f > 100:
		return 100
	}
	return int(f)
}

// levelToScalar maps a level (0-100) to a Core Audio scalar (0.0-1.0).
func levelToScalar(level int) float32 {
	if level < 0 {
		level = 0
	}
	if level > 100 {
		level = 100
	}
	return float32(level) / 100
}

// comBackend is the Core Audio implementation of audioBackend. It is valid only
// on the thread that created it. Each operation resolves the default render
// endpoint again, so the device that is current at that moment is used (for
// example after a headset is plugged in).
type comBackend struct{}

// newCOMBackend initializes COM on the calling thread. close undoes it.
func newCOMBackend() (audioBackend, error) {
	if err := ole.CoInitializeEx(0, ole.COINIT_APARTMENTTHREADED); err != nil {
		return nil, err
	}
	return &comBackend{}, nil
}

func (c *comBackend) close() {
	ole.CoUninitialize()
}

// endpoint returns the master volume interface of the default render endpoint.
// The caller must call release exactly once.
func (c *comBackend) endpoint() (*wca.IAudioEndpointVolume, func(), error) {
	var enum *wca.IMMDeviceEnumerator
	if err := wca.CoCreateInstance(wca.CLSID_MMDeviceEnumerator, 0, wca.CLSCTX_ALL, wca.IID_IMMDeviceEnumerator, &enum); err != nil {
		return nil, nil, fmt.Errorf("create device enumerator: %w", err)
	}
	var dev *wca.IMMDevice
	// go-wca names the second argument stateMask, but Windows defines it as
	// ERole, so the console role is passed here.
	if err := enum.GetDefaultAudioEndpoint(wca.ERender, wca.EConsole, &dev); err != nil {
		enum.Release()
		return nil, nil, fmt.Errorf("get default render endpoint: %w", err)
	}
	var vol *wca.IAudioEndpointVolume
	if err := dev.Activate(wca.IID_IAudioEndpointVolume, wca.CLSCTX_ALL, nil, &vol); err != nil {
		dev.Release()
		enum.Release()
		return nil, nil, fmt.Errorf("activate endpoint volume: %w", err)
	}
	release := func() {
		vol.Release()
		dev.Release()
		enum.Release()
	}
	return vol, release, nil
}

func (c *comBackend) read() (float32, bool, error) {
	vol, release, err := c.endpoint()
	if err != nil {
		return 0, false, err
	}
	defer release()

	var scalar float32
	if err := vol.GetMasterVolumeLevelScalar(&scalar); err != nil {
		return 0, false, fmt.Errorf("get master volume: %w", err)
	}
	var muted bool
	if err := vol.GetMute(&muted); err != nil {
		return 0, false, fmt.Errorf("get mute: %w", err)
	}
	return scalar, muted, nil
}

func (c *comBackend) writeLevel(scalar float32) error {
	vol, release, err := c.endpoint()
	if err != nil {
		return err
	}
	defer release()
	if err := vol.SetMasterVolumeLevelScalar(scalar, nil); err != nil {
		return fmt.Errorf("set master volume: %w", err)
	}
	return nil
}

func (c *comBackend) writeMuted(muted bool) error {
	vol, release, err := c.endpoint()
	if err != nil {
		return err
	}
	defer release()
	if err := vol.SetMute(muted, nil); err != nil {
		return fmt.Errorf("set mute: %w", err)
	}
	return nil
}
