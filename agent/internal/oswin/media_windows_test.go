package oswin

import (
	"context"
	"errors"
	"strings"
	"testing"
	"unsafe"

	"remotto/agent/internal/control"
)

// These tests never call NewMedia or the real SendInput. They inject a fake
// sendFunc, so no key event reaches the OS.

func TestVKFor(t *testing.T) {
	tests := []struct {
		name   string
		action control.MediaAction
		want   uint16
		wantOK bool
	}{
		{name: "play-pause", action: control.MediaPlayPause, want: 0xB3, wantOK: true},
		{name: "next", action: control.MediaNext, want: 0xB0, wantOK: true},
		{name: "prev", action: control.MediaPrev, want: 0xB1, wantOK: true},
		{name: "unknown", action: control.MediaAction("stop"), want: 0, wantOK: false},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, ok := vkFor(tt.action)
			if ok != tt.wantOK || got != tt.want {
				t.Fatalf("vkFor(%q) = (%#x, %v), want (%#x, %v)", tt.action, got, ok, tt.want, tt.wantOK)
			}
		})
	}
}

func TestKeyPressInputs(t *testing.T) {
	got := keyPressInputs(0xB3)

	want := [2]input{
		{typ: inputKeyboard, ki: keybdInput{vk: 0xB3, flags: keyeventfExtendedKey}},
		{typ: inputKeyboard, ki: keybdInput{vk: 0xB3, flags: keyeventfExtendedKey | keyeventfKeyUp}},
	}
	if got != want {
		t.Fatalf("keyPressInputs(0xB3) = %+v, want %+v", got, want)
	}
	if got[0].ki.flags&keyeventfKeyUp != 0 {
		t.Errorf("first event must be key down, flags = %#x", got[0].ki.flags)
	}
	if got[1].ki.flags&keyeventfKeyUp == 0 {
		t.Errorf("second event must be key up, flags = %#x", got[1].ki.flags)
	}
}

func TestInputStructSize(t *testing.T) {
	want := uintptr(28)
	if unsafe.Sizeof(uintptr(0)) == 8 {
		want = 40
	}
	if got := unsafe.Sizeof(input{}); got != want {
		t.Fatalf("unsafe.Sizeof(input{}) = %d, want %d", got, want)
	}
}

func TestMediaSend(t *testing.T) {
	tests := []struct {
		name       string
		ctx        func() context.Context
		action     control.MediaAction
		sendN      uint32
		sendErr    error
		wantErr    bool
		wantCalled bool
		wantSecret bool
	}{
		{
			name:       "two events injected",
			ctx:        context.Background,
			action:     control.MediaPlayPause,
			sendN:      2,
			wantCalled: true,
		},
		{
			name:       "zero events injected returns media error without OS detail",
			ctx:        context.Background,
			action:     control.MediaNext,
			sendN:      0,
			sendErr:    errors.New("secret os detail"),
			wantErr:    true,
			wantCalled: true,
		},
		{
			name:       "one event injected is a failure",
			ctx:        context.Background,
			action:     control.MediaPrev,
			sendN:      1,
			wantErr:    true,
			wantCalled: true,
		},
		{
			name:       "unknown action is rejected before SendInput",
			ctx:        context.Background,
			action:     control.MediaAction("stop"),
			wantErr:    true,
			wantCalled: false,
		},
		{
			name: "cancelled context is rejected before SendInput",
			ctx: func() context.Context {
				ctx, cancel := context.WithCancel(context.Background())
				cancel()
				return ctx
			},
			action:     control.MediaPlayPause,
			wantErr:    true,
			wantCalled: false,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			called := false
			m := &Media{send: func(inputs []input) (uint32, error) {
				called = true
				if len(inputs) != 2 {
					t.Errorf("len(inputs) = %d, want 2", len(inputs))
				}
				return tt.sendN, tt.sendErr
			}}

			err := m.Send(tt.ctx(), tt.action)

			if called != tt.wantCalled {
				t.Fatalf("send called = %v, want %v", called, tt.wantCalled)
			}
			if !tt.wantErr {
				if err != nil {
					t.Fatalf("Send() error = %v, want nil", err)
				}
				return
			}
			if !errors.Is(err, control.ErrMedia) {
				t.Fatalf("errors.Is(err, ErrMedia) = false, err = %v", err)
			}
			if strings.Contains(err.Error(), "secret") {
				t.Fatalf("err.Error() = %q leaks OS detail", err.Error())
			}
			if msg := err.Error(); msg != control.ErrMedia.Error() {
				t.Fatalf("err.Error() = %q, want %q", msg, control.ErrMedia.Error())
			}
		})
	}
}

func TestMediaSendKeepsCauseForLogs(t *testing.T) {
	cause := errors.New("secret os detail")
	m := &Media{send: func([]input) (uint32, error) { return 0, cause }}

	err := m.Send(context.Background(), control.MediaNext)

	if !errors.Is(err, cause) {
		t.Fatalf("errors.Is(err, cause) = false, want true; err = %v", err)
	}
}
