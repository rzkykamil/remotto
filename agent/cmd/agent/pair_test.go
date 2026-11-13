package main

import (
	"bytes"
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"remotto/agent/internal/config"
	"remotto/agent/internal/discovery"
	"remotto/agent/internal/pairing"
)

// pairOut runs "pair" with an explicit config path and a fixed --host, so the
// test never reads the real adapters.
func pairOut(t *testing.T, cfgPath string, extra ...string) (code int, stdout, stderr string) {
	t.Helper()
	t.Setenv("APPDATA", t.TempDir())
	args := append([]string{"pair", "--config", cfgPath, "--host", "192.168.1.10"}, extra...)
	var out, errOut bytes.Buffer
	code = run(context.Background(), args, &out, &errOut)
	return code, out.String(), errOut.String()
}

// tokenLine returns the token value from the manual pairing text.
func tokenLine(t *testing.T, stdout string) string {
	t.Helper()
	for _, line := range strings.Split(stdout, "\n") {
		if rest, ok := strings.CutPrefix(strings.TrimSpace(line), "Token:"); ok {
			return strings.TrimSpace(rest)
		}
	}
	t.Fatalf("stdout has no Token line: %q", stdout)
	return ""
}

func TestPairFirstRunCreatesConfigAndPrintsQRAndToken(t *testing.T) {
	cfgPath := filepath.Join(t.TempDir(), "config.json")
	code, stdout, stderr := pairOut(t, cfgPath)
	if code != 0 {
		t.Fatalf("exit code = %d, want 0 (stderr %q)", code, stderr)
	}
	token := tokenLine(t, stdout)
	if !pairing.ValidToken(token) {
		t.Fatalf("token %q does not match the token format", token)
	}
	if !strings.Contains(stdout, "Alamat: 192.168.1.10") {
		t.Errorf("stdout lacks the manual host line: %q", stdout)
	}
	if !strings.Contains(stdout, "Port:   8765") {
		t.Errorf("stdout lacks the manual port line: %q", stdout)
	}
	if !strings.ContainsAny(stdout, "█▀▄") {
		t.Errorf("stdout has no QR block characters")
	}
	if _, err := os.Stat(cfgPath); err != nil {
		t.Errorf("config not created: %v", err)
	}
	if stderr != "" {
		t.Errorf("stderr = %q, want empty", stderr)
	}
}

func TestPairTwiceKeepsTokenAndConfigBytes(t *testing.T) {
	cfgPath := filepath.Join(t.TempDir(), "config.json")
	code, first, stderr := pairOut(t, cfgPath)
	if code != 0 {
		t.Fatalf("first run exit = %d (stderr %q)", code, stderr)
	}
	before, err := os.ReadFile(cfgPath)
	if err != nil {
		t.Fatal(err)
	}

	code, second, stderr := pairOut(t, cfgPath)
	if code != 0 {
		t.Fatalf("second run exit = %d (stderr %q)", code, stderr)
	}
	if tokenLine(t, first) != tokenLine(t, second) {
		t.Errorf("token changed between pair runs")
	}
	after, err := os.ReadFile(cfgPath)
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(before, after) {
		t.Errorf("config.json changed by second pair run")
	}
}

func TestPairPublicHostFailsWithoutCreatingConfig(t *testing.T) {
	cfgPath := filepath.Join(t.TempDir(), "config.json")
	t.Setenv("APPDATA", t.TempDir())
	var out, errOut bytes.Buffer
	code := run(context.Background(), []string{"pair", "--config", cfgPath, "--host", "8.8.8.8"}, &out, &errOut)
	if code != 1 {
		t.Fatalf("exit code = %d, want 1", code)
	}
	if !strings.Contains(errOut.String(), "invalid host") {
		t.Errorf("stderr = %q, want it to explain the invalid host", errOut.String())
	}
	if strings.Contains(out.String(), "Token:") {
		t.Errorf("stdout printed a token despite invalid host")
	}
	if _, err := os.Stat(cfgPath); !os.IsNotExist(err) {
		t.Errorf("config exists or stat failed (%v); invalid --host must not create it", err)
	}
}

func TestPairAcceptsTailscaleHostOverride(t *testing.T) {
	cfgPath := filepath.Join(t.TempDir(), "config.json")
	t.Setenv("APPDATA", t.TempDir())
	var out, errOut bytes.Buffer
	code := run(context.Background(), []string{"pair", "--config", cfgPath, "--host", "100.101.102.103"}, &out, &errOut)
	if code != 0 {
		t.Fatalf("exit code = %d, want 0 (stderr %q)", code, errOut.String())
	}
	if !strings.Contains(out.String(), "Alamat: 100.101.102.103") {
		t.Errorf("stdout lacks the Tailscale host: %q", out.String())
	}
}

func TestPairRejectsPositionalArgs(t *testing.T) {
	code, _, _ := runApp(t, "pair", "extra")
	if code != 2 {
		t.Fatalf("exit code = %d, want 2", code)
	}
}

// TestPairQRAndIDLineCarryConfigAgentID checks that the QR is the payload
// built with the config agentId, and that the ID line prints the same id.
func TestPairQRAndIDLineCarryConfigAgentID(t *testing.T) {
	cfgPath := filepath.Join(t.TempDir(), "config.json")
	code, stdout, stderr := pairOut(t, cfgPath)
	if code != 0 {
		t.Fatalf("exit code = %d (stderr %q)", code, stderr)
	}
	cfg, err := config.Load(cfgPath, config.Default("host", time.Now()))
	if err != nil {
		t.Fatalf("load config: %v", err)
	}
	if !discovery.ValidAgentID(cfg.AgentID) {
		t.Fatalf("config agentId %q is not valid", cfg.AgentID)
	}
	if !strings.Contains(stdout, "  ID agent: "+cfg.AgentID) {
		t.Errorf("stdout lacks the ID agent line for %q: %q", cfg.AgentID, stdout)
	}
	raw, err := pairing.BuildPayloadWithID(cfg.AgentID, cfg.LaptopName, "192.168.1.10", cfg.Port, cfg.Token)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(raw, `"id":"`+cfg.AgentID+`"`) {
		t.Fatalf("payload %q lacks the agent id", raw)
	}
	var qr bytes.Buffer
	if err := pairing.RenderQR(&qr, raw); err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(stdout, qr.String()) {
		t.Errorf("stdout QR is not the payload with the config agentId")
	}
}

// TestPairOldConfigGetsAgentIDOnceAndStays checks that a config without agentId
// gets one on the first pair, and that a second pair keeps the same id and
// leaves the file bytes unchanged.
func TestPairOldConfigGetsAgentIDOnceAndStays(t *testing.T) {
	cfgPath := filepath.Join(t.TempDir(), "config.json")
	cfg := config.Default("host", time.Now())
	cfg.Token = e2eToken
	cfg.TokenCreatedAt = "2026-01-01T00:00:00Z"
	if err := config.Save(cfgPath, cfg); err != nil {
		t.Fatalf("save config: %v", err)
	}
	if id, err := config.Load(cfgPath, config.Default("host", time.Now())); err != nil || id.AgentID != "" {
		t.Fatalf("precondition: old config agentId = %q (err %v), want empty", id.AgentID, err)
	}

	code, first, stderr := pairOut(t, cfgPath)
	if code != 0 {
		t.Fatalf("first pair exit = %d (stderr %q)", code, stderr)
	}
	if !strings.Contains(first, "ID agent dibuat.") {
		t.Errorf("first pair stdout lacks the created event: %q", first)
	}
	firstCfg, err := config.Load(cfgPath, config.Default("host", time.Now()))
	if err != nil {
		t.Fatal(err)
	}
	if !discovery.ValidAgentID(firstCfg.AgentID) {
		t.Fatalf("agentId %q after first pair is not valid", firstCfg.AgentID)
	}
	before, err := os.ReadFile(cfgPath)
	if err != nil {
		t.Fatal(err)
	}

	code, second, stderr := pairOut(t, cfgPath)
	if code != 0 {
		t.Fatalf("second pair exit = %d (stderr %q)", code, stderr)
	}
	if strings.Contains(second, "ID agent dibuat.") {
		t.Errorf("second pair created the agent id again: %q", second)
	}
	if !strings.Contains(second, "  ID agent: "+firstCfg.AgentID) {
		t.Errorf("second pair ID line differs from %q", firstCfg.AgentID)
	}
	after, err := os.ReadFile(cfgPath)
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(before, after) {
		t.Errorf("config.json changed by second pair run")
	}
}
