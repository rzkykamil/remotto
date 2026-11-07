package pairing

import (
	"errors"
	"net/netip"
	"strings"
	"testing"
)

func addr(t *testing.T, s string) netip.Addr {
	t.Helper()
	a, err := netip.ParseAddr(s)
	if err != nil {
		t.Fatalf("ParseAddr(%q) error = %v", s, err)
	}
	return a
}

func TestSelectHost(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name     string
		adapters []Adapter
		want     string // empty means ErrNoHostCandidate
	}{
		{
			name: "single up adapter with gateway",
			adapters: []Adapter{
				{Name: "Wi-Fi", Up: true, HasGateway: true, IPv4: []netip.Addr{addr(t, "192.168.1.10")}},
			},
			want: "192.168.1.10",
		},
		{
			name: "WSL adapter without gateway is skipped",
			adapters: []Adapter{
				{Name: "vEthernet (WSL)", Up: true, HasGateway: false, IPv4: []netip.Addr{addr(t, "172.20.144.1")}},
				{Name: "Wi-Fi", Up: true, HasGateway: true, IPv4: []netip.Addr{addr(t, "192.168.1.10")}},
			},
			want: "192.168.1.10",
		},
		{
			name: "down adapter with gateway is skipped",
			adapters: []Adapter{
				{Name: "Ethernet", Up: false, HasGateway: true, IPv4: []netip.Addr{addr(t, "10.0.0.5")}},
				{Name: "Wi-Fi", Up: true, HasGateway: true, IPv4: []netip.Addr{addr(t, "192.168.1.10")}},
			},
			want: "192.168.1.10",
		},
		{
			name: "first matching adapter in input order wins",
			adapters: []Adapter{
				{Name: "Ethernet", Up: true, HasGateway: true, IPv4: []netip.Addr{addr(t, "10.0.0.5")}},
				{Name: "Wi-Fi", Up: true, HasGateway: true, IPv4: []netip.Addr{addr(t, "192.168.1.10")}},
			},
			want: "10.0.0.5",
		},
		{
			name: "public address with gateway is not a candidate",
			adapters: []Adapter{
				{Name: "Cellular", Up: true, HasGateway: true, IPv4: []netip.Addr{addr(t, "8.8.8.8")}},
			},
			want: "",
		},
		{
			name: "tailscale range is not picked automatically",
			adapters: []Adapter{
				{Name: "Tailscale", Up: true, HasGateway: true, IPv4: []netip.Addr{addr(t, "100.101.102.103")}},
			},
			want: "",
		},
		{
			name: "boundary 172.16/12 accepted, 172.32 rejected",
			adapters: []Adapter{
				{Name: "a", Up: true, HasGateway: true, IPv4: []netip.Addr{addr(t, "172.32.0.1")}},
				{Name: "b", Up: true, HasGateway: true, IPv4: []netip.Addr{addr(t, "172.31.255.1")}},
			},
			want: "172.31.255.1",
		},
		{
			name: "second address of an adapter is used when first is public",
			adapters: []Adapter{
				{Name: "Wi-Fi", Up: true, HasGateway: true, IPv4: []netip.Addr{addr(t, "203.0.113.7"), addr(t, "192.168.0.20")}},
			},
			want: "192.168.0.20",
		},
		{
			name:     "no adapters",
			adapters: nil,
			want:     "",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()

			got, err := SelectHost(tt.adapters)
			if tt.want == "" {
				if !errors.Is(err, ErrNoHostCandidate) {
					t.Fatalf("SelectHost() error = %v, want ErrNoHostCandidate", err)
				}
				return
			}
			if err != nil {
				t.Fatalf("SelectHost() error = %v", err)
			}
			if got != addr(t, tt.want) {
				t.Fatalf("SelectHost() = %v, want %s", got, tt.want)
			}
		})
	}
}

func TestSelectHostNoCandidateSuggestsOverride(t *testing.T) {
	t.Parallel()

	_, err := SelectHost([]Adapter{{Name: "WSL", Up: true, IPv4: []netip.Addr{addr(t, "172.20.144.1")}}})
	if !errors.Is(err, ErrNoHostCandidate) {
		t.Fatalf("SelectHost() error = %v, want ErrNoHostCandidate", err)
	}
	if got := err.Error(); !strings.Contains(got, "--host") {
		t.Fatalf("error message %q does not mention --host", got)
	}
}

func TestValidateHostOverride(t *testing.T) {
	t.Parallel()

	valid := []string{"192.168.1.10", "10.0.0.1", "172.16.0.1", "172.31.255.254", "100.64.0.1", "100.127.255.254"}
	for _, s := range valid {
		t.Run("valid "+s, func(t *testing.T) {
			t.Parallel()

			got, err := ValidateHostOverride(s)
			if err != nil {
				t.Fatalf("ValidateHostOverride(%q) error = %v", s, err)
			}
			if got.String() != s {
				t.Fatalf("ValidateHostOverride(%q) = %v", s, got)
			}
		})
	}

	invalid := []string{
		"",
		"8.8.8.8",
		"127.0.0.1",
		"172.15.0.1",
		"172.32.0.1",
		"100.63.255.255",
		"100.128.0.1",
		"laptop.local",
		"fd00::1",
		"::ffff:192.168.1.10",
		"192.168.1.10:8765",
		" 192.168.1.10",
		"192.168.1",
	}
	for _, s := range invalid {
		t.Run("invalid "+s, func(t *testing.T) {
			t.Parallel()

			_, err := ValidateHostOverride(s)
			if !errors.Is(err, ErrInvalidHost) {
				t.Fatalf("ValidateHostOverride(%q) error = %v, want ErrInvalidHost", s, err)
			}
		})
	}
}
