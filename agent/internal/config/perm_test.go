package config

import (
	"errors"
	"os"
	"path/filepath"
	"reflect"
	"testing"
)

// permCall records one Ensure call and whether the path existed at that time.
type permCall struct {
	path    string
	existed bool
}

// fakePerm is a PermChecker that records calls and returns scripted results.
type fakePerm struct {
	fixed map[string]bool
	errs  map[string]error
	calls []permCall
}

func (f *fakePerm) Ensure(path string) (bool, error) {
	_, err := os.Stat(path)
	f.calls = append(f.calls, permCall{path: path, existed: err == nil})
	if e := f.errs[path]; e != nil {
		return false, e
	}
	return f.fixed[path], nil
}

func (f *fakePerm) paths() []string {
	out := make([]string, 0, len(f.calls))
	for _, c := range f.calls {
		out = append(out, c.path)
	}
	return out
}

func TestLoadOrInitSecuresFolderBeforeFirstWrite(t *testing.T) {
	dir := filepath.Join(t.TempDir(), "Remotto")
	path := filepath.Join(dir, "config.json")
	perm := &fakePerm{}

	_, events, err := LoadOrInit(path, Default("PC", fixedNow), stubToken, perm, fixedNow)
	if err != nil {
		t.Fatalf("LoadOrInit() error: %v", err)
	}
	if got := perm.paths(); !reflect.DeepEqual(got, []string{dir}) {
		t.Fatalf("Ensure paths = %v, want [folder]", got)
	}
	if !perm.calls[0].existed {
		t.Fatal("folder was not created before Ensure")
	}
	if _, err := os.Stat(path); err != nil {
		t.Fatalf("config not written: %v", err)
	}
	if got := eventKinds(events); len(got) != 1 || got[0] != EventFirstRun {
		t.Fatalf("events = %v, want [first_run]", got)
	}
}

func TestLoadOrInitSecuresExistingFilesBeforeUse(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.json")
	content := `{"configVersion":1,"port":9000,"token":"` + validToken + `","tokenCreatedAt":"2026-01-01T00:00:00Z"}`
	writeFile(t, path, content)
	perm := &fakePerm{}

	_, events, err := LoadOrInit(path, Default("PC", fixedNow), stubToken, perm, fixedNow)
	if err != nil {
		t.Fatalf("LoadOrInit() error: %v", err)
	}
	if got := perm.paths(); !reflect.DeepEqual(got, []string{filepath.Dir(path), path}) {
		t.Fatalf("Ensure paths = %v, want [folder config.json]", got)
	}
	if len(events) != 0 {
		t.Fatalf("events = %v, want none", eventKinds(events))
	}
	if got := string(readAll(t, path)); got != content {
		t.Fatal("file changed on valid load")
	}
}

func TestLoadOrInitPermFixedEmitsEvent(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.json")
	writeFile(t, path, `{"configVersion":1,"port":9000,"token":""}`)
	perm := &fakePerm{fixed: map[string]bool{path: true}}

	c, events, err := LoadOrInit(path, Default("PC", fixedNow), stubToken, perm, fixedNow)
	if err != nil {
		t.Fatalf("LoadOrInit() error: %v", err)
	}
	if c.Token != validToken {
		t.Fatalf("Token = %q, want generated token", c.Token)
	}
	if len(events) != 1 || events[0].Kind != EventPermFixed || events[0].Detail != "config.json" {
		t.Fatalf("events = %+v, want [perm_fixed config.json]", events)
	}
}

func TestLoadOrInitPermErrorFailsStart(t *testing.T) {
	t.Run("folder", func(t *testing.T) {
		dir := filepath.Join(t.TempDir(), "Remotto")
		path := filepath.Join(dir, "config.json")
		perm := &fakePerm{errs: map[string]error{dir: errors.New("denied")}}

		_, _, err := LoadOrInit(path, Default("PC", fixedNow), stubToken, perm, fixedNow)
		if err == nil {
			t.Fatal("LoadOrInit() error = nil, want permission error")
		}
		if _, statErr := os.Stat(path); !errors.Is(statErr, os.ErrNotExist) {
			t.Fatalf("config written despite permission error: %v", statErr)
		}
	})

	t.Run("existing file", func(t *testing.T) {
		path := filepath.Join(t.TempDir(), "config.json")
		content := `{"configVersion":1,"port":9000,"token":""}`
		writeFile(t, path, content)
		perm := &fakePerm{errs: map[string]error{path: errors.New("denied")}}

		_, _, err := LoadOrInit(path, Default("PC", fixedNow), stubToken, perm, fixedNow)
		if err == nil {
			t.Fatal("LoadOrInit() error = nil, want permission error")
		}
		if got := string(readAll(t, path)); got != content {
			t.Fatal("file changed despite permission error")
		}
	})
}

func TestLoadOrInitSecuresCorruptFilesBeforeRename(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.json")
	writeFile(t, path, `{not json`)
	corrupt := path + ".corrupt"
	writeFile(t, corrupt, `old`)
	perm := &fakePerm{fixed: map[string]bool{corrupt: true}}

	_, events, err := LoadOrInit(path, Default("PC", fixedNow), stubToken, perm, fixedNow)
	if err != nil {
		t.Fatalf("LoadOrInit() error: %v", err)
	}
	if got := perm.paths(); !reflect.DeepEqual(got, []string{filepath.Dir(path), path, corrupt}) {
		t.Fatalf("Ensure paths = %v", got)
	}
	if got := eventKinds(events); !reflect.DeepEqual(got, []EventKind{EventPermFixed, EventCorruptReplaced}) {
		t.Fatalf("events = %v, want [perm_fixed corrupt_replaced]", got)
	}
}

func TestLoadOrInitSecuresBackupBeforeWrite(t *testing.T) {
	migrations[0] = func(doc map[string]any) error {
		doc["laptopName"] = "Migrated"
		return nil
	}
	t.Cleanup(func() { delete(migrations, 0) })

	path := filepath.Join(t.TempDir(), "config.json")
	writeFile(t, path, `{"configVersion":0,"port":9000,"token":"`+validToken+`"}`)
	bak := path + ".v0.bak"
	writeFile(t, bak, `old backup`)
	perm := &fakePerm{}

	_, _, err := LoadOrInit(path, Default("PC", fixedNow), stubToken, perm, fixedNow)
	if err != nil {
		t.Fatalf("LoadOrInit() error: %v", err)
	}
	if got := perm.paths(); !reflect.DeepEqual(got, []string{filepath.Dir(path), path, bak}) {
		t.Fatalf("Ensure paths = %v", got)
	}
	if got := string(readAll(t, bak)); got == "old backup" {
		t.Fatal("backup was not rewritten")
	}
}
