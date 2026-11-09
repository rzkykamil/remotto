//go:build !windows

package pairing

import (
	"net"
	"net/netip"
)

// listAdapters lists local interfaces with the net package. Only private
// IPv4 addresses are kept. Gateway detection is not implemented here, so
// HasGateway stays false and SelectHost needs --host on these systems. The
// agent targets Windows; this file exists so the package builds and tests
// run elsewhere.
func listAdapters() ([]Adapter, error) {
	ifaces, err := net.Interfaces()
	if err != nil {
		return nil, err
	}
	var out []Adapter
	for _, ifc := range ifaces {
		addrs, err := ifc.Addrs()
		if err != nil {
			return nil, err
		}
		a := Adapter{
			Name: ifc.Name,
			Up:   ifc.Flags&net.FlagUp != 0,
		}
		for _, addr := range addrs {
			ipNet, ok := addr.(*net.IPNet)
			if !ok {
				continue
			}
			ip, ok := netip.AddrFromSlice(ipNet.IP)
			if !ok {
				continue
			}
			if ip = ip.Unmap(); isLANAddr(ip) {
				a.IPv4 = append(a.IPv4, ip)
			}
		}
		if len(a.IPv4) > 0 {
			out = append(out, a)
		}
	}
	return out, nil
}
