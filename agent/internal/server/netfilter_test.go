package server

import (
	"bytes"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

// TestBR12NetworkFilterAllowsAndRejectsSources checks which source addresses
// reach the next handler. Allowed ranges are LAN, loopback and Tailscale
// (100.64.0.0/10). Everything else gets 403 forbidden_network.
func TestBR12NetworkFilterAllowsAndRejectsSources(t *testing.T) {
	tests := []struct {
		name       string
		remoteAddr string
		allowed    bool
	}{
		{"public IPv4", "8.8.8.8:1234", false},
		{"172.15 below private range", "172.15.255.255:1234", false},
		{"172.16 start of private range", "172.16.0.1:1234", true},
		{"172.31 end of private range", "172.31.255.255:1234", true},
		{"172.32 above private range", "172.32.0.1:1234", false},
		{"10/8", "10.20.30.40:1234", true},
		{"192.168/16", "192.168.1.5:1234", true},
		{"192.169 outside 192.168/16", "192.169.1.5:1234", false},
		{"loopback 127/8", "127.0.0.1:1234", true},
		{"tailscale 100.64 start", "100.64.0.1:1234", true},
		{"tailscale 100.127 end", "100.127.255.255:1234", true},
		{"100.63 below tailscale range", "100.63.0.1:1234", false},
		{"100.128 above tailscale range", "100.128.0.1:1234", false},
		{"v4-mapped private", "[::ffff:192.168.1.5]:1234", true},
		{"v4-mapped public", "[::ffff:8.8.8.8]:1234", false},
		{"IPv6 loopback", "[::1]:1234", true},
		{"IPv6 global", "[2001:db8::1]:1234", false},
		{"IPv6 unique local", "[fd00::1]:1234", false},
		{"IPv6 link-local with zone", "[fe80::1%eth0]:1234", false},
		{"unparsable address", "garbage", false},
		{"empty address", "", false},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var buf bytes.Buffer
			called := false
			next := http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
				called = true
				w.WriteHeader(http.StatusOK)
			})
			h := Chain(next, NetworkFilter(newTestLogger(&buf)))

			req := httptest.NewRequest(http.MethodGet, "/api/v1/status", nil)
			req.RemoteAddr = tt.remoteAddr
			rec := httptest.NewRecorder()
			h.ServeHTTP(rec, req)

			if tt.allowed {
				if !called || rec.Code != http.StatusOK {
					t.Fatalf("allowed source: called=%v status=%d, want handler called with 200", called, rec.Code)
				}
				return
			}
			if called {
				t.Fatal("rejected source reached the next handler")
			}
			if rec.Code != http.StatusForbidden {
				t.Fatalf("status = %d, want 403", rec.Code)
			}
			if !strings.Contains(rec.Body.String(), `"code":"forbidden_network"`) {
				t.Fatalf("body %q does not carry code forbidden_network", rec.Body.String())
			}
		})
	}
}

// TestBR12NetworkFilterRejectionLogsIPOnly checks that the rejection log line
// carries the source IP and nothing else from the request.
func TestBR12NetworkFilterRejectionLogsIPOnly(t *testing.T) {
	var buf bytes.Buffer
	h := Chain(http.HandlerFunc(func(http.ResponseWriter, *http.Request) {}),
		NetworkFilter(newTestLogger(&buf)))

	req := httptest.NewRequest(http.MethodGet, "/api/v1/status?q=secret", nil)
	req.RemoteAddr = "8.8.8.8:4321"
	req.Header.Set("Authorization", "Bearer secrettoken")
	h.ServeHTTP(httptest.NewRecorder(), req)

	out := buf.String()
	if !strings.Contains(out, `"ip":"8.8.8.8"`) {
		t.Fatalf("log %q does not contain source ip", out)
	}
	for _, leak := range []string{"secrettoken", "Bearer", "q=secret", "4321"} {
		if strings.Contains(out, leak) {
			t.Fatalf("log %q leaks %q", out, leak)
		}
	}
}
