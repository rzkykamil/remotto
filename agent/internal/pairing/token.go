// Package pairing holds the token, host selection, and QR payload logic
// used to pair the phone with the agent over the LAN.
package pairing

import (
	"encoding/hex"
	"fmt"
	"io"
	"regexp"
)

// tokenBytes is the entropy size of a token: 256 bits.
const tokenBytes = 32

// tokenPattern matches a token: 64 lowercase hex characters.
var tokenPattern = regexp.MustCompile(`^[0-9a-f]{64}$`)

// GenerateToken reads tokenBytes bytes from r and returns them as 64
// lowercase hex characters. Callers pass crypto/rand.Reader in production.
// On a short or failed read it returns an error and no partial token.
func GenerateToken(r io.Reader) (string, error) {
	buf := make([]byte, tokenBytes)
	if _, err := io.ReadFull(r, buf); err != nil {
		return "", fmt.Errorf("read token entropy: %w", err)
	}
	return hex.EncodeToString(buf), nil
}

// ValidToken reports whether s has the token format: 64 lowercase hex
// characters. It does not compare against any stored token.
func ValidToken(s string) bool {
	return tokenPattern.MatchString(s)
}
