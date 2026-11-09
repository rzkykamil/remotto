package logging

import (
	"bufio"
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// parseLines decodes every non-empty line as a JSON object.
func parseLines(t *testing.T, data []byte) []map[string]any {
	t.Helper()
	var out []map[string]any
	sc := bufio.NewScanner(bytes.NewReader(data))
	for sc.Scan() {
		line := sc.Bytes()
		if len(bytes.TrimSpace(line)) == 0 {
			continue
		}
		var m map[string]any
		if err := json.Unmarshal(line, &m); err != nil {
			t.Fatalf("line is not valid JSON: %q: %v", line, err)
		}
		out = append(out, m)
	}
	if err := sc.Err(); err != nil {
		t.Fatalf("scan: %v", err)
	}
	return out
}

func TestNewJSONLinesHaveRequiredFields(t *testing.T) {
	var buf bytes.Buffer
	logger, closer, err := New(Options{Console: &buf})
	if err != nil {
		t.Fatalf("New: %v", err)
	}
	defer closer.Close()

	logger.Info("server started", "addr", "127.0.0.1:8765")
	logger.Warn("careful")

	lines := parseLines(t, buf.Bytes())
	if len(lines) != 2 {
		t.Fatalf("want 2 lines, got %d", len(lines))
	}
	for _, m := range lines {
		for _, k := range []string{"time", "level", "msg"} {
			if _, ok := m[k]; !ok {
				t.Errorf("line missing %q: %v", k, m)
			}
		}
	}
}

func TestNewWritesToFileAndConsole(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "logs", "agent.log")
	var console bytes.Buffer

	logger, closer, err := New(Options{File: path, Console: &console})
	if err != nil {
		t.Fatalf("New: %v", err)
	}
	logger.Info("hello both")
	if err := closer.Close(); err != nil {
		t.Fatalf("Close: %v", err)
	}

	fileData, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read log file: %v", err)
	}
	if !strings.Contains(string(fileData), `"msg":"hello both"`) {
		t.Errorf("file missing message: %s", fileData)
	}
	if !strings.Contains(console.String(), `"msg":"hello both"`) {
		t.Errorf("console missing message: %s", console.String())
	}
}

func TestNewLevelFilters(t *testing.T) {
	tests := []struct {
		name      string
		level     string
		wantInfo  bool
		wantWarn  bool
		wantError bool
	}{
		{name: "empty means info", level: "", wantInfo: true, wantWarn: true, wantError: true},
		{name: "warn filters info", level: "warn", wantInfo: false, wantWarn: true, wantError: true},
		{name: "error filters warn", level: "ERROR", wantInfo: false, wantWarn: false, wantError: true},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var buf bytes.Buffer
			logger, closer, err := New(Options{Level: tt.level, Console: &buf})
			if err != nil {
				t.Fatalf("New: %v", err)
			}
			defer closer.Close()

			logger.Info("i-msg")
			logger.Warn("w-msg")
			logger.Error("e-msg")

			out := buf.String()
			if got := strings.Contains(out, "i-msg"); got != tt.wantInfo {
				t.Errorf("info logged = %v, want %v", got, tt.wantInfo)
			}
			if got := strings.Contains(out, "w-msg"); got != tt.wantWarn {
				t.Errorf("warn logged = %v, want %v", got, tt.wantWarn)
			}
			if got := strings.Contains(out, "e-msg"); got != tt.wantError {
				t.Errorf("error logged = %v, want %v", got, tt.wantError)
			}
		})
	}
}

func TestBR11_NewRedactsSensitiveAttributes(t *testing.T) {
	const secret = "abc123secret"
	path := filepath.Join(t.TempDir(), "agent.log")

	logger, closer, err := New(Options{File: path})
	if err != nil {
		t.Fatalf("New: %v", err)
	}
	logger.Info("attempt",
		"token", secret,
		"Authorization", "Bearer "+secret,
		"PASSWORD", secret,
		"ip", "192.168.1.20",
	)
	if err := closer.Close(); err != nil {
		t.Fatalf("Close: %v", err)
	}

	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read log file: %v", err)
	}
	if strings.Contains(string(data), secret) {
		t.Errorf("secret value leaked to log: %s", data)
	}
	lines := parseLines(t, data)
	if len(lines) != 1 {
		t.Fatalf("want 1 line, got %d", len(lines))
	}
	for _, k := range []string{"token", "Authorization", "PASSWORD"} {
		if got := lines[0][k]; got != "[redacted]" {
			t.Errorf("%s = %v, want [redacted]", k, got)
		}
	}
	if got := lines[0]["ip"]; got != "192.168.1.20" {
		t.Errorf("ip = %v, want unchanged", got)
	}
}

func TestParseLevel(t *testing.T) {
	tests := []struct {
		in      string
		wantErr bool
	}{
		{in: "debug"},
		{in: "INFO"},
		{in: "Warn"},
		{in: "error"},
		{in: "loud", wantErr: true},
		{in: "", wantErr: true},
	}
	for _, tt := range tests {
		t.Run(tt.in, func(t *testing.T) {
			_, err := ParseLevel(tt.in)
			if (err != nil) != tt.wantErr {
				t.Errorf("ParseLevel(%q) err = %v, wantErr %v", tt.in, err, tt.wantErr)
			}
		})
	}
}

func TestNewRejectsUnknownLevel(t *testing.T) {
	if _, _, err := New(Options{Level: "loud"}); err == nil {
		t.Fatal("want error for unknown level")
	}
}

func TestNewCreatesParentDirectory(t *testing.T) {
	path := filepath.Join(t.TempDir(), "nested", "logs", "agent.log")

	logger, closer, err := New(Options{File: path})
	if err != nil {
		t.Fatalf("New: %v", err)
	}
	logger.Info("created")
	if err := closer.Close(); err != nil {
		t.Fatalf("Close: %v", err)
	}
	if _, err := os.Stat(path); err != nil {
		t.Fatalf("log file not created: %v", err)
	}
}

func TestNewWithoutOutputsDoesNotFail(t *testing.T) {
	logger, closer, err := New(Options{})
	if err != nil {
		t.Fatalf("New: %v", err)
	}
	logger.Info("discarded")
	if err := closer.Close(); err != nil {
		t.Fatalf("Close: %v", err)
	}
}
