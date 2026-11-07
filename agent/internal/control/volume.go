package control

import (
	"context"
	"errors"
	"sync"
)

// Volume limits and the step used by up and down (BR-3, BR-16).
const (
	VolumeStep = 5
	MinLevel   = 0
	MaxLevel   = 100
)

// ErrInvalidLevel is returned when a requested level is outside 0-100. Its
// message is safe to return to clients.
var ErrInvalidLevel = errors.New("level must be an integer between 0 and 100")

// VolumeService is the domain entry point for volume actions. It validates
// input, serializes read-modify-write sequences, unmutes on level changes and
// turns OS errors into ErrAudio.
type VolumeService struct {
	ctrl AudioController
	mu   sync.Mutex
}

// NewVolumeService returns a VolumeService that talks to c. A nil c makes every
// call fail with ErrAudio (fail-closed).
func NewVolumeService(c AudioController) *VolumeService {
	return &VolumeService{ctrl: c}
}

// Get returns the current output volume reported by the OS.
func (s *VolumeService) Get(ctx context.Context) (Volume, error) {
	if s.ctrl == nil {
		return Volume{}, Wrap(ErrAudio, ErrUnsupported)
	}
	if err := ctx.Err(); err != nil {
		return Volume{}, Wrap(ErrAudio, err)
	}

	s.mu.Lock()
	defer s.mu.Unlock()

	v, err := s.ctrl.Volume(ctx)
	if err != nil {
		return Volume{}, audioError(err)
	}
	return v, nil
}

// SetLevel sets the output level (BR-3) and unmutes (BR-15). Levels outside
// 0-100 are rejected with ErrInvalidLevel before the OS is touched; they are
// never clamped. The returned volume is read back from the OS.
func (s *VolumeService) SetLevel(ctx context.Context, level int) (Volume, error) {
	if level < MinLevel || level > MaxLevel {
		return Volume{}, ErrInvalidLevel
	}
	if s.ctrl == nil {
		return Volume{}, Wrap(ErrAudio, ErrUnsupported)
	}
	if err := ctx.Err(); err != nil {
		return Volume{}, Wrap(ErrAudio, err)
	}

	s.mu.Lock()
	defer s.mu.Unlock()

	return s.setLevelLocked(ctx, level)
}

// Up raises the level by VolumeStep, clamped at MaxLevel (BR-16).
func (s *VolumeService) Up(ctx context.Context) (Volume, error) {
	return s.step(ctx, VolumeStep)
}

// Down lowers the level by VolumeStep, clamped at MinLevel (BR-16).
func (s *VolumeService) Down(ctx context.Context) (Volume, error) {
	return s.step(ctx, -VolumeStep)
}

// SetMuted changes only the mute flag and leaves the level untouched.
func (s *VolumeService) SetMuted(ctx context.Context, muted bool) (Volume, error) {
	if s.ctrl == nil {
		return Volume{}, Wrap(ErrAudio, ErrUnsupported)
	}
	if err := ctx.Err(); err != nil {
		return Volume{}, Wrap(ErrAudio, err)
	}

	s.mu.Lock()
	defer s.mu.Unlock()

	if err := s.ctrl.SetMuted(ctx, muted); err != nil {
		return Volume{}, audioError(err)
	}
	return s.readLocked(ctx)
}

// step reads the current level, adds delta, clamps the result to 0-100 and
// writes it. A step at a limit still succeeds and still unmutes (BR-16).
func (s *VolumeService) step(ctx context.Context, delta int) (Volume, error) {
	if s.ctrl == nil {
		return Volume{}, Wrap(ErrAudio, ErrUnsupported)
	}
	if err := ctx.Err(); err != nil {
		return Volume{}, Wrap(ErrAudio, err)
	}

	s.mu.Lock()
	defer s.mu.Unlock()

	cur, err := s.ctrl.Volume(ctx)
	if err != nil {
		return Volume{}, audioError(err)
	}
	return s.setLevelLocked(ctx, clamp(cur.Level+delta, MinLevel, MaxLevel))
}

// setLevelLocked writes level, unmutes, and reads the result back. Callers must
// hold s.mu and have validated level.
func (s *VolumeService) setLevelLocked(ctx context.Context, level int) (Volume, error) {
	if err := s.ctrl.SetLevel(ctx, level); err != nil {
		return Volume{}, audioError(err)
	}
	if err := s.ctrl.SetMuted(ctx, false); err != nil {
		return Volume{}, audioError(err)
	}
	return s.readLocked(ctx)
}

// readLocked reads the volume back from the OS. Callers must hold s.mu.
func (s *VolumeService) readLocked(ctx context.Context) (Volume, error) {
	v, err := s.ctrl.Volume(ctx)
	if err != nil {
		return Volume{}, audioError(err)
	}
	return v, nil
}

// audioError maps an OS error to ErrAudio, keeping the cause for logging.
// An error that already matches ErrAudio is returned as-is.
func audioError(err error) error {
	if errors.Is(err, ErrAudio) {
		return err
	}
	return Wrap(ErrAudio, err)
}

func clamp(v, lo, hi int) int {
	if v < lo {
		return lo
	}
	if v > hi {
		return hi
	}
	return v
}
