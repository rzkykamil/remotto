package config

import (
	"fmt"
	"net/netip"
	"regexp"
	"time"
	"unicode/utf8"
)

var tokenPattern = regexp.MustCompile(`^[0-9a-f]{64}$`)

var validLogLevels = map[string]bool{
	"debug": true,
	"info":  true,
	"warn":  true,
	"error": true,
}

// ValidationError reports the first config field that breaks a rule.
// Reason never contains the token value.
type ValidationError struct {
	Field  string
	Reason string
}

func (e *ValidationError) Error() string {
	return fmt.Sprintf("config: field %q: %s", e.Field, e.Reason)
}

func invalid(field, reason string) error {
	return &ValidationError{Field: field, Reason: reason}
}

// Validate checks every field against its range and format. It returns a
// *ValidationError for the first rule that fails, or nil.
func Validate(c Config) error {
	if c.ConfigVersion != CurrentVersion {
		return invalid("configVersion", fmt.Sprintf("unsupported version %d, this agent supports %d", c.ConfigVersion, CurrentVersion))
	}
	if n := utf8.RuneCountInString(c.LaptopName); n < 1 || n > maxLaptopNameRunes {
		return invalid("laptopName", "must be 1-64 characters")
	}
	if c.Port < 1024 || c.Port > 65535 {
		return invalid("port", "must be 1024-65535")
	}
	addr, err := netip.ParseAddr(c.BindAddress)
	if err != nil || !addr.Is4() {
		return invalid("bindAddress", "must be an IPv4 address")
	}
	if c.Token != "" && !tokenPattern.MatchString(c.Token) {
		return invalid("token", "must be 64 lowercase hex characters")
	}
	if err := checkTimestamp("tokenCreatedAt", c.TokenCreatedAt); err != nil {
		return err
	}
	if err := checkTimestamp("createdAt", c.CreatedAt); err != nil {
		return err
	}
	if c.PowerDelaySeconds < 5 || c.PowerDelaySeconds > 30 {
		return invalid("powerDelaySeconds", "must be 5-30")
	}
	if c.RateLimit.RequestsPerSecond <= 10 || c.RateLimit.RequestsPerSecond > 1000 {
		return invalid("rateLimit.requestsPerSecond", "must be 11-1000")
	}
	if c.RateLimit.Burst < c.RateLimit.RequestsPerSecond || c.RateLimit.Burst > 10000 {
		return invalid("rateLimit.burst", "must be between requestsPerSecond and 10000")
	}
	if !validLogLevels[c.LogLevel] {
		return invalid("logLevel", "must be one of debug, info, warn, error")
	}
	return nil
}

// checkTimestamp accepts an empty value (before first run) or RFC 3339.
func checkTimestamp(field, value string) error {
	if value == "" {
		return nil
	}
	if _, err := time.Parse(time.RFC3339, value); err != nil {
		return invalid(field, "must be RFC 3339 timestamp")
	}
	return nil
}
