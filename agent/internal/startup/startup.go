// Package startup manages the Task Scheduler task that starts the agent when
// the user logs on (FR-6.1). All schtasks calls go through Runner, so tests
// never touch the real Task Scheduler.
package startup

import (
	"bytes"
	"context"
	"errors"
	"log/slog"
	"os"
	"os/user"
	"strings"

	"remotto/agent/internal/control"
)

// TaskName is the full Task Scheduler path of the agent's logon task.
const TaskName = `Remotto\Agent`

const schtasksName = "schtasks"

// Sentinel errors. Their messages are safe to show to clients and the CLI.
// Raw schtasks output never appears in them; it is logged only.
var (
	ErrInstall   = errors.New("failed to install startup task")
	ErrUninstall = errors.New("failed to remove startup task")
	ErrNeedAdmin = errors.New("administrator rights required to manage startup task")
)

// Runner runs an external command without a shell and returns its combined
// output.
type Runner interface {
	Run(ctx context.Context, name string, args ...string) ([]byte, error)
}

// Manager installs and removes the logon task. Nil fields fall back to
// defaults: os.Executable, the current user, os.TempDir and the system Runner.
type Manager struct {
	Runner      Runner
	Executable  func() (string, error)
	CurrentUser func() (string, error)
	TempDir     string
}

// Install creates or replaces the logon task for the current user and
// executable (`/Create ... /F`). The task XML is written to a temporary file,
// which is removed before Install returns.
func (m *Manager) Install(ctx context.Context) error {
	exe, err := m.executable()
	if err != nil {
		return control.Wrap(ErrInstall, err)
	}
	userID, err := m.currentUser()
	if err != nil {
		return control.Wrap(ErrInstall, err)
	}
	doc, err := BuildTaskXML(exe, userID)
	if err != nil {
		return control.Wrap(ErrInstall, err)
	}

	// os.CreateTemp picks a random name and creates the file with mode 0600.
	f, err := os.CreateTemp(m.tempDir(), "remotto-task-*.xml")
	if err != nil {
		return control.Wrap(ErrInstall, err)
	}
	path := f.Name()
	defer func() { _ = os.Remove(path) }()

	if _, err := f.Write(doc); err != nil {
		_ = f.Close()
		return control.Wrap(ErrInstall, err)
	}
	if err := f.Close(); err != nil {
		return control.Wrap(ErrInstall, err)
	}

	out, err := m.runner().Run(ctx, schtasksName, "/Create", "/TN", TaskName, "/XML", path, "/F")
	if err != nil {
		slog.Warn("schtasks /Create failed", "output", strings.TrimSpace(string(out)), "err", err)
		if isAccessDenied(out) {
			return control.Wrap(ErrNeedAdmin, err)
		}
		return control.Wrap(ErrInstall, err)
	}
	return nil
}

// Uninstall deletes the logon task. A task that does not exist counts as
// success, so the call is idempotent.
func (m *Manager) Uninstall(ctx context.Context) error {
	out, err := m.runner().Run(ctx, schtasksName, "/Delete", "/TN", TaskName, "/F")
	if err == nil {
		return nil
	}
	if isNotFound(out) {
		return nil
	}
	slog.Warn("schtasks /Delete failed", "output", strings.TrimSpace(string(out)), "err", err)
	if isAccessDenied(out) {
		return control.Wrap(ErrNeedAdmin, err)
	}
	return control.Wrap(ErrUninstall, err)
}

func (m *Manager) runner() Runner {
	if m.Runner != nil {
		return m.Runner
	}
	return systemRunner()
}

func (m *Manager) executable() (string, error) {
	if m.Executable != nil {
		return m.Executable()
	}
	return os.Executable()
}

func (m *Manager) currentUser() (string, error) {
	if m.CurrentUser != nil {
		return m.CurrentUser()
	}
	u, err := user.Current()
	if err != nil {
		return "", err
	}
	return u.Username, nil
}

func (m *Manager) tempDir() string {
	if m.TempDir != "" {
		return m.TempDir
	}
	return os.TempDir()
}

// isAccessDenied reports whether schtasks output says the caller lacks rights.
// The English text is matched. schtasks prints its output in the OS display
// language, so on a non-English Windows this check may miss and the error is
// reported as a generic failure instead.
func isAccessDenied(out []byte) bool {
	return bytes.Contains(bytes.ToLower(out), []byte("access is denied"))
}

// isNotFound reports whether schtasks says the task does not exist.
func isNotFound(out []byte) bool {
	lower := bytes.ToLower(out)
	return bytes.Contains(lower, []byte("cannot find the file specified")) ||
		bytes.Contains(lower, []byte("does not exist in the system"))
}
