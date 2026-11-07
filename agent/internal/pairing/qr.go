package pairing

import (
	"errors"
	"fmt"
	"io"

	"github.com/mdp/qrterminal/v3"
)

// maxQRPayloadBytes is the largest payload the app accepts (data-design §5).
const maxQRPayloadBytes = 256

// ErrQRPayload means the payload cannot be rendered as a QR code.
var ErrQRPayload = errors.New("invalid QR payload")

// errWriter remembers the first write error. qrterminal ignores write errors,
// so this keeps a broken terminal from looking like success.
type errWriter struct {
	w   io.Writer
	err error
}

func (e *errWriter) Write(p []byte) (int, error) {
	if e.err != nil {
		return 0, e.err
	}
	n, err := e.w.Write(p)
	if err != nil {
		e.err = err
	}
	return n, err
}

// RenderQR writes payload to w as a QR code made of half-block characters,
// so it fits a terminal. Medium error correction is used. The payload must
// be non-empty and at most 256 bytes.
func RenderQR(w io.Writer, payload string) error {
	if w == nil {
		return fmt.Errorf("%w: nil writer", ErrQRPayload)
	}
	if payload == "" || len(payload) > maxQRPayloadBytes {
		return fmt.Errorf("%w: length %d bytes, want 1-%d", ErrQRPayload, len(payload), maxQRPayloadBytes)
	}
	ew := &errWriter{w: w}
	qrterminal.GenerateHalfBlock(payload, qrterminal.M, ew)
	if ew.err != nil {
		return fmt.Errorf("write QR: %w", ew.err)
	}
	return nil
}
