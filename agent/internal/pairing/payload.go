package pairing

import (
	"encoding/json"
	"errors"
	"fmt"
	"regexp"
	"strings"
	"unicode/utf8"
)

// PayloadVersion is the schema version of the QR payload (data-design §5).
const PayloadVersion = 1

// maxPayloadNameRunes caps the laptop name in the QR so the code stays small.
const maxPayloadNameRunes = 32

// agentIDPattern matches a valid agentId: 32 lowercase hex characters.
var agentIDPattern = regexp.MustCompile(`^[0-9a-f]{32}$`)

// ErrInvalidPayload means the pairing data cannot form a valid payload.
var ErrInvalidPayload = errors.New("invalid pairing payload")

// payload is the wire form of the QR content. Field order fixes the JSON
// output: v, id, name, host, port, token. The id field is omitted when empty.
type payload struct {
	V     int    `json:"v"`
	ID    string `json:"id,omitempty"`
	Name  string `json:"name"`
	Host  string `json:"host"`
	Port  int    `json:"port"`
	Token string `json:"token"`
}

// BuildPayload returns the one-line JSON payload without an agent id. It is
// kept for callers that have no agentId yet.
func BuildPayload(name, host string, port int, token string) (string, error) {
	return BuildPayloadWithID("", name, host, port, token)
}

// BuildPayloadWithID returns the one-line JSON payload that the app scans. When
// agentID is not empty it must match the agentId format and is written as id.
// The name is cut to 32 runes without splitting UTF-8 sequences. The host must
// be an allowed LAN or Tailscale IPv4 address and the token must have the token
// format. Errors never include the token or the agent id value.
func BuildPayloadWithID(agentID, name, host string, port int, token string) (string, error) {
	if agentID != "" && !agentIDPattern.MatchString(agentID) {
		return "", fmt.Errorf("%w: agent id format", ErrInvalidPayload)
	}
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
		ID:    agentID,
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
