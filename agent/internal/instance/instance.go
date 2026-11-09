// Package instance keeps a single agent process running per Windows session.
// It holds a named mutex for the lifetime of the process (docs/technical-spec.md,
// Startup). Other platforms have no such mutex and always succeed.
package instance

import "errors"

// MutexName is the session-local named mutex that marks a running agent.
const MutexName = `Local\RemottoAgent`

// ErrAlreadyRunning means another agent already holds the named mutex.
var ErrAlreadyRunning = errors.New("agent already running")

// Release gives up the instance lock. It is safe to call more than once.
type Release func()

// Acquire takes the named instance lock. It returns ErrAlreadyRunning when
// another process holds it. The caller must call the returned Release when
// the agent stops.
func Acquire(name string) (Release, error) {
	return acquire(name)
}
