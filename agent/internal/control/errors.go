package control

import "errors"

// Sentinel errors for the domain. Their messages are safe to return to clients.
var (
	ErrUnsupported = errors.New("operation not supported on this platform")
	ErrMedia       = errors.New("media control failed")
	ErrAudio       = errors.New("audio control failed")
	ErrPower       = errors.New("power control failed")
)

// wrapped pairs a safe sentinel with an internal cause. Error exposes only the
// sentinel message, so OS detail never reaches responses; the cause stays
// reachable through Unwrap for logging.
type wrapped struct {
	sentinel error
	cause    error
}

// Wrap returns an error that matches sentinel with errors.Is and unwraps to cause.
// Its Error method returns only the sentinel message.
func Wrap(sentinel, cause error) error {
	return &wrapped{sentinel: sentinel, cause: cause}
}

func (w *wrapped) Error() string { return w.sentinel.Error() }

func (w *wrapped) Is(target error) bool { return target == w.sentinel }

func (w *wrapped) Unwrap() error { return w.cause }
