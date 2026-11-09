//go:build !windows

package startup

import (
	"context"

	"remotto/agent/internal/control"
)

// unsupportedRunner refuses every command on platforms without Task Scheduler.
type unsupportedRunner struct{}

// systemRunner returns a Runner that always fails with control.ErrUnsupported.
func systemRunner() Runner { return unsupportedRunner{} }

func (unsupportedRunner) Run(_ context.Context, _ string, _ ...string) ([]byte, error) {
	return nil, control.ErrUnsupported
}
