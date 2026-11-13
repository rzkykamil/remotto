//go:build manual

package discovery

import (
	"context"
	"regexp"
	"strings"
	"testing"
	"time"

	"github.com/grandcat/zeroconf"
)

// TestManualAdvertiseAndBrowse advertises the agent on the real LAN with
// multicast DNS and browses for it. It is not run automatically: it needs a
// network that allows multicast and UDP 5353. Run it by hand with
//
//	go test -tags manual ./internal/discovery -run Manual -v
func TestManualAdvertiseAndBrowse(t *testing.T) {
	const port = 8765
	agentID := strings.Repeat("0123456789abcdef", 2)
	token64 := regexp.MustCompile(`[0-9a-f]{64}`)

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	done := make(chan struct{})
	go func() {
		defer close(done)
		Run(ctx, Options{
			Enabled:   true,
			AgentID:   agentID,
			Name:      "manual-test",
			Port:      port,
			Interval:  time.Second,
			Registrar: ZeroconfRegistrar{},
			Lister:    SystemLister{},
		})
	}()

	resolver, err := zeroconf.NewResolver()
	if err != nil {
		t.Fatalf("new resolver: %v", err)
	}
	bctx, bcancel := context.WithTimeout(ctx, 5*time.Second)
	defer bcancel()
	entries := make(chan *zeroconf.ServiceEntry)
	if err := resolver.Browse(bctx, ServiceType, Domain, entries); err != nil {
		t.Fatalf("browse: %v", err)
	}

	want := InstanceName(agentID)
	var found *zeroconf.ServiceEntry
	for found == nil {
		select {
		case e := <-entries:
			if e != nil && e.Instance == want {
				found = e
			}
		case <-bctx.Done():
			t.Fatalf("instance %q not seen within 5s; check firewall UDP 5353 and that the LAN allows multicast", want)
		}
	}

	if found.Port != port {
		t.Errorf("port = %d, want %d", found.Port, port)
	}
	gotID := ""
	for _, kv := range found.Text {
		key, val, _ := strings.Cut(kv, "=")
		switch key {
		case "v":
			if val != TXTVersion {
				t.Errorf("TXT v = %q, want %q", val, TXTVersion)
			}
		case "id":
			gotID = val
		case "name":
		default:
			t.Errorf("unexpected TXT key %q", key)
		}
		if token64.MatchString(kv) {
			t.Errorf("TXT entry %q contains a 64-hex value", key)
		}
	}
	if gotID != agentID {
		t.Errorf("TXT id = %q, want %q", gotID, agentID)
	}

	cancel()
	select {
	case <-done:
	case <-time.After(5 * time.Second):
		t.Fatal("Run did not return after cancel")
	}
}
