package config

import (
	"bytes"
	"errors"
	"io"
	"os"
	"path/filepath"
	"regexp"
	"testing"
)

var agentIDRe = regexp.MustCompile(`^[0-9a-f]{32}$`)

const validAgentID = "0123456789abcdef0123456789abcdef"

// failingReader always returns an error, to simulate a broken entropy source.
type failingReader struct{}

func (failingReader) Read([]byte) (int, error) { return 0, errors.New("entropy unavailable") }

// useAgentIDSource swaps agentIDSource for the duration of one test.
func useAgentIDSource(t *testing.T, r io.Reader) {
	t.Helper()
	prev := agentIDSource
	agentIDSource = r
	t.Cleanup(func() { agentIDSource = prev })
}

func TestNewAgentIDFormat(t *testing.T) {
	tests := []struct {
		name string
		src  io.Reader
		want string
	}{
		{
			name: "sequential bytes encode as lowercase hex",
			src:  bytes.NewReader([]byte{0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15}),
			want: "000102030405060708090a0b0c0d0e0f",
		},
		{
			name: "high bytes stay lowercase",
			src:  bytes.NewReader(bytes.Repeat([]byte{0xab}, 16)),
			want: "abababababababababababababababab",
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			useAgentIDSource(t, tt.src)
			got, err := newAgentID()
			if err != nil {
				t.Fatalf("newAgentID() error: %v", err)
			}
			if got != tt.want {
				t.Fatalf("newAgentID() = %q, want %q", got, tt.want)
			}
		})
	}
}

func TestNewAgentIDShortReadNoPartialValue(t *testing.T) {
	useAgentIDSource(t, bytes.NewReader([]byte{1, 2, 3, 4, 5}))
	got, err := newAgentID()
	if err == nil {
		t.Fatalf("newAgentID() = %q, want error on short read", got)
	}
	if got != "" {
		t.Fatalf("newAgentID() partial value %q returned with error", got)
	}
}

func TestNewAgentIDSourceErrorPropagates(t *testing.T) {
	useAgentIDSource(t, failingReader{})
	if _, err := newAgentID(); err == nil {
		t.Fatal("newAgentID() error = nil, want error")
	}
}

func TestDefaultDiscoveryEnabledAndNoAgentID(t *testing.T) {
	c := Default("PC", fixedNow)
	if !c.Discovery.Enabled {
		t.Fatal("Default().Discovery.Enabled = false, want true")
	}
	if c.AgentID != "" {
		t.Fatalf("Default().AgentID = %q, want empty (generated on first run)", c.AgentID)
	}
}

func TestValidateAgentID(t *testing.T) {
	tests := []struct {
		name      string
		agentID   string
		wantError bool
	}{
		{name: "empty is allowed before backfill", agentID: ""},
		{name: "32 lowercase hex ok", agentID: validAgentID},
		{name: "uppercase rejected", agentID: "0123456789ABCDEF0123456789ABCDEF", wantError: true},
		{name: "31 hex rejected", agentID: validAgentID[:31], wantError: true},
		{name: "33 hex rejected", agentID: validAgentID + "0", wantError: true},
		{name: "non hex rejected", agentID: "g123456789abcdef0123456789abcdef", wantError: true},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			c := Default("PC", fixedNow)
			c.AgentID = tt.agentID
			err := Validate(c)
			if !tt.wantError {
				if err != nil {
					t.Fatalf("Validate() = %v, want nil", err)
				}
				return
			}
			var ve *ValidationError
			if !errors.As(err, &ve) || ve.Field != "agentId" {
				t.Fatalf("Validate() = %v, want ValidationError for agentId", err)
			}
		})
	}
}

func TestLoadDiscoveryDefaults(t *testing.T) {
	tests := []struct {
		name        string
		json        string
		wantEnabled bool
	}{
		{name: "field missing defaults to enabled", json: `{"configVersion":1,"port":9000}`, wantEnabled: true},
		{name: "empty discovery object keeps enabled", json: `{"configVersion":1,"discovery":{}}`, wantEnabled: true},
		{name: "explicit false kept", json: `{"configVersion":1,"discovery":{"enabled":false}}`, wantEnabled: false},
		{name: "explicit true kept", json: `{"configVersion":1,"discovery":{"enabled":true}}`, wantEnabled: true},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			path := filepath.Join(t.TempDir(), "config.json")
			writeFile(t, path, tt.json)
			c, err := Load(path, Default("PC", fixedNow))
			if err != nil {
				t.Fatalf("Load() error: %v", err)
			}
			if c.Discovery.Enabled != tt.wantEnabled {
				t.Fatalf("Discovery.Enabled = %v, want %v", c.Discovery.Enabled, tt.wantEnabled)
			}
		})
	}
}

func TestLoadInvalidAgentIDReturnsValidationError(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.json")
	writeFile(t, path, `{"configVersion":1,"agentId":"ABCDEF"}`)
	_, err := Load(path, Default("PC", fixedNow))
	var ve *ValidationError
	if !errors.As(err, &ve) || ve.Field != "agentId" {
		t.Fatalf("Load() = %v, want ValidationError for agentId", err)
	}
}

func TestLoadOrInitFirstRunCreatesAgentID(t *testing.T) {
	path := filepath.Join(t.TempDir(), "sub", "config.json")
	c, events, err := LoadOrInit(path, Default("PC", fixedNow), stubToken, nil, fixedNow)
	if err != nil {
		t.Fatalf("LoadOrInit() error: %v", err)
	}
	if !agentIDRe.MatchString(c.AgentID) {
		t.Fatalf("AgentID = %q, want 32 lowercase hex", c.AgentID)
	}
	if !c.Discovery.Enabled {
		t.Fatal("Discovery.Enabled = false after first run, want true")
	}
	if got := eventKinds(events); len(got) != 1 || got[0] != EventFirstRun {
		t.Fatalf("events = %v, want [first_run] only", got)
	}
	disk, err := Load(path, Default("PC", fixedNow))
	if err != nil {
		t.Fatalf("Load() after first run error: %v", err)
	}
	if disk.AgentID != c.AgentID {
		t.Fatalf("saved AgentID = %q, want %q", disk.AgentID, c.AgentID)
	}
}

func TestLoadOrInitAgentIDStableAcrossRuns(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.json")
	first, _, err := LoadOrInit(path, Default("PC", fixedNow), stubToken, nil, fixedNow)
	if err != nil {
		t.Fatalf("first LoadOrInit() error: %v", err)
	}
	second, _, err := LoadOrInit(path, Default("PC", fixedNow), stubToken, nil, fixedNow)
	if err != nil {
		t.Fatalf("second LoadOrInit() error: %v", err)
	}
	if second.AgentID != first.AgentID {
		t.Fatalf("AgentID changed across runs: %q -> %q", first.AgentID, second.AgentID)
	}
}

func TestLoadOrInitRecreatedTokenKeepsAgentID(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.json")
	writeFile(t, path, `{"configVersion":1,"agentId":"`+validAgentID+`","token":""}`)
	c, _, err := LoadOrInit(path, Default("PC", fixedNow), stubToken, nil, fixedNow)
	if err != nil {
		t.Fatalf("LoadOrInit() error: %v", err)
	}
	if c.Token != validToken {
		t.Fatalf("Token = %q, want regenerated token", c.Token)
	}
	if c.AgentID != validAgentID {
		t.Fatalf("AgentID = %q, want unchanged %q", c.AgentID, validAgentID)
	}
}

func TestLoadOrInitAgentIDSourceErrorWritesNothing(t *testing.T) {
	useAgentIDSource(t, failingReader{})
	path := filepath.Join(t.TempDir(), "config.json")
	if _, _, err := LoadOrInit(path, Default("PC", fixedNow), stubToken, nil, fixedNow); err == nil {
		t.Fatal("LoadOrInit() error = nil, want error")
	}
	if _, err := os.Stat(path); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("config file exists after failed agentId creation: %v", err)
	}
	assertNoTempFiles(t, filepath.Dir(path))
}

const existingToken = "abababababababababababababababababababababababababababababababab"

// writeLegacyConfig writes a config that predates agentId: it has a token and
// non-default fields, but no agentId.
func writeLegacyConfig(t *testing.T, path string) {
	t.Helper()
	writeFile(t, path, `{"configVersion":1,"laptopName":"Kantor","port":9000,`+
		`"token":"`+existingToken+`","tokenCreatedAt":"2026-01-01T00:00:00Z",`+
		`"discovery":{"enabled":false}}`)
}

func readBytes(t *testing.T, path string) []byte {
	t.Helper()
	b, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read %s: %v", path, err)
	}
	return b
}

func TestEnsureAgentIDFillsAndSavesLegacyConfig(t *testing.T) {
	useAgentIDSource(t, bytes.NewReader(bytes.Repeat([]byte{0x12}, 16)))
	path := filepath.Join(t.TempDir(), "config.json")
	writeLegacyConfig(t, path)
	c, err := Load(path, Default("PC", fixedNow))
	if err != nil {
		t.Fatalf("Load() error: %v", err)
	}

	ev, changed, err := EnsureAgentID(path, &c)
	if err != nil {
		t.Fatalf("EnsureAgentID() error: %v", err)
	}
	if !changed {
		t.Fatal("changed = false, want true")
	}
	if ev.Kind != EventAgentIDCreated {
		t.Fatalf("event kind = %q, want %q", ev.Kind, EventAgentIDCreated)
	}
	want := "12121212121212121212121212121212"
	if c.AgentID != want {
		t.Fatalf("in-memory AgentID = %q, want %q", c.AgentID, want)
	}

	disk, err := Load(path, Default("PC", fixedNow))
	if err != nil {
		t.Fatalf("Load() after EnsureAgentID error: %v", err)
	}
	if disk.AgentID != want {
		t.Fatalf("saved AgentID = %q, want %q", disk.AgentID, want)
	}
	if disk.Token != existingToken {
		t.Fatalf("saved Token changed: %q", disk.Token)
	}
	if disk.TokenCreatedAt != "2026-01-01T00:00:00Z" {
		t.Fatalf("saved TokenCreatedAt changed: %q", disk.TokenCreatedAt)
	}
	if disk.Discovery.Enabled {
		t.Fatal("saved Discovery.Enabled = true, want false (kept)")
	}
	if disk.LaptopName != "Kantor" || disk.Port != 9000 {
		t.Fatalf("other fields changed: name=%q port=%d", disk.LaptopName, disk.Port)
	}
	assertNoTempFiles(t, filepath.Dir(path))
}

func TestEnsureAgentIDSecondCallIsNoOp(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.json")
	writeLegacyConfig(t, path)
	c, err := Load(path, Default("PC", fixedNow))
	if err != nil {
		t.Fatalf("Load() error: %v", err)
	}
	if _, _, err := EnsureAgentID(path, &c); err != nil {
		t.Fatalf("first EnsureAgentID() error: %v", err)
	}
	id := c.AgentID
	before := readBytes(t, path)

	ev, changed, err := EnsureAgentID(path, &c)
	if err != nil {
		t.Fatalf("second EnsureAgentID() error: %v", err)
	}
	if changed {
		t.Fatal("second call changed = true, want false")
	}
	if ev != (Event{}) {
		t.Fatalf("second call event = %+v, want zero", ev)
	}
	if c.AgentID != id {
		t.Fatalf("AgentID changed on no-op: %q -> %q", id, c.AgentID)
	}
	if !bytes.Equal(before, readBytes(t, path)) {
		t.Fatal("file changed on no-op call")
	}
}

func TestEnsureAgentIDResultStableThroughLoadOrInit(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.json")
	writeLegacyConfig(t, path)
	c, err := Load(path, Default("PC", fixedNow))
	if err != nil {
		t.Fatalf("Load() error: %v", err)
	}
	if _, _, err := EnsureAgentID(path, &c); err != nil {
		t.Fatalf("EnsureAgentID() error: %v", err)
	}

	got, events, err := LoadOrInit(path, Default("PC", fixedNow), stubToken, nil, fixedNow)
	if err != nil {
		t.Fatalf("LoadOrInit() error: %v", err)
	}
	if got.AgentID != c.AgentID {
		t.Fatalf("LoadOrInit AgentID = %q, want %q", got.AgentID, c.AgentID)
	}
	if len(events) != 0 {
		t.Fatalf("events = %v, want none", eventKinds(events))
	}
}

func TestEnsureAgentIDSourceErrorLeavesFileAndMemory(t *testing.T) {
	useAgentIDSource(t, failingReader{})
	path := filepath.Join(t.TempDir(), "config.json")
	writeLegacyConfig(t, path)
	before := readBytes(t, path)
	c, err := Load(path, Default("PC", fixedNow))
	if err != nil {
		t.Fatalf("Load() error: %v", err)
	}

	ev, changed, err := EnsureAgentID(path, &c)
	if err == nil {
		t.Fatal("EnsureAgentID() error = nil, want error")
	}
	if changed || ev != (Event{}) {
		t.Fatalf("changed=%v event=%+v on error, want false and zero", changed, ev)
	}
	if c.AgentID != "" {
		t.Fatalf("in-memory AgentID = %q after error, want empty", c.AgentID)
	}
	if !bytes.Equal(before, readBytes(t, path)) {
		t.Fatal("file changed after agentId source error")
	}
	assertNoTempFiles(t, filepath.Dir(path))
}

func TestEnsureAgentIDSaveFailureKeepsMemoryEmpty(t *testing.T) {
	dir := t.TempDir()
	blocker := filepath.Join(dir, "blocker")
	if err := os.WriteFile(blocker, []byte("not a folder"), 0o600); err != nil {
		t.Fatalf("write blocker: %v", err)
	}
	// The config folder is a regular file, so the save cannot create it.
	path := filepath.Join(blocker, "config.json")
	c := Default("PC", fixedNow)
	c.Token = existingToken
	c.TokenCreatedAt = "2026-01-01T00:00:00Z"

	ev, changed, err := EnsureAgentID(path, &c)
	if err == nil {
		t.Fatal("EnsureAgentID() error = nil, want error")
	}
	if changed || ev != (Event{}) {
		t.Fatalf("changed=%v event=%+v on save error, want false and zero", changed, ev)
	}
	if c.AgentID != "" {
		t.Fatalf("in-memory AgentID = %q after save error, want empty", c.AgentID)
	}
	if got := readBytes(t, blocker); string(got) != "not a folder" {
		t.Fatalf("blocker file changed: %q", got)
	}
}
