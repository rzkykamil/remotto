package main

import (
	"context"
	"errors"
	"testing"

	"remotto/agent/internal/control"
)

// TestUnsupportedStubs checks that every stub method returns ErrUnsupported.
func TestUnsupportedStubs(t *testing.T) {
	ctx := context.Background()
	tests := []struct {
		name string
		call func() error
	}{
		{"media send", func() error { return unsupported{}.Send(ctx, control.MediaPlayPause) }},
		{"audio volume", func() error { _, err := unsupported{}.Volume(ctx); return err }},
		{"audio set level", func() error { return unsupported{}.SetLevel(ctx, 50) }},
		{"audio set muted", func() error { return unsupported{}.SetMuted(ctx, true) }},
		{"power execute", func() error { return unsupported{}.Execute(ctx, control.PowerSleep) }},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if err := tt.call(); !errors.Is(err, control.ErrUnsupported) {
				t.Fatalf("err = %v, want ErrUnsupported", err)
			}
		})
	}
}

// TestNewControllersNonNil checks that newControllers fills all three ports.
func TestNewControllersNonNil(t *testing.T) {
	c := newControllers()
	if c.Media == nil {
		t.Error("Media is nil")
	}
	if c.Audio == nil {
		t.Error("Audio is nil")
	}
	if c.Power == nil {
		t.Error("Power is nil")
	}
}
