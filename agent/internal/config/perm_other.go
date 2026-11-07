//go:build !windows

package config

import (
	"fmt"
	"io/fs"
	"os"
)

// NewPermChecker returns the permission checker for this platform. Outside
// Windows it sets the POSIX mode: 0700 for folders and 0600 for files.
func NewPermChecker() (PermChecker, error) {
	return modePerm{}, nil
}

// modePerm enforces owner-only POSIX modes.
type modePerm struct{}

// Ensure chmods path to 0700 (folder) or 0600 (file) when the mode differs.
func (modePerm) Ensure(path string) (bool, error) {
	info, err := os.Stat(path)
	if err != nil {
		return false, fmt.Errorf("stat permissions: %w", err)
	}
	want := fs.FileMode(0o600)
	if info.IsDir() {
		want = 0o700
	}
	if info.Mode().Perm() == want {
		return false, nil
	}
	if err := os.Chmod(path, want); err != nil {
		return false, fmt.Errorf("set permissions: %w", err)
	}
	return true, nil
}
