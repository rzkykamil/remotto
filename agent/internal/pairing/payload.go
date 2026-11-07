package pairing

import (
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"unicode/utf8"
)

// PayloadVersion is the schema version of the QR payload (data-design §5).
const PayloadVersion = 1

// maxPayloadNameRunes caps the laptop name in the QR so the code stays small.
const maxPayloadNameRunes = 32

// ErrInvalidPayload means the pairing data cannot form a valid payload.
var ErrInvalidPayload = errors.New("invalid pairing payload")

// payload is the wire form of the QR content. Field order fixes the JSON
// output: v, name, host, port, token.
type payload struct {
	V     int    `json:"v"`
	Name  string `json:"name"`
	Host  string `json:"host"`
	Port  int    `json:"port"`
	Token string `json:"token"`
}

// BuildPayload returns the one-line JSON payload that the app scans. The name
// is cut to 32 runes without splitting UTF-8 sequences. The host must be an
// allowed LAN or Tailscale IPv4 address and the token must have the token
// format. Errors never include the token value.
func BuildPayload(name, host string, port int, token string) (string, error) {
	if !ValidToken(token) {
		return "", fmt.Errorf("%w: token format", ErrInvalidPayload)
	}
	if port < 1 || port > 65535 {
		return "", fmt.Errorf("%w: port %d out of range", ErrInvalidPayload, port)
	}
	addr, err := ValidateHostOverride(host)
	if err != nil {
		return "", fmt.Errorf("%w: %w", ErrInvalidPayload, err)
	}
	name = truncateRunes(strings.TrimSpace(name), maxPayloadNameRunes)
	if name == "" {
		return "", fmt.Errorf("%w: empty laptop name", ErrInvalidPayload)
	}

	raw, err := json.Marshal(payload{
		V:     PayloadVersion,
		Name:  name,
		Host:  addr.String(),
		Port:  port,
		Token: token,
	})
	if err != nil {
		return "", fmt.Errorf("encode payload: %w", err)
	}
	return string(raw), nil
}

// truncateRunes returns at most max runes of s. It never splits a rune.
func truncateRunes(s string, max int) string {
	if utf8.RuneCountInString(s) <= max {
		return s
	}
	runes := []rune(s)
	return string(runes[:max])
}
