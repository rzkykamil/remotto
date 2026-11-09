package logging

import (
	"bytes"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
)

// TestFR64_RotatesIntoBackupsAndDropsOldest checks BR-11/FR-6.4: with a tiny
// limit the active file and three backups exist, and the fourth never does.
func TestFR64_RotatesIntoBackupsAndDropsOldest(t *testing.T) {
	path := filepath.Join(t.TempDir(), "agent.log")

	logger, closer, err := New(Options{File: path, MaxBytes: 200, Backups: 3})
	if err != nil {
		t.Fatalf("New: %v", err)
	}
	for i := 0; i < 40; i++ {
		logger.Info("line", "n", i)
	}
	if err := closer.Close(); err != nil {
		t.Fatalf("Close: %v", err)
	}

	for _, p := range []string{path, path + ".1", path + ".2", path + ".3"} {
		if _, err := os.Stat(p); err != nil {
			t.Errorf("want %s to exist: %v", p, err)
		}
	}
	if _, err := os.Stat(path + ".4"); !os.IsNotExist(err) {
		t.Errorf("%s.4 must never exist, stat err = %v", path, err)
	}
}

// TestFR64_EachFileHoldsWholeJSONLines checks that rotation never splits a
// log line across two files.
func TestFR64_EachFileHoldsWholeJSONLines(t *testing.T) {
	path := filepath.Join(t.TempDir(), "agent.log")

	logger, closer, err := New(Options{File: path, MaxBytes: 200, Backups: 3})
	if err != nil {
		t.Fatalf("New: %v", err)
	}
	for i := 0; i < 40; i++ {
		logger.Info("line", "n", i)
	}
	if err := closer.Close(); err != nil {
		t.Fatalf("Close: %v", err)
	}

	for _, p := range []string{path, path + ".1", path + ".2", path + ".3"} {
		data, err := os.ReadFile(p)
		if err != nil {
			t.Fatalf("read %s: %v", p, err)
		}
		if len(data) == 0 || data[len(data)-1] != '\n' {
			t.Errorf("%s does not end with a newline", p)
		}
		if int64(len(data)) > 200 {
			t.Errorf("%s has %d bytes, want <= 200", p, len(data))
		}
		parseLines(t, data) // fails the test if any line is not valid JSON
	}
}

// TestFR64_ReopenContinuesExistingSize checks that reopening an existing file
// counts its current size instead of starting from zero.
func TestFR64_ReopenContinuesExistingSize(t *testing.T) {
	path := filepath.Join(t.TempDir(), "agent.log")
	if err := os.WriteFile(path, bytes.Repeat([]byte("x"), 150), 0o600); err != nil {
		t.Fatalf("seed: %v", err)
	}

	r, err := openRotating(path, 200, 3)
	if err != nil {
		t.Fatalf("openRotating: %v", err)
	}
	defer r.Close()

	if r.size != 150 {
		t.Fatalf("size = %d, want 150 (continue, not reset)", r.size)
	}
	// 150 + 60 > 200 must rotate before writing.
	if _, err := r.Write(bytes.Repeat([]byte("y"), 60)); err != nil {
		t.Fatalf("Write: %v", err)
	}
	if _, err := os.Stat(path + ".1"); err != nil {
		t.Fatalf("want rotation on reopened file: %v", err)
	}
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read active: %v", err)
	}
	if len(data) != 60 {
		t.Errorf("active file has %d bytes, want 60", len(data))
	}
}

// TestFR64_OversizedSingleLineIsKept checks that a line larger than the limit
// is written whole instead of looping on rotation.
func TestFR64_OversizedSingleLineIsKept(t *testing.T) {
	path := filepath.Join(t.TempDir(), "agent.log")
	line := strings.Repeat("a", 300) + "\n"

	r, err := openRotating(path, 200, 3)
	if err != nil {
		t.Fatalf("openRotating: %v", err)
	}
	defer r.Close()
	if _, err := r.Write([]byte(line)); err != nil {
		t.Fatalf("Write: %v", err)
	}

	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read: %v", err)
	}
	if string(data) != line {
		t.Errorf("oversized line not written whole, got %d bytes", len(data))
	}
}

// TestFR64_LogFilePermissions checks the 0600 mode where the platform has
// Unix permission bits.
func TestFR64_LogFilePermissions(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("file mode bits are not meaningful on Windows")
	}
	path := filepath.Join(t.TempDir(), "agent.log")

	r, err := openRotating(path, 200, 3)
	if err != nil {
		t.Fatalf("openRotating: %v", err)
	}
	defer r.Close()
	if _, err := r.Write([]byte("hello\n")); err != nil {
		t.Fatalf("Write: %v", err)
	}

	info, err := os.Stat(path)
	if err != nil {
		t.Fatalf("stat: %v", err)
	}
	if got := info.Mode().Perm(); got != 0o600 {
		t.Errorf("perm = %o, want 600", got)
	}
}

// TestFR64_DefaultsApplyWhenZero checks that zero options use 5 MiB and 3
// backups, without rotating a small file.
func TestFR64_DefaultsApplyWhenZero(t *testing.T) {
	path := filepath.Join(t.TempDir(), "agent.log")

	logger, closer, err := New(Options{File: path})
	if err != nil {
		t.Fatalf("New: %v", err)
	}
	logger.Info("small")
	if err := closer.Close(); err != nil {
		t.Fatalf("Close: %v", err)
	}
	if _, err := os.Stat(path + ".1"); !os.IsNotExist(err) {
		t.Errorf("small file must not rotate with defaults, stat err = %v", err)
	}
	if defaultMaxBytes != 5<<20 || defaultBackups != 3 {
		t.Errorf("defaults = %d/%d, want 5 MiB/3", defaultMaxBytes, defaultBackups)
	}
}

func TestFR64_RotateFailureKeepsLogging(t *testing.T) {
	path := filepath.Join(t.TempDir(), "agent.log")
	// A non-empty directory at the oldest backup path makes rotation fail.
	oldest := path + ".1"
	if err := os.MkdirAll(filepath.Join(oldest, "keep"), 0o700); err != nil {
		t.Fatal(err)
	}
	rf, err := openRotating(path, 10, 1)
	if err != nil {
		t.Fatal(err)
	}
	defer rf.Close()

	for i := 0; i < 3; i++ {
		if _, err := rf.Write([]byte("0123456789\n")); err != nil {
			t.Fatalf("write %d after failed rotation: %v", i, err)
		}
	}
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if got := strings.Count(string(data), "0123456789"); got != 3 {
		t.Fatalf("lines in active file = %d, want 3", got)
	}
}
