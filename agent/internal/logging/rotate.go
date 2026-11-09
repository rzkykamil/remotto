package logging

import (
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"strconv"
	"sync"
)

// rotatingFile is an io.WriteCloser that rotates its file by size. When a
// write would push the file past maxBytes, the file is closed and shifted to
// path.1, path.1 to path.2, and so on. The oldest backup (path.<backups>) is
// dropped. A write is never split across two files: rotation happens before
// the line is written.
type rotatingFile struct {
	mu       sync.Mutex
	path     string
	maxBytes int64
	backups  int
	f        *os.File
	size     int64
}

var _ io.WriteCloser = (*rotatingFile)(nil)

// openRotating opens path for appending and continues from its current size.
func openRotating(path string, maxBytes int64, backups int) (*rotatingFile, error) {
	r := &rotatingFile{path: path, maxBytes: maxBytes, backups: backups}
	if err := r.open(); err != nil {
		return nil, err
	}
	return r, nil
}

// open opens the active file and records its existing size.
func (r *rotatingFile) open() error {
	f, err := os.OpenFile(r.path, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o600)
	if err != nil {
		return err
	}
	info, err := f.Stat()
	if err != nil {
		f.Close()
		return err
	}
	r.f = f
	r.size = info.Size()
	return nil
}

// Write appends p, rotating first when it would exceed maxBytes. An empty
// active file is never rotated, so a single oversized line is still written.
func (r *rotatingFile) Write(p []byte) (int, error) {
	r.mu.Lock()
	defer r.mu.Unlock()

	if r.f == nil {
		return 0, fs.ErrClosed
	}
	if r.size > 0 && r.size+int64(len(p)) > r.maxBytes {
		if err := r.rotate(); err != nil {
			// Rotation can fail on Windows when another program holds a
			// backup open. Keep logging to the active file instead of
			// leaving the logger closed for the rest of the process.
			if r.f == nil {
				if oerr := r.open(); oerr != nil {
					return 0, errors.Join(err, oerr)
				}
			}
		}
	}
	n, err := r.f.Write(p)
	r.size += int64(n)
	return n, err
}

// rotate closes the active file, shifts the backups and reopens path.
func (r *rotatingFile) rotate() error {
	if err := r.f.Close(); err != nil {
		r.f = nil
		return fmt.Errorf("logging: close before rotate: %w", err)
	}
	r.f = nil

	if r.backups <= 0 {
		if err := os.Remove(r.path); err != nil && !errors.Is(err, fs.ErrNotExist) {
			return fmt.Errorf("logging: remove log file: %w", err)
		}
	} else {
		oldest := r.backupPath(r.backups)
		if err := os.Remove(oldest); err != nil && !errors.Is(err, fs.ErrNotExist) {
			return fmt.Errorf("logging: remove oldest backup: %w", err)
		}
		for i := r.backups - 1; i >= 1; i-- {
			// A missing source just means there is no such backup yet.
			_ = os.Rename(r.backupPath(i), r.backupPath(i+1))
		}
		if err := os.Rename(r.path, r.backupPath(1)); err != nil && !errors.Is(err, fs.ErrNotExist) {
			return fmt.Errorf("logging: rotate active file: %w", err)
		}
	}
	return r.open()
}

// Close closes the active file. Closing twice is safe.
func (r *rotatingFile) Close() error {
	r.mu.Lock()
	defer r.mu.Unlock()

	if r.f == nil {
		return nil
	}
	err := r.f.Close()
	r.f = nil
	return err
}

func (r *rotatingFile) backupPath(i int) string {
	return r.path + "." + strconv.Itoa(i)
}
