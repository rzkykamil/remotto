// Package logging builds the agent's structured logger.
//
// Output is one JSON object per line via log/slog. The logger writes to an
// optional log file and an optional console writer at the same time. Sensitive
// attributes (token, authorization, password) are redacted defensively, even
// though callers are expected never to log them.
package logging

import (
	"fmt"
	"io"
	"log/slog"
	"os"
	"path/filepath"
	"strings"
)

// Options configures New.
type Options struct {
	Level   string    // debug|info|warn|error; empty means info
	File    string    // full path of the log file; empty means no file
	Console io.Writer // nil means no console output
}

const redacted = "[redacted]"

// sensitiveKeys lists attribute keys whose values are never written.
var sensitiveKeys = []string{"token", "authorization", "password"}

// ParseLevel converts a level name into a slog.Level. The match is
// case-insensitive. Unknown names return an error.
func ParseLevel(s string) (slog.Level, error) {
	switch strings.ToLower(s) {
	case "debug":
		return slog.LevelDebug, nil
	case "info":
		return slog.LevelInfo, nil
	case "warn":
		return slog.LevelWarn, nil
	case "error":
		return slog.LevelError, nil
	default:
		return 0, fmt.Errorf("logging: unknown level %q", s)
	}
}

// New returns a JSON logger and a Closer that releases the log file. Closing
// is a no-op when no file is configured. With neither a file nor a console,
// the logger discards its output.
func New(opts Options) (*slog.Logger, io.Closer, error) {
	level := slog.LevelInfo
	if opts.Level != "" {
		lv, err := ParseLevel(opts.Level)
		if err != nil {
			return nil, nil, err
		}
		level = lv
	}

	var writers []io.Writer
	var closer io.Closer = nopCloser{}
	if opts.File != "" {
		if err := os.MkdirAll(filepath.Dir(opts.File), 0o700); err != nil {
			return nil, nil, fmt.Errorf("logging: create log directory: %w", err)
		}
		f, err := os.OpenFile(opts.File, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o600)
		if err != nil {
			return nil, nil, fmt.Errorf("logging: open log file: %w", err)
		}
		writers = append(writers, f)
		closer = f
	}
	if opts.Console != nil {
		writers = append(writers, opts.Console)
	}

	var w io.Writer = io.Discard
	switch len(writers) {
	case 0:
	case 1:
		w = writers[0]
	default:
		w = io.MultiWriter(writers...)
	}

	handler := slog.NewJSONHandler(w, &slog.HandlerOptions{
		Level:       level,
		ReplaceAttr: redact,
	})
	return slog.New(handler), closer, nil
}

// redact replaces the value of sensitive attributes. The default keys time,
// level and msg are left untouched.
func redact(_ []string, a slog.Attr) slog.Attr {
	for _, k := range sensitiveKeys {
		if strings.EqualFold(a.Key, k) {
			return slog.String(a.Key, redacted)
		}
	}
	return a
}

type nopCloser struct{}

func (nopCloser) Close() error { return nil }
