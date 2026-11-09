package control

import (
	"errors"
	"strings"
	"testing"
)

func TestWrap(t *testing.T) {
	tests := []struct {
		name     string
		sentinel error
		cause    error
	}{
		{name: "audio", sentinel: ErrAudio, cause: errors.New("COM 0x8007")},
		{name: "media", sentinel: ErrMedia, cause: errors.New("SendInput 0x5")},
		{name: "power", sentinel: ErrPower, cause: errors.New("exit status 1")},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := Wrap(tt.sentinel, tt.cause)

			if !errors.Is(err, tt.sentinel) {
				t.Fatalf("errors.Is(err, sentinel) = false, want true")
			}
			if got := errors.Unwrap(err); got != tt.cause {
				t.Fatalf("errors.Unwrap(err) = %v, want %v", got, tt.cause)
			}
			if msg := err.Error(); msg != tt.sentinel.Error() {
				t.Fatalf("err.Error() = %q, want %q", msg, tt.sentinel.Error())
			}
			if strings.Contains(err.Error(), tt.cause.Error()) {
				t.Fatalf("err.Error() leaks cause: %q", err.Error())
			}
		})
	}
}
