package control

import (
	"context"
	"errors"
	"sync"
)

// ErrInvalidAction is returned when a media action is not one of the known actions.
var ErrInvalidAction = errors.New("unknown media action")

// Valid reports whether a is one of the supported media actions.
func (a MediaAction) Valid() bool {
	switch a {
	case MediaPlayPause, MediaNext, MediaPrev:
		return true
	}
	return false
}

// MediaService is the domain entry point for media actions. It validates the
// action, serializes calls to the OS, and turns OS errors into ErrMedia.
type MediaService struct {
	ctrl MediaController
	mu   sync.Mutex
}

// NewMediaService returns a MediaService that sends actions through c. A nil c
// makes every call fail with ErrMedia (fail-closed).
func NewMediaService(c MediaController) *MediaService {
	return &MediaService{ctrl: c}
}

// Do validates a and sends it to the OS controller. Errors match ErrMedia or
// ErrInvalidAction; the underlying OS cause stays reachable through Unwrap.
func (s *MediaService) Do(ctx context.Context, a MediaAction) error {
	if !a.Valid() {
		return ErrInvalidAction
	}
	if s.ctrl == nil {
		return Wrap(ErrMedia, ErrUnsupported)
	}

	s.mu.Lock()
	defer s.mu.Unlock()

	err := s.ctrl.Send(ctx, a)
	if err == nil {
		return nil
	}
	if errors.Is(err, ErrMedia) {
		return err
	}
	return Wrap(ErrMedia, err)
}
