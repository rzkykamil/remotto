//go:build !windows

package config

import (
	"os"
	"path/filepath"
	"testing"
)

func TestModePermEnsureSetsOwnerOnlyModes(t *testing.T) {
	tests := []struct {
		name     string
		isDir    bool
		initial  os.FileMode
		wantMode os.FileMode
	}{
		{name: "folder loose", isDir: true, initial: 0o755, wantMode: 0o700},
		{name: "file loose", initial: 0o644, wantMode: 0o600},
		{name: "file group read", initial: 0o640, wantMode: 0o600},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			path := filepath.Join(t.TempDir(), "target")
			if tt.isDir {
				if err := os.Mkdir(path, tt.initial); err != nil {
					t.Fatalf("mkdir: %v", err)
				}
			} else {
				writeFile(t, path, "{}")
				if err := os.Chmod(path, tt.initial); err != nil {
					t.Fatalf("chmod: %v", err)
				}
			}
			perm := modePerm{}

			fixed, err := perm.Ensure(path)
			if err != nil {
				t.Fatalf("Ensure() error: %v", err)
			}
			if !fixed {
				t.Fatal("Ensure() fixed = false, want true")
			}
			info, err := os.Stat(path)
			if err != nil {
				t.Fatalf("stat: %v", err)
			}
			if got := info.Mode().Perm(); got != tt.wantMode {
				t.Fatalf("mode = %o, want %o", got, tt.wantMode)
			}
			fixed, err = perm.Ensure(path)
			if err != nil || fixed {
				t.Fatalf("second Ensure() = %v, %v; want false, nil", fixed, err)
			}
		})
	}
}

func TestModePermEnsureMissingPathFails(t *testing.T) {
	_, err := modePerm{}.Ensure(filepath.Join(t.TempDir(), "missing"))
	if err == nil {
		t.Fatal("Ensure() error = nil, want error for missing path")
	}
}
