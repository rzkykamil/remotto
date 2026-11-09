//go:build windows

package startup

import (
	"context"
	"os"
	"os/exec"
	"path/filepath"
)

// execRunner runs commands with exec.CommandContext. Arguments are passed
// directly, never through a shell.
type execRunner struct{}

// systemRunner returns the Runner that runs real Windows commands.
func systemRunner() Runner { return execRunner{} }

// Run runs name with args and returns its combined stdout and stderr. The
// schtasks name is resolved under %SystemRoot%\System32, so a binary placed
// earlier on PATH cannot replace it.
func (execRunner) Run(ctx context.Context, name string, args ...string) ([]byte, error) {
	if name == schtasksName {
		if root := os.Getenv("SystemRoot"); root != "" {
			name = filepath.Join(root, "System32", "schtasks.exe")
		}
	}
	return exec.CommandContext(ctx, name, args...).CombinedOutput()
}
