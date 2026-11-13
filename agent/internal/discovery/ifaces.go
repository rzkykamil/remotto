package discovery

import (
	"net"
	"net/netip"
	"sort"
	"strings"

	"remotto/agent/internal/pairing"
)

// Iface is a network interface as seen by the advertiser. It is plain data so
// that the selection rules can be tested without touching the OS. Raw carries
// the original net.Interface for the registrar.
type Iface struct {
	Name       string
	Up         bool
	Multicast  bool
	Loopback   bool
	HasGateway bool
	IPv4       []netip.Addr
	Raw        net.Interface
}

// SelectInterfaces returns the interfaces to advertise on. An interface must be
// up, multicast-capable, not loopback, and have a default gateway. Only its
// private LAN IPv4 addresses are kept, so WSL, Hyper-V, Tailscale (100.64/10),
// public and IPv6 addresses are never advertised. The result is sorted by name
// and then by address, so the same set of interfaces always gives the same
// order. The input is not modified.
func SelectInterfaces(in []Iface) []Iface {
	out := make([]Iface, 0, len(in))
	for _, f := range in {
		if !f.Up || !f.Multicast || f.Loopback || !f.HasGateway {
			continue
		}
		var lan []netip.Addr
		for _, a := range f.IPv4 {
			if pairing.IsLANAddr(a) {
				lan = append(lan, a)
			}
		}
		if len(lan) == 0 {
			continue
		}
		sortAddrs(lan)
		f.IPv4 = lan
		out = append(out, f)
	}
	sort.SliceStable(out, func(i, j int) bool {
		if out[i].Name != out[j].Name {
			return out[i].Name < out[j].Name
		}
		return addrKey(out[i]) < addrKey(out[j])
	})
	return out
}

// Signature returns a deterministic key for a set of interfaces: their names
// and sorted addresses. The advertiser compares it between polls to detect a
// change. The input order does not affect the result.
func Signature(in []Iface) string {
	keys := make([]string, 0, len(in))
	for _, f := range in {
		keys = append(keys, f.Name+"="+addrKey(f))
	}
	sort.Strings(keys)
	return strings.Join(keys, ";")
}

// addrKey joins the interface's IPv4 addresses in sorted order.
func addrKey(f Iface) string {
	addrs := make([]netip.Addr, len(f.IPv4))
	copy(addrs, f.IPv4)
	sortAddrs(addrs)
	parts := make([]string, 0, len(addrs))
	for _, a := range addrs {
		parts = append(parts, a.String())
	}
	return strings.Join(parts, ",")
}

// sortAddrs sorts addresses in place by their numeric value.
func sortAddrs(addrs []netip.Addr) {
	sort.Slice(addrs, func(i, j int) bool { return addrs[i].Compare(addrs[j]) < 0 })
}
