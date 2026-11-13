package discovery

import (
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"log/slog"
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

// BR-22 / discovery-flow: the agent logs while it advertises, so the log
// output must hold no token material on any path: normal run, disabled,
// invalid agent id, register failure, list failure, interface gone and back,
// and stop. The config that holds the token is passed in, but Run receives
// only the agent id and the name, so the buffer must stay clean.
func TestBR22_RunLogsHaveNoTokenMaterial(t *testing.T) {
	forbidden := forbiddenStrings()
	cfg := config.Default("LAPTOP-KANTOR", time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC))
	cfg.Token = secretToken
	cfg.TokenCreatedAt = "2026-01-01T00:00:00Z"
	cfg.AgentID = testAgentID

	lan := func() []Iface {
		return []Iface{lanIface("Wi-Fi", 3, "192.168.1.10")}
	}
	cases := []struct {
		name string
		// setup adjusts the options or the fakes before Run starts.
		setup func(o *Options, h *runHarness)
		// drive runs the scenario; it must end with Run stopped.
		drive func(h *runHarness)
	}{
		{
			name:  "normal run and stop",
			setup: func(o *Options, h *runHarness) { h.lister.set(lan(), nil) },
			drive: func(h *runHarness) {
				h.start()
				h.park()
				h.poll()
				h.stop()
			},
		},
		{
			name:  "discovery disabled",
			setup: func(o *Options, h *runHarness) { o.Enabled = false },
			drive: func(h *runHarness) {
				h.start()
				h.waitDone()
			},
		},
		{
			name:  "agent id invalid",
			setup: func(o *Options, h *runHarness) { o.AgentID = strings.ToUpper(testAgentID) },
			drive: func(h *runHarness) {
				h.start()
				h.waitDone()
			},
		},
		{
			name: "register fails",
			setup: func(o *Options, h *runHarness) {
				h.reg.failNext = 3
				h.lister.set(lan(), nil)
			},
			drive: func(h *runHarness) {
				h.start()
				h.park()
				h.poll()
				h.poll()
				h.stop()
			},
		},
		{
			name:  "list fails",
			setup: func(o *Options, h *runHarness) { h.lister.set(nil, errors.New("fake list failure")) },
			drive: func(h *runHarness) {
				h.start()
				h.park()
				h.poll()
				h.stop()
			},
		},
		{
			name:  "interface gone and back",
			setup: func(o *Options, h *runHarness) { h.lister.set(lan(), nil) },
			drive: func(h *runHarness) {
				h.start()
				h.park()
				h.lister.set(nil, nil)
				h.poll()
				h.lister.set(lan(), nil)
				h.poll()
				h.stop()
			},
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			o := testOptions()
			o.AgentID = cfg.AgentID
			o.Name = cfg.LaptopName
			buf := &syncBuffer{}
			o.Logger = slog.New(slog.NewTextHandler(buf, &slog.HandlerOptions{Level: slog.LevelDebug}))
			h := newHarness(t, o)
			tc.setup(&h.opts, h)
			tc.drive(h)

			logs := buf.String()
			if logs == "" {
				t.Fatal("log buffer is empty, the scenario logged nothing to check")
			}
			assertNoSecret(t, "log output", logs, forbidden)
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
