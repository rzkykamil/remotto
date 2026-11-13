package discovery

import (
	"crypto/sha256"
	"encoding/hex"
	"regexp"
	"strings"
	"testing"
	"time"

	"remotto/agent/internal/config"
)

// secretToken is a 64-hex token in the shape the agent generates. The tests
// check that neither it nor its SHA-256 hex ever reaches an advertisement.
var secretToken = strings.Repeat("7e", 32)

// hex64Pattern matches any run of 64 hex characters, the token length. A
// name that merely looks like a token must not leak one through the TXT
// records either.
var hex64Pattern = regexp.MustCompile(`[0-9a-fA-F]{64}`)

// tokenLookalikeName is a laptop name that contains a 64-hex string which is
// not the real token. BuildTXT must cut it below 64 characters.
var tokenLookalikeName = "Laptop-" + strings.Repeat("9d", 32)

// forbiddenStrings returns the values that must not appear in any advertised
// field: the token itself and its SHA-256 in hex, lower and upper case.
func forbiddenStrings() []string {
	sum := sha256.Sum256([]byte(secretToken))
	digest := hex.EncodeToString(sum[:])
	return []string{
		secretToken,
		strings.ToUpper(secretToken),
		digest,
		strings.ToUpper(digest),
	}
}

// assertNoSecret fails when s contains a forbidden value or a 64-hex run.
func assertNoSecret(t *testing.T, field, s string, forbidden []string) {
	t.Helper()
	for _, f := range forbidden {
		if strings.Contains(s, f) {
			t.Errorf("%s = %q contains token material %q", field, s, f)
		}
	}
	if m := hex64Pattern.FindString(s); m != "" {
		t.Errorf("%s = %q contains a 64-hex run", field, s)
	}
}

// BR-22 / discovery-flow: the TXT records carry only v, id and name. The
// token and its hash never appear, even when the name looks like a token.
func TestBR22_BuildTXTNeverCarriesTokenMaterial(t *testing.T) {
	forbidden := forbiddenStrings()
	ids := []string{
		testAgentID,
		"fedcba9876543210fedcba9876543210",
		"00000000000000000000000000000000",
	}
	names := []string{
		"",
		"Laptop Kantor",
		tokenLookalikeName,
		strings.Repeat(secretToken, 2),
		"Laptop Kantor 🚀 " + strings.Repeat("x", 40),
	}
	for _, id := range ids {
		for _, name := range names {
			txt := BuildTXT(id, name)
			for _, entry := range txt {
				assertNoSecret(t, "TXT entry", entry, forbidden)
				key, _, _ := strings.Cut(entry, "=")
				switch key {
				case "v", "id", "name":
				default:
					t.Errorf("TXT key %q is not allowed (entry %q)", key, entry)
				}
			}
		}
	}
}

// BR-22 / discovery-flow: a full run with the config defaults and a token
// advertises nothing that contains the token. The instance, hostname, TXT
// records, addresses and interface names are all checked.
func TestBR22_RunAdvertisementHasNoToken(t *testing.T) {
	forbidden := forbiddenStrings()
	cfg := config.Default("LAPTOP-KANTOR", time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC))
	cfg.Token = secretToken
	cfg.TokenCreatedAt = "2026-01-01T00:00:00Z"

	cases := []struct {
		name    string
		agentID string
		laptop  string
	}{
		{"config defaults", testAgentID, cfg.LaptopName},
		{"lookalike name", "fedcba9876543210fedcba9876543210", tokenLookalikeName},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			o := testOptions()
			o.AgentID = tc.agentID
			o.Name = tc.laptop
			h := newHarness(t, o)
			h.lister.set([]Iface{
				lanIface("Wi-Fi", 3, "192.168.1.10"),
				lanIface("Ethernet", 4, "10.0.0.5"),
			}, nil)
			h.start()
			h.park()
			h.stop()

			services := h.reg.serviceList()
			if len(services) != 1 {
				t.Fatalf("Register calls = %d, want 1", len(services))
			}
			svc := services[0]
			assertNoSecret(t, "Instance", svc.Instance, forbidden)
			assertNoSecret(t, "hostName", hostName(svc.Instance), forbidden)
			for _, entry := range svc.TXT {
				assertNoSecret(t, "TXT entry", entry, forbidden)
			}
			for _, ip := range svc.IPs {
				assertNoSecret(t, "IP", ip.String(), forbidden)
			}
			for _, ifc := range svc.Ifaces {
				assertNoSecret(t, "interface name", ifc.Name, forbidden)
			}
			// The name key must still be present, cut to 32 runes, so the
			// check above is not passing because the name was dropped.
			want := "name=" + truncateRunes(tc.laptop, maxNameRunes)
			if !containsEntry(svc.TXT, want) {
				t.Errorf("TXT = %v, want entry %q", svc.TXT, want)
			}
		})
	}
}

// containsEntry reports whether entries holds want exactly.
func containsEntry(entries []string, want string) bool {
	for _, e := range entries {
		if e == want {
			return true
		}
	}
	return false
}
