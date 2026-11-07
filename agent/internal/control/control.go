// Package control defines the domain ports for OS actions. Implementations
// live outside this package (oswin on Windows, stubs and fakes elsewhere) and
// must not leak OS details into it.
package control

import "context"

// MediaAction is a media key action sent to the laptop.
type MediaAction string

const (
	MediaPlayPause MediaAction = "play-pause"
	MediaNext      MediaAction = "next"
	MediaPrev      MediaAction = "prev"
)

// MediaController sends media key actions to the OS.
type MediaController interface {
	Send(ctx context.Context, action MediaAction) error
}

// Volume is the output volume state of the laptop.
type Volume struct {
	Level int  `json:"level"`
	Muted bool `json:"muted"`
}

// AudioController is a thin OS port. Clamping, stepping and unmute-on-change (BR-3, BR-15, BR-16) belong to the domain, not here.
type AudioController interface {
	Volume(ctx context.Context) (Volume, error)
	SetLevel(ctx context.Context, level int) error // level 0-100
	SetMuted(ctx context.Context, muted bool) error
}

// PowerAction is a power command for the laptop.
type PowerAction string

const (
	PowerSleep    PowerAction = "sleep"
	PowerRestart  PowerAction = "restart"
	PowerShutdown PowerAction = "shutdown"
)

// PowerController runs the OS command immediately. Delay and cancel live in the scheduler (M4), never here.
type PowerController interface {
	Execute(ctx context.Context, action PowerAction) error
}
