// Package config loads, validates and saves the agent configuration file.
package config

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"time"
)

// CurrentVersion is the config schema version this agent understands.
const CurrentVersion = 1

const (
	defaultLaptopName  = "Laptop"
	defaultPort        = 8765
	defaultBindAddress = "0.0.0.0"
	defaultPowerDelay  = 5
	defaultRPS         = 20
	defaultBurst       = 40
	defaultLogLevel    = "info"
	maxLaptopNameRunes = 64
)

// RateLimit holds the per-IP request rate limit settings.
type RateLimit struct {
	RequestsPerSecond int `json:"requestsPerSecond"`
	Burst             int `json:"burst"`
}

// Config is the content of config.json.
type Config struct {
	ConfigVersion     int       `json:"configVersion"`
	LaptopName        string    `json:"laptopName"`
	Port              int       `json:"port"`
	BindAddress       string    `json:"bindAddress"`
	Token             string    `json:"token"`
	TokenCreatedAt    string    `json:"tokenCreatedAt"`
	CreatedAt         string    `json:"createdAt"`
	PowerDelaySeconds int       `json:"powerDelaySeconds"`
	RateLimit         RateLimit `json:"rateLimit"`
	LogLevel          string    `json:"logLevel"`
}

// Dir returns the Remotto data folder, %APPDATA%\Remotto.
func Dir() (string, error) {
	base := os.Getenv("APPDATA")
	if base == "" {
		dir, err := os.UserConfigDir()
		if err != nil {
			return "", fmt.Errorf("config dir: %w", err)
		}
		base = dir
	}
	return filepath.Join(base, "Remotto"), nil
}

// DefaultPath returns the path of config.json inside Dir.
func DefaultPath() (string, error) {
	dir, err := Dir()
	if err != nil {
		return "", err
	}
	return filepath.Join(dir, "config.json"), nil
}

// Default returns the default config for a laptop with the given hostname.
func Default(hostname string, now time.Time) Config {
	return Config{
		ConfigVersion:     CurrentVersion,
		LaptopName:        laptopNameFrom(hostname),
		Port:              defaultPort,
		BindAddress:       defaultBindAddress,
		Token:             "",
		TokenCreatedAt:    "",
		CreatedAt:         now.Format(time.RFC3339),
		PowerDelaySeconds: defaultPowerDelay,
		RateLimit:         RateLimit{RequestsPerSecond: defaultRPS, Burst: defaultBurst},
		LogLevel:          defaultLogLevel,
	}
}

func laptopNameFrom(hostname string) string {
	runes := []rune(hostname)
	if len(runes) == 0 {
		return defaultLaptopName
	}
	if len(runes) > maxLaptopNameRunes {
		runes = runes[:maxLaptopNameRunes]
	}
	return string(runes)
}

// Load reads the file at path into a copy of defaults, so fields missing
// from the file keep their default values. Unknown fields are ignored.
// The returned error wraps fs.ErrNotExist when the file does not exist.
func Load(path string, defaults Config) (Config, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return Config{}, fmt.Errorf("read config %s: %w", path, err)
	}
	c := defaults
	if err := json.NewDecoder(bytes.NewReader(data)).Decode(&c); err != nil {
		return Config{}, fmt.Errorf("parse config %s: %w", path, err)
	}
	if err := Validate(c); err != nil {
		return Config{}, err
	}
	return c, nil
}

// Save validates c and writes it atomically to path: it writes a temporary
// file in the same folder, syncs it, and renames it over the target. An
// invalid config writes nothing.
func Save(path string, c Config) error {
	if err := Validate(c); err != nil {
		return err
	}
	data, err := json.MarshalIndent(c, "", "  ")
	if err != nil {
		return fmt.Errorf("encode config: %w", err)
	}
	data = append(data, '\n')

	dir := filepath.Dir(path)
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return fmt.Errorf("create config folder: %w", err)
	}
	tmp, err := os.CreateTemp(dir, "config-*.tmp")
	if err != nil {
		return fmt.Errorf("create temp config: %w", err)
	}
	tmpName := tmp.Name()
	committed := false
	defer func() {
		if !committed {
			_ = os.Remove(tmpName)
		}
	}()

	_, writeErr := tmp.Write(data)
	if writeErr == nil {
		writeErr = tmp.Sync()
	}
	if err := errors.Join(writeErr, tmp.Close()); err != nil {
		return fmt.Errorf("write temp config: %w", err)
	}
	if err := os.Rename(tmpName, path); err != nil {
		return fmt.Errorf("replace config: %w", err)
	}
	committed = true
	return nil
}
