package config

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"time"
)

// agentIDSource supplies the random bytes for newAgentID. Tests replace it.
var agentIDSource io.Reader = rand.Reader

// newAgentID returns 16 random bytes from agentIDSource as 32 lowercase hex
// characters. A short read fails without returning a partial value.
func newAgentID() (string, error) {
	var b [16]byte
	if _, err := io.ReadFull(agentIDSource, b[:]); err != nil {
		return "", fmt.Errorf("create agent id: %w", err)
	}
	return hex.EncodeToString(b[:]), nil
}

// EventKind names a lifecycle event reported by LoadOrInit. Events never
// carry the token value.
type EventKind string

const (
	// EventFirstRun means no config file existed and a new one was created.
	EventFirstRun EventKind = "first_run"
	// EventCorruptReplaced means the file was not valid JSON, was renamed to
	// config.json.corrupt, and a new config was created.
	EventCorruptReplaced EventKind = "corrupt_replaced"
	// EventMigrated means the file was upgraded from an older configVersion.
	EventMigrated EventKind = "migrated"
	// EventPermFixed means loose permissions were tightened by PermChecker.
	EventPermFixed EventKind = "perm_fixed"
	// EventAgentIDCreated means an existing config had no agentId and one was
	// created and saved by EnsureAgentID.
	EventAgentIDCreated EventKind = "agent_id_created"
)

// Event is one lifecycle occurrence for the caller to log.
type Event struct {
	Kind   EventKind
	Detail string
}

const corruptSuffix = ".corrupt"

// LoadOrInit loads the config at path, or creates, repairs or migrates it.
//
//   - Missing file: a new config is created with a token (first run).
//   - Invalid JSON: the file is renamed to config.json.corrupt and a new
//     config is created.
//   - configVersion newer than CurrentVersion: ErrNewerVersion, file untouched.
//   - configVersion older: the original is copied to config.json.v<N>.bak,
//     migrated in order, and saved.
//   - Empty token: a token is created and saved.
//
// Out-of-range values return *ValidationError and leave the file untouched.
// newToken creates a new token; now sets the timestamps.
//
// When perm is not nil, the config folder is created if missing and secured
// before anything is read or written. Every existing file that LoadOrInit
// may write (config.json, config.json.corrupt, config.json.v<N>.bak) is
// secured right before it is touched. A PermChecker error fails the call. A
// fixed permission adds an EventPermFixed. A nil perm skips these checks.
func LoadOrInit(path string, defaults Config, newToken func() (string, error), perm PermChecker, now time.Time) (Config, []Event, error) {
	var events []Event
	if perm != nil {
		dir := filepath.Dir(path)
		if err := os.MkdirAll(dir, 0o700); err != nil {
			return Config{}, nil, fmt.Errorf("create config folder: %w", err)
		}
		var err error
		if events, err = securePath(perm, dir, events); err != nil {
			return Config{}, nil, err
		}
		if events, err = securePathIfExists(perm, path, events); err != nil {
			return Config{}, nil, err
		}
	}

	raw, err := os.ReadFile(path)
	if errors.Is(err, fs.ErrNotExist) {
		c, err := initConfig(path, defaults, newToken, now)
		if err != nil {
			return Config{}, nil, err
		}
		return c, append(events, Event{Kind: EventFirstRun}), nil
	}
	if err != nil {
		return Config{}, nil, fmt.Errorf("read config %s: %w", path, err)
	}

	version, err := probeVersion(raw)
	if err != nil {
		return replaceCorrupt(path, defaults, newToken, now, perm, events)
	}
	if version > CurrentVersion {
		return Config{}, nil, checkVersion(version)
	}

	data := raw
	if version < CurrentVersion {
		data, err = migrate(raw, version)
		if err != nil {
			return Config{}, nil, err
		}
	}
	c, err := decodeInto(data, defaults)
	if err != nil {
		return replaceCorrupt(path, defaults, newToken, now, perm, events)
	}
	if err := Validate(c); err != nil {
		return Config{}, nil, err
	}

	if version < CurrentVersion {
		bak := fmt.Sprintf("%s.v%d.bak", path, version)
		if perm != nil {
			if events, err = securePathIfExists(perm, bak, events); err != nil {
				return Config{}, nil, err
			}
		}
		if err := os.WriteFile(bak, raw, 0o600); err != nil {
			return Config{}, nil, fmt.Errorf("write config backup: %w", err)
		}
		events = append(events, Event{
			Kind:   EventMigrated,
			Detail: fmt.Sprintf("configVersion %d -> %d", version, CurrentVersion),
		})
	}

	needSave := version < CurrentVersion
	if c.Token == "" {
		tok, err := newToken()
		if err != nil {
			return Config{}, nil, fmt.Errorf("create token: %w", err)
		}
		c.Token = tok
		c.TokenCreatedAt = now.Format(time.RFC3339)
		needSave = true
	}
	if needSave {
		if err := Save(path, c); err != nil {
			return Config{}, nil, err
		}
	}
	return c, events, nil
}

// securePath runs perm.Ensure on path and appends EventPermFixed when the
// permissions had to be tightened. The error names only the base file name.
func securePath(perm PermChecker, path string, events []Event) ([]Event, error) {
	fixed, err := perm.Ensure(path)
	if err != nil {
		return events, fmt.Errorf("secure %s: %w", filepath.Base(path), err)
	}
	if fixed {
		events = append(events, Event{Kind: EventPermFixed, Detail: filepath.Base(path)})
	}
	return events, nil
}

// securePathIfExists secures path only when it exists. A missing path is
// created later by Save or WriteFile, and it inherits the secured folder.
func securePathIfExists(perm PermChecker, path string, events []Event) ([]Event, error) {
	if _, err := os.Stat(path); errors.Is(err, fs.ErrNotExist) {
		return events, nil
	} else if err != nil {
		return events, fmt.Errorf("stat %s: %w", filepath.Base(path), err)
	}
	return securePath(perm, path, events)
}

// probeVersion reads configVersion from data. It fails when data is not a
// JSON object or configVersion is not an integer. A missing field gives 0.
func probeVersion(data []byte) (int, error) {
	var top map[string]json.RawMessage
	if err := json.Unmarshal(data, &top); err != nil {
		return 0, fmt.Errorf("parse config: %w", err)
	}
	if top == nil {
		return 0, errors.New("config is not a JSON object")
	}
	var probe struct {
		ConfigVersion int `json:"configVersion"`
	}
	if err := json.Unmarshal(data, &probe); err != nil {
		return 0, fmt.Errorf("parse configVersion: %w", err)
	}
	return probe.ConfigVersion, nil
}

// initConfig creates a fresh config with a new token and saves it.
func initConfig(path string, defaults Config, newToken func() (string, error), now time.Time) (Config, error) {
	c := defaults
	if c.CreatedAt == "" {
		c.CreatedAt = now.Format(time.RFC3339)
	}
	if c.AgentID == "" {
		id, err := newAgentID()
		if err != nil {
			return Config{}, err
		}
		c.AgentID = id
	}
	tok, err := newToken()
	if err != nil {
		return Config{}, fmt.Errorf("create token: %w", err)
	}
	c.Token = tok
	c.TokenCreatedAt = now.Format(time.RFC3339)
	if err := Save(path, c); err != nil {
		return Config{}, err
	}
	return c, nil
}

// replaceCorrupt moves the unreadable file aside and creates a new config.
// An existing config.json.corrupt is secured before the rename replaces it.
func replaceCorrupt(path string, defaults Config, newToken func() (string, error), now time.Time, perm PermChecker, events []Event) (Config, []Event, error) {
	dst := path + corruptSuffix
	var err error
	if perm != nil {
		if events, err = securePathIfExists(perm, dst, events); err != nil {
			return Config{}, nil, err
		}
	}
	if err := os.Rename(path, dst); err != nil {
		return Config{}, nil, fmt.Errorf("move corrupt config aside: %w", err)
	}
	c, err := initConfig(path, defaults, newToken, now)
	if err != nil {
		return Config{}, nil, err
	}
	return c, append(events, Event{Kind: EventCorruptReplaced, Detail: filepath.Base(dst)}), nil
}

// EnsureAgentID gives an existing config an agentId when it has none. A config
// that already has one is left alone and returns false. Otherwise a new id is
// created, saved atomically with the rest of c (token and other fields are kept),
// and c.AgentID is set only after the save succeeds. The returned Event is
// EventAgentIDCreated. LoadOrInit does not call this; the caller runs it after
// LoadOrInit.
func EnsureAgentID(path string, c *Config) (Event, bool, error) {
	if c.AgentID != "" {
		return Event{}, false, nil
	}
	id, err := newAgentID()
	if err != nil {
		return Event{}, false, err
	}
	next := *c
	next.AgentID = id
	if err := Save(path, next); err != nil {
		return Event{}, false, err
	}
	*c = next
	return Event{Kind: EventAgentIDCreated}, true, nil
}
