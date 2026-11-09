package pairing

import (
	"errors"
	"fmt"
	"net/netip"
)

// ErrNoHostCandidate means no active adapter with a gateway has a private
// IPv4 address. The user can pass --host to choose the address by hand.
var ErrNoHostCandidate = errors.New("no LAN address found: pass --host <ipv4> to choose one")

// ErrInvalidHost means a --host override is not an allowed address.
var ErrInvalidHost = errors.New("invalid host: use a private IPv4 address (10/8, 172.16/12, 192.168/16) or Tailscale 100.64/10")

// Adapter is a network adapter as seen by host selection. It is plain data
// so that selection can be tested without touching the OS.
type Adapter struct {
	Name       string
	Up         bool
	HasGateway bool
	IPv4       []netip.Addr
}

// lanPrefixes are the private IPv4 ranges used for LAN host candidates.
var lanPrefixes = []netip.Prefix{
	netip.MustParsePrefix("10.0.0.0/8"),
	netip.MustParsePrefix("172.16.0.0/12"),
	netip.MustParsePrefix("192.168.0.0/16"),
}

// tailscalePrefix is the CGNAT range used by Tailscale. It is only accepted
// as a --host override, never picked automatically.
var tailscalePrefix = netip.MustParsePrefix("100.64.0.0/10")

// SelectHost returns the first IPv4 address of an up adapter that has a
// default gateway and a private LAN address. Adapters are checked in the
// order given, so the result is stable for the same input. Virtual adapters
// such as WSL or Hyper-V normally have no gateway and are skipped.
func SelectHost(adapters []Adapter) (netip.Addr, error) {
	for _, a := range adapters {
		if !a.Up || !a.HasGateway {
			continue
		}
		for _, addr := range a.IPv4 {
			if isLANAddr(addr) {
				return addr, nil
			}
		}
	}
	return netip.Addr{}, ErrNoHostCandidate
}

// ValidateHostOverride checks a --host value. It accepts a plain IPv4 address
// in the private LAN ranges or in the Tailscale range. Hostnames, IPv6 and
// public addresses are rejected.
func ValidateHostOverride(s string) (netip.Addr, error) {
	addr, err := netip.ParseAddr(s)
	if err != nil || !addr.Is4() {
		return netip.Addr{}, fmt.Errorf("%w: %q", ErrInvalidHost, s)
	}
	if !isLANAddr(addr) && !tailscalePrefix.Contains(addr) {
		return netip.Addr{}, fmt.Errorf("%w: %q", ErrInvalidHost, s)
	}
	return addr, nil
}

// DetectHost lists the local adapters and selects the LAN host. The listing
// is read-only.
func DetectHost() (netip.Addr, error) {
	adapters, err := listAdapters()
	if err != nil {
		return netip.Addr{}, fmt.Errorf("list network adapters: %w", err)
	}
	return SelectHost(adapters)
}

// isLANAddr reports whether addr is an IPv4 address in one of the private
// LAN ranges.
func isLANAddr(addr netip.Addr) bool {
	if !addr.Is4() {
		return false
	}
	for _, p := range lanPrefixes {
		if p.Contains(addr) {
			return true
		}
	}
	return false
}
