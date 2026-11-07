package config

import (
	"bytes"
	"errors"
	"io/fs"
	"os"
	"path/filepath"
	"regexp"
	"testing"
	"time"
)

var tokenRe = regexp.MustCompile(`^[0-9a-f]{64}$`)

func stubToken() (string, error) { return validToken, nil }

func readAll(t *testing.T, path string) []byte {
	t.Helper()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read %s: %v", path, err)
	}
	return data
}

func eventKinds(events []Event) []EventKind {
	kinds := make([]EventKind, 0, len(events))
	for _, e := range events {
		kinds = append(kinds, e.Kind)
	}
	return kinds
}

func TestLoadOrInitFirstRun(t *testing.T) {
	path := filepath.Join(t.TempDir(), "sub", "config.json")
	c, events, err := LoadOrInit(path, Default("PC", fixedNow), stubToken, nil, fixedNow)
	if err != nil {
		t.Fatalf("LoadOrInit() error: %v", err)
	}
	if !tokenRe.MatchString(c.Token) || c.Token != validToken {
		t.Fatalf("Token = %q, want generated token", c.Token)
	}
	if c.TokenCreatedAt != fixedNow.Format(time.RFC3339) {
		t.Fatalf("TokenCreatedAt = %q", c.TokenCreatedAt)
	}
	if got := eventKinds(events); len(got) != 1 || got[0] != EventFirstRun {
		t.Fatalf("events = %v, want [first_run]", got)
	}
	disk, err := Load(path, Default("PC", fixedNow))
	if err != nil {
		t.Fatalf("Load() after first run error: %v", err)
	}
	if disk.Token != validToken {
		t.Fatalf("saved token = %q, want %q", disk.Token, validToken)
	}
	assertNoTempFiles(t, filepath.Dir(path))
}

func TestLoadOrInitExistingValidIsUntouched(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.json")
	content := `{"configVersion":1,"port":9000,"token":"` + validToken + `","tokenCreatedAt":"2026-01-01T00:00:00Z"}`
	writeFile(t, path, content)

	c, events, err := LoadOrInit(path, Default("PC", fixedNow), stubToken, nil, fixedNow)
	if err != nil {
		t.Fatalf("LoadOrInit() error: %v", err)
	}
	if c.Port != 9000 || c.Token != validToken {
		t.Fatalf("loaded config = %+v", c)
	}
	if len(events) != 0 {
		t.Fatalf("events = %v, want none", eventKinds(events))
	}
	if got := string(readAll(t, path)); got != content {
		t.Fatalf("file changed on valid load")
	}
}

func TestLoadOrInitEmptyTokenFilled(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.json")
	writeFile(t, path, `{"configVersion":1,"port":9000,"token":""}`)

	c, _, err := LoadOrInit(path, Default("PC", fixedNow), stubToken, nil, fixedNow)
	if err != nil {
		t.Fatalf("LoadOrInit() error: %v", err)
	}
	if c.Token != validToken {
		t.Fatalf("Token = %q, want generated token", c.Token)
	}
	disk, err := Load(path, Default("PC", fixedNow))
	if err != nil {
		t.Fatalf("Load() error: %v", err)
	}
	if disk.Token != validToken || disk.Port != 9000 {
		t.Fatalf("saved config = %+v, want token filled and port kept", disk)
	}
}

func TestLoadOrInitCorruptJSONReplaced(t *testing.T) {
	tests := []struct {
		name    string
		content string
	}{
		{name: "truncated object", content: `{"port":`},
		{name: "empty file", content: ``},
		{name: "not json", content: `hello`},
		{name: "json null", content: `null`},
		{name: "wrong type", content: `{"configVersion":1,"port":"x"}`},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			path := filepath.Join(t.TempDir(), "config.json")
			writeFile(t, path, tt.content)

			c, events, err := LoadOrInit(path, Default("PC", fixedNow), stubToken, nil, fixedNow)
			if err != nil {
				t.Fatalf("LoadOrInit() error: %v", err)
			}
			if c.Token != validToken {
				t.Fatalf("Token = %q, want new token", c.Token)
			}
			if got := eventKinds(events); len(got) != 1 || got[0] != EventCorruptReplaced {
				t.Fatalf("events = %v, want [corrupt_replaced]", got)
			}
			if got := string(readAll(t, path+".corrupt")); got != tt.content {
				t.Fatalf(".corrupt content = %q, want original", got)
			}
			if _, err := Load(path, Default("PC", fixedNow)); err != nil {
				t.Fatalf("new config invalid: %v", err)
			}
		})
	}
}

func TestLoadOrInitNewerVersionRefused(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.json")
	content := `{"configVersion":2,"port":"future-shape","token":"x"}`
	writeFile(t, path, content)

	_, events, err := LoadOrInit(path, Default("PC", fixedNow), stubToken, nil, fixedNow)
	if !errors.Is(err, ErrNewerVersion) {
		t.Fatalf("LoadOrInit() error = %v, want ErrNewerVersion", err)
	}
	if events != nil {
		t.Fatalf("events = %v, want none", eventKinds(events))
	}
	if got := string(readAll(t, path)); got != content {
		t.Fatalf("newer file was modified: %q", got)
	}
	assertNoSibling(t, path, ".corrupt", ".bak")
}

func TestLoadOrInitMigratesOlderVersion(t *testing.T) {
	migrations[0] = func(doc map[string]any) error {
		doc["laptopName"] = "Migrated"
		return nil
	}
	t.Cleanup(func() { delete(migrations, 0) })

	path := filepath.Join(t.TempDir(), "config.json")
	original := `{"configVersion":0,"laptopName":"Old","port":9000,"token":"` + validToken + `","tokenCreatedAt":"2026-01-01T00:00:00Z"}`
	writeFile(t, path, original)

	c, events, err := LoadOrInit(path, Default("PC", fixedNow), stubToken, nil, fixedNow)
	if err != nil {
		t.Fatalf("LoadOrInit() error: %v", err)
	}
	if c.LaptopName != "Migrated" || c.ConfigVersion != CurrentVersion || c.Port != 9000 {
		t.Fatalf("migrated config = %+v", c)
	}
	if got := eventKinds(events); len(got) != 1 || got[0] != EventMigrated {
		t.Fatalf("events = %v, want [migrated]", got)
	}
	if got := string(readAll(t, path+".v0.bak")); got != original {
		t.Fatalf("backup content differs from original")
	}
	disk, err := Load(path, Default("PC", fixedNow))
	if err != nil {
		t.Fatalf("Load() after migration error: %v", err)
	}
	if disk.LaptopName != "Migrated" {
		t.Fatalf("saved LaptopName = %q", disk.LaptopName)
	}
}

func TestLoadOrInitMissingMigrationStepFailsUntouched(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.json")
	content := `{"configVersion":0,"port":9000,"token":"` + validToken + `"}`
	writeFile(t, path, content)

	_, _, err := LoadOrInit(path, Default("PC", fixedNow), stubToken, nil, fixedNow)
	if err == nil {
		t.Fatal("LoadOrInit() error = nil, want missing migration error")
	}
	if got := string(readAll(t, path)); got != content {
		t.Fatalf("file changed on failed migration")
	}
	assertNoSibling(t, path, ".bak")
}

func TestLoadOrInitInvalidValueLeavesFileUntouched(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.json")
	content := `{"configVersion":1,"port":80,"token":"` + validToken + `"}`
	writeFile(t, path, content)

	_, _, err := LoadOrInit(path, Default("PC", fixedNow), stubToken, nil, fixedNow)
	var ve *ValidationError
	if !errors.As(err, &ve) || ve.Field != "port" {
		t.Fatalf("LoadOrInit() error = %v, want ValidationError on port", err)
	}
	if got := string(readAll(t, path)); got != content {
		t.Fatalf("file changed on validation failure")
	}
}

func TestLoadOrInitNewTokenErrorWritesNothing(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.json")
	fail := func() (string, error) { return "", errors.New("rng down") }

	_, _, err := LoadOrInit(path, Default("PC", fixedNow), fail, nil, fixedNow)
	if err == nil {
		t.Fatal("LoadOrInit() error = nil, want error")
	}
	if _, err := os.Stat(path); !errors.Is(err, fs.ErrNotExist) {
		t.Fatalf("config created despite token failure: %v", err)
	}
}

func TestLoadOrInitUnwritableFolderErrors(t *testing.T) {
	dir := t.TempDir()
	blocker := filepath.Join(dir, "blocker")
	blockerContent := []byte("i am a file, not a folder")
	if err := os.WriteFile(blocker, blockerContent, 0o600); err != nil {
		t.Fatalf("write blocker: %v", err)
	}
	path := filepath.Join(blocker, "sub", "config.json")

	_, _, err := LoadOrInit(path, Default("PC", fixedNow), stubToken, nil, fixedNow)
	if err == nil {
		t.Fatal("LoadOrInit() error = nil, want error when folder cannot be created")
	}
	if !bytes.Equal(readAll(t, blocker), blockerContent) {
		t.Fatal("blocker file changed")
	}
}

func TestLoadVersionChecks(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.json")
	writeFile(t, path, `{"configVersion":2}`)
	if _, err := Load(path, Default("PC", fixedNow)); !errors.Is(err, ErrNewerVersion) {
		t.Fatalf("Load(newer) error = %v, want ErrNewerVersion", err)
	}

	writeFile(t, path, `{"configVersion":0}`)
	var ve *ValidationError
	if _, err := Load(path, Default("PC", fixedNow)); !errors.As(err, &ve) || ve.Field != "configVersion" {
		t.Fatalf("Load(older) error = %v, want ValidationError on configVersion", err)
	}
}

func TestSaveRejectsWrongVersion(t *testing.T) {
	c := Default("PC", fixedNow)
	c.ConfigVersion = 2
	path := filepath.Join(t.TempDir(), "config.json")
	if err := Save(path, c); !errors.Is(err, ErrNewerVersion) {
		t.Fatalf("Save(newer) error = %v, want ErrNewerVersion", err)
	}
	if _, err := os.Stat(path); !errors.Is(err, fs.ErrNotExist) {
		t.Fatalf("Save wrote a file for a refused version: %v", err)
	}
}

// assertNoSibling fails when path+suffix exists for any suffix.
func assertNoSibling(t *testing.T, path string, suffixes ...string) {
	t.Helper()
	for _, s := range suffixes {
		if _, err := os.Stat(path + s); err == nil {
			t.Fatalf("unexpected file %s%s", path, s)
		}
	}
}
