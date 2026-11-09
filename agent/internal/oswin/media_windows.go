package oswin

import (
	"context"
	"fmt"
	"unsafe"

	"golang.org/x/sys/windows"

	"remotto/agent/internal/control"
)

// Virtual-key codes for the media keys (winuser.h).
const (
	vkMediaNextTrack = 0xB0
	vkMediaPrevTrack = 0xB1
	vkMediaPlayPause = 0xB3
)

// Constants used by SendInput (winuser.h).
const (
	inputKeyboard        = 1
	keyeventfExtendedKey = 0x0001
	keyeventfKeyUp       = 0x0002
)

// keybdInput mirrors the Win32 KEYBDINPUT struct.
type keybdInput struct {
	vk    uint16
	scan  uint16
	flags uint32
	time  uint32
	extra uintptr
}

// input mirrors the Win32 INPUT struct. The union that follows type is sized
// by MOUSEINPUT, which is larger than KEYBDINPUT; the trailing padding covers
// it. The total is 40 bytes on 64-bit and 28 bytes on 32-bit, as the Windows
// headers require. The layout is checked by a test.
type input struct {
	typ uint32
	ki  keybdInput
	_   [8]byte
}

var _ control.MediaController = (*Media)(nil)

// sendFunc delivers inputs to the OS and returns how many were injected.
// The production implementation calls SendInput; tests substitute a fake.
type sendFunc func(inputs []input) (uint32, error)

// Media sends media key presses through SendInput.
type Media struct {
	send sendFunc
}

// NewMedia returns a Media bound to user32.dll SendInput. It does not press any
// key until Send is called.
func NewMedia() *Media {
	proc := windows.NewLazySystemDLL("user32.dll").NewProc("SendInput")
	return &Media{
		send: func(inputs []input) (uint32, error) {
			n, _, err := proc.Call(
				uintptr(len(inputs)),
				uintptr(unsafe.Pointer(&inputs[0])),
				unsafe.Sizeof(inputs[0]),
			)
			return uint32(n), err
		},
	}
}

// vkFor maps a media action to its virtual-key code.
func vkFor(a control.MediaAction) (uint16, bool) {
	switch a {
	case control.MediaPlayPause:
		return vkMediaPlayPause, true
	case control.MediaNext:
		return vkMediaNextTrack, true
	case control.MediaPrev:
		return vkMediaPrevTrack, true
	}
	return 0, false
}

// keyPressInputs returns a key-down event followed by a key-up event for vk.
// Both are extended keys, as media keys are.
func keyPressInputs(vk uint16) [2]input {
	return [2]input{
		{typ: inputKeyboard, ki: keybdInput{vk: vk, flags: keyeventfExtendedKey}},
		{typ: inputKeyboard, ki: keybdInput{vk: vk, flags: keyeventfExtendedKey | keyeventfKeyUp}},
	}
}

// Send presses and releases the media key for a in a single SendInput call, so
// a key-down can never be left without its key-up. Errors carry only the
// ErrMedia message; the OS detail stays reachable through Unwrap for logs.
func (m *Media) Send(ctx context.Context, a control.MediaAction) error {
	if err := ctx.Err(); err != nil {
		return control.Wrap(control.ErrMedia, err)
	}
	vk, ok := vkFor(a)
	if !ok {
		return control.Wrap(control.ErrMedia, fmt.Errorf("unknown media action %q", a))
	}
	inputs := keyPressInputs(vk)
	n, err := m.send(inputs[:])
	if n != uint32(len(inputs)) {
		return control.Wrap(control.ErrMedia, fmt.Errorf("SendInput injected %d of %d events: %w", n, len(inputs), err))
	}
	return nil
}
