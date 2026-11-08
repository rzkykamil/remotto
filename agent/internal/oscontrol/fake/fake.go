// Package fake provides in-memory implementations of the control ports. They
// record calls and never touch the operating system, so tests can run safely
// on any machine.
package fake

import (
	"context"
	"sync"

	"remotto/agent/internal/control"
)

var (
	_ control.MediaController = (*Media)(nil)
	_ control.AudioController = (*Audio)(nil)
	_ control.PowerController = (*Power)(nil)
)

// Media records media actions. Every call is recorded, then SetErr decides the result.
type Media struct {
	mu    sync.Mutex
	err   error
	calls []control.MediaAction
}

// SetErr makes every later Send return err. Passing nil restores success.
func (m *Media) SetErr(err error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.err = err
}

// Send records action and returns the configured error.
func (m *Media) Send(_ context.Context, action control.MediaAction) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.calls = append(m.calls, action)
	return m.err
}

// Calls returns a copy of the recorded actions in call order.
func (m *Media) Calls() []control.MediaAction {
	m.mu.Lock()
	defer m.mu.Unlock()
	return append([]control.MediaAction(nil), m.calls...)
}

// Audio keeps a volume state in memory. It stores values as given: clamping
// and unmute-on-change belong to the domain, not to this fake.
type Audio struct {
	mu        sync.Mutex
	err       error
	muteErr   error
	volume    control.Volume
	levelCall []int
	muteCalls []bool
}

// NewAudio returns an Audio with the given initial state.
func NewAudio(level int, muted bool) *Audio {
	return &Audio{volume: control.Volume{Level: level, Muted: muted}}
}

// SetErr makes every method fail with err. Passing nil restores success.
func (a *Audio) SetErr(err error) {
	a.mu.Lock()
	defer a.mu.Unlock()
	a.err = err
}

// SetMuteErr makes every later SetMuted fail with err, while SetLevel and
// Volume keep working. Passing nil restores success.
func (a *Audio) SetMuteErr(err error) {
	a.mu.Lock()
	defer a.mu.Unlock()
	a.muteErr = err
}

// Volume returns the stored state, or the configured error.
func (a *Audio) Volume(_ context.Context) (control.Volume, error) {
	a.mu.Lock()
	defer a.mu.Unlock()
	if a.err != nil {
		return control.Volume{}, a.err
	}
	return a.volume, nil
}

// SetLevel records the attempt. On success it stores level as given.
func (a *Audio) SetLevel(_ context.Context, level int) error {
	a.mu.Lock()
	defer a.mu.Unlock()
	a.levelCall = append(a.levelCall, level)
	if a.err != nil {
		return a.err
	}
	a.volume.Level = level
	return nil
}

// SetMuted records the attempt, then fails in this order: muteErr, then err.
// If neither is set, it stores the mute flag.
func (a *Audio) SetMuted(_ context.Context, muted bool) error {
	a.mu.Lock()
	defer a.mu.Unlock()
	a.muteCalls = append(a.muteCalls, muted)
	if a.muteErr != nil {
		return a.muteErr
	}
	if a.err != nil {
		return a.err
	}
	a.volume.Muted = muted
	return nil
}

// SetLevelCalls returns a copy of every level passed to SetLevel, in call order.
func (a *Audio) SetLevelCalls() []int {
	a.mu.Lock()
	defer a.mu.Unlock()
	return append([]int(nil), a.levelCall...)
}

// SetMutedCalls returns a copy of every mute value passed to SetMuted, in call
// order. Failed attempts are included.
func (a *Audio) SetMutedCalls() []bool {
	a.mu.Lock()
	defer a.mu.Unlock()
	return append([]bool(nil), a.muteCalls...)
}

// Power records power actions and never runs an OS command.
type Power struct {
	mu    sync.Mutex
	err   error
	calls []control.PowerAction
}

// SetErr makes every later Execute return err. Passing nil restores success.
func (p *Power) SetErr(err error) {
	p.mu.Lock()
	defer p.mu.Unlock()
	p.err = err
}

// Execute records action and returns the configured error. It does not run anything.
func (p *Power) Execute(_ context.Context, action control.PowerAction) error {
	p.mu.Lock()
	defer p.mu.Unlock()
	p.calls = append(p.calls, action)
	return p.err
}

// Calls returns a copy of the recorded actions in call order.
func (p *Power) Calls() []control.PowerAction {
	p.mu.Lock()
	defer p.mu.Unlock()
	return append([]control.PowerAction(nil), p.calls...)
}
