package config

import (
	"errors"
	"io/fs"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
	"time"
)

var fixedNow = time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC)

const validToken = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

func writeFile(t *testing.T, path, content string) {
	t.Helper()
	if err := os.WriteFile(path, []byte(content), 0o600); err != nil {
		t.Fatalf("write fixture: %v", err)
	}
}

func TestDefault(t *testing.T) {
	tests := []struct {
		name     string
		hostname string
		want     string
	}{
		{name: "normal hostname", hostname: "DESKTOP-ABC", want: "DESKTOP-ABC"},
		{name: "empty hostname falls back", hostname: "", want: "Laptop"},
		{name: "100 ascii chars truncated to 64", hostname: strings.Repeat("a", 100), want: strings.Repeat("a", 64)},
		{name: "100 multibyte runes truncated to 64 runes", hostname: strings.Repeat("é", 100), want: strings.Repeat("é", 64)},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			c := Default(tt.hostname, fixedNow)
			if c.LaptopName != tt.want {
				t.Fatalf("LaptopName = %q, want %q", c.LaptopName, tt.want)
			}
			if err := Validate(c); err != nil {
				t.Fatalf("Validate(Default) = %v, want nil", err)
			}
		})
	}
}

func TestDefaultValues(t *testing.T) {
	c := Default("PC", fixedNow)
	if c.ConfigVersion != 1 || c.Port != 8765 || c.BindAddress != "0.0.0.0" ||
		c.Token != "" || c.TokenCreatedAt != "" || c.PowerDelaySeconds != 5 ||
		c.RateLimit.RequestsPerSecond != 20 || c.RateLimit.Burst != 40 || c.LogLevel != "info" {
		t.Fatalf("unexpected defaults: %+v", c)
	}
	if c.CreatedAt != fixedNow.Format(time.RFC3339) {
		t.Fatalf("CreatedAt = %q", c.CreatedAt)
	}
}

// TestDefaultRateLimitAboveSliderRate guards BR-14: the slider sends at most
// one request per 100 ms (10 per second), so the default limit must leave
// headroom above that rate.
func TestDefaultRateLimitAboveSliderRate(t *testing.T) {
	const sliderRPS = 10
	c := Default("PC", fixedNow)
	if c.RateLimit.RequestsPerSecond < 2*sliderRPS {
		t.Fatalf("RateLimit.RequestsPerSecond = %d, want >= %d (2x slider rate)",
			c.RateLimit.RequestsPerSecond, 2*sliderRPS)
	}
	if c.RateLimit.Burst < c.RateLimit.RequestsPerSecond {
		t.Fatalf("RateLimit.Burst = %d, want >= RequestsPerSecond %d",
			c.RateLimit.Burst, c.RateLimit.RequestsPerSecond)
	}
}

func TestDirUsesAppData(t *testing.T) {
	base := t.TempDir()
	t.Setenv("APPDATA", base)

	dir, err := Dir()
	if err != nil {
		t.Fatalf("Dir() error: %v", err)
	}
	if want := filepath.Join(base, "Remotto"); dir != want {
		t.Fatalf("Dir() = %q, want %q", dir, want)
	}
	p, err := DefaultPath()
	if err != nil {
		t.Fatalf("DefaultPath() error: %v", err)
	}
	if want := filepath.Join(base, "Remotto", "config.json"); p != want {
		t.Fatalf("DefaultPath() = %q, want %q", p, want)
	}
}

func TestLoadMissingFile(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.json")
	_, err := Load(path, Default("PC", fixedNow))
	if !errors.Is(err, fs.ErrNotExist) {
		t.Fatalf("Load missing file error = %v, want fs.ErrNotExist", err)
	}
}

func TestLoadPartialKeepsDefaults(t *testing.T) {
	tests := []struct {
		name    string
		content string
		check   func(t *testing.T, c Config)
	}{
		{
			name:    "only port set",
			content: `{"port": 9000}`,
			check: func(t *testing.T, c Config) {
				if c.Port != 9000 {
					t.Fatalf("Port = %d, want 9000", c.Port)
				}
				if c.PowerDelaySeconds != 5 || c.LogLevel != "info" || c.RateLimit.RequestsPerSecond != 20 {
					t.Fatalf("other fields lost defaults: %+v", c)
				}
			},
		},
		{
			name:    "partial rateLimit keeps requestsPerSecond default",
			content: `{"rateLimit":{"burst":50}}`,
			check: func(t *testing.T, c Config) {
				if c.RateLimit.RequestsPerSecond != 20 || c.RateLimit.Burst != 50 {
					t.Fatalf("RateLimit = %+v, want {20 50}", c.RateLimit)
				}
			},
		},
		{
			name:    "unknown fields are ignored",
			content: `{"port": 9000, "futureField": true, "nested": {"a": 1}}`,
			check: func(t *testing.T, c Config) {
				if c.Port != 9000 {
					t.Fatalf("Port = %d, want 9000", c.Port)
				}
			},
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			path := filepath.Join(t.TempDir(), "config.json")
			writeFile(t, path, tt.content)
			c, err := Load(path, Default("PC", fixedNow))
			if err != nil {
				t.Fatalf("Load() error: %v", err)
			}
			tt.check(t, c)
		})
	}
}

func TestLoadBrokenJSON(t *testing.T) {
	tests := []struct {
		name    string
		content string
	}{
		{name: "truncated object", content: `{"port":`},
		{name: "empty file", content: ``},
		{name: "not json", content: `hello`},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			path := filepath.Join(t.TempDir(), "config.json")
			writeFile(t, path, tt.content)
			if _, err := Load(path, Default("PC", fixedNow)); err == nil {
				t.Fatal("Load() error = nil, want error")
			}
		})
	}
}

func TestLoadInvalidValueReturnsValidationError(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.json")
	writeFile(t, path, `{"port": 80}`)
	_, err := Load(path, Default("PC", fixedNow))
	var ve *ValidationError
	if !errors.As(err, &ve) {
		t.Fatalf("Load() error = %v, want *ValidationError", err)
	}
	if ve.Field != "port" {
		t.Fatalf("Field = %q, want port", ve.Field)
	}
}

func TestValidate(t *testing.T) {
	tests := []struct {
		name      string
		mutate    func(c *Config)
		wantField string // empty means valid
	}{
		{name: "default is valid", mutate: func(c *Config) {}},
		{name: "laptopName empty rejected", mutate: func(c *Config) { c.LaptopName = "" }, wantField: "laptopName"},
		{name: "laptopName 64 runes ok", mutate: func(c *Config) { c.LaptopName = strings.Repeat("x", 64) }},
		{name: "laptopName 65 runes rejected", mutate: func(c *Config) { c.LaptopName = strings.Repeat("x", 65) }, wantField: "laptopName"},
		{name: "port 1023 rejected", mutate: func(c *Config) { c.Port = 1023 }, wantField: "port"},
		{name: "port 1024 ok", mutate: func(c *Config) { c.Port = 1024 }},
		{name: "port 65535 ok", mutate: func(c *Config) { c.Port = 65535 }},
		{name: "port 65536 rejected", mutate: func(c *Config) { c.Port = 65536 }, wantField: "port"},
		{name: "bindAddress ipv6 rejected", mutate: func(c *Config) { c.BindAddress = "::1" }, wantField: "bindAddress"},
		{name: "bindAddress garbage rejected", mutate: func(c *Config) { c.BindAddress = "abc" }, wantField: "bindAddress"},
		{name: "bindAddress lan ipv4 ok", mutate: func(c *Config) { c.BindAddress = "192.168.1.5" }},
		{name: "token empty ok", mutate: func(c *Config) { c.Token = "" }},
		{name: "token 63 hex rejected", mutate: func(c *Config) { c.Token = validToken[:63] }, wantField: "token"},
		{name: "token uppercase rejected", mutate: func(c *Config) { c.Token = strings.ToUpper(validToken) }, wantField: "token"},
		{name: "token 64 lowercase hex ok", mutate: func(c *Config) { c.Token = validToken }},
		{name: "tokenCreatedAt empty ok", mutate: func(c *Config) { c.TokenCreatedAt = "" }},
		{name: "tokenCreatedAt date only rejected", mutate: func(c *Config) { c.TokenCreatedAt = "2026-01-01" }, wantField: "tokenCreatedAt"},
		{name: "createdAt garbage rejected", mutate: func(c *Config) { c.CreatedAt = "not-a-time" }, wantField: "createdAt"},
		{name: "powerDelaySeconds 4 rejected", mutate: func(c *Config) { c.PowerDelaySeconds = 4 }, wantField: "powerDelaySeconds"},
		{name: "powerDelaySeconds 5 ok", mutate: func(c *Config) { c.PowerDelaySeconds = 5 }},
		{name: "powerDelaySeconds 30 ok", mutate: func(c *Config) { c.PowerDelaySeconds = 30 }},
		{name: "powerDelaySeconds 31 rejected", mutate: func(c *Config) { c.PowerDelaySeconds = 31 }, wantField: "powerDelaySeconds"},
		{name: "requestsPerSecond 10 rejected", mutate: func(c *Config) { c.RateLimit.RequestsPerSecond = 10 }, wantField: "rateLimit.requestsPerSecond"},
		{name: "requestsPerSecond 11 ok", mutate: func(c *Config) { c.RateLimit.RequestsPerSecond = 11 }},
		{name: "requestsPerSecond 1001 rejected", mutate: func(c *Config) { c.RateLimit.RequestsPerSecond = 1001 }, wantField: "rateLimit.requestsPerSecond"},
		{name: "burst below requestsPerSecond rejected", mutate: func(c *Config) { c.RateLimit.Burst = 19 }, wantField: "rateLimit.burst"},
		{name: "burst 10001 rejected", mutate: func(c *Config) { c.RateLimit.Burst = 10001 }, wantField: "rateLimit.burst"},
		{name: "logLevel loud rejected", mutate: func(c *Config) { c.LogLevel = "loud" }, wantField: "logLevel"},
		{name: "logLevel warn ok", mutate: func(c *Config) { c.LogLevel = "warn" }},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			c := Default("PC", fixedNow)
			tt.mutate(&c)
			err := Validate(c)
			if tt.wantField == "" {
				if err != nil {
					t.Fatalf("Validate() = %v, want nil", err)
				}
				return
			}
			var ve *ValidationError
			if !errors.As(err, &ve) {
				t.Fatalf("Validate() = %v, want *ValidationError for %q", err, tt.wantField)
			}
			if ve.Field != tt.wantField {
				t.Fatalf("Field = %q, want %q", ve.Field, tt.wantField)
			}
		})
	}
}

func TestSaveLoadRoundTrip(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.json")
	want := Default("PC", fixedNow)
	want.Token = validToken
	want.TokenCreatedAt = fixedNow.Format(time.RFC3339)

	if err := Save(path, want); err != nil {
		t.Fatalf("Save() error: %v", err)
	}
	got, err := Load(path, Default("Other", fixedNow.Add(time.Hour)))
	if err != nil {
		t.Fatalf("Load() error: %v", err)
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("round trip mismatch:\n got  %+v\n want %+v", got, want)
	}
}

func TestSaveOverwritesExisting(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.json")
	first := Default("PC", fixedNow)
	second := Default("PC", fixedNow)
	second.Port = 9000

	if err := Save(path, first); err != nil {
		t.Fatalf("Save(first) error: %v", err)
	}
	if err := Save(path, second); err != nil {
		t.Fatalf("Save(second) error: %v", err)
	}
	got, err := Load(path, Default("PC", fixedNow))
	if err != nil {
		t.Fatalf("Load() error: %v", err)
	}
	if got.Port != 9000 {
		t.Fatalf("Port = %d, want 9000", got.Port)
	}
}

func TestSaveInvalidWritesNothing(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "config.json")
	writeFile(t, path, "original")

	bad := Default("PC", fixedNow)
	bad.Port = 80
	if err := Save(path, bad); err == nil {
		t.Fatal("Save(invalid) error = nil, want error")
	}

	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read after failed save: %v", err)
	}
	if string(data) != "original" {
		t.Fatalf("existing file changed to %q", data)
	}
	assertNoTempFiles(t, dir)

	missing := filepath.Join(t.TempDir(), "config.json")
	if err := Save(missing, bad); err == nil {
		t.Fatal("Save(invalid, missing) error = nil, want error")
	}
	if _, err := os.Stat(missing); !errors.Is(err, fs.ErrNotExist) {
		t.Fatalf("invalid save created file, stat err = %v", err)
	}
}

func TestSaveLeavesNoTempFiles(t *testing.T) {
	dir := filepath.Join(t.TempDir(), "sub", "deeper")
	path := filepath.Join(dir, "config.json")
	if err := Save(path, Default("PC", fixedNow)); err != nil {
		t.Fatalf("Save() error: %v", err)
	}
	if _, err := os.Stat(path); err != nil {
		t.Fatalf("config file missing after save: %v", err)
	}
	assertNoTempFiles(t, dir)
}

func assertNoTempFiles(t *testing.T, dir string) {
	t.Helper()
	entries, err := os.ReadDir(dir)
	if err != nil {
		t.Fatalf("read dir: %v", err)
	}
	for _, e := range entries {
		if strings.HasSuffix(e.Name(), ".tmp") {
			t.Fatalf("leftover temp file: %s", e.Name())
		}
	}
}
