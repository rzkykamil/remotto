package main

import (
	"context"

	"remotto/agent/internal/control"
)

// unsupported is a placeholder implementation of the OS ports. Every method
// fails with control.ErrUnsupported, so the agent can start and answer on
// platforms without an OS implementation.
type unsupported struct{}

var (
	_ control.MediaController = unsupported{}
	_ control.AudioController = unsupported{}
	_ control.PowerController = unsupported{}
)

func (unsupported) Send(_ context.Context, _ control.MediaAction) error {
	return control.ErrUnsupported
}

func (unsupported) Volume(_ context.Context) (control.Volume, error) {
	return control.Volume{}, control.ErrUnsupported
}

func (unsupported) SetLevel(_ context.Context, _ int) error {
	return control.ErrUnsupported
}

func (unsupported) SetMuted(_ context.Context, _ bool) error {
	return control.ErrUnsupported
}

func (unsupported) Execute(_ context.Context, _ control.PowerAction) error {
	return control.ErrUnsupported
}

// controllers groups the OS ports used by the handlers.
type controllers struct {
	Media control.MediaController
	Audio control.AudioController
	Power control.PowerController
}
