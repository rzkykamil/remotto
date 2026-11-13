package discovery

import (
	"fmt"
	"net"
	"net/netip"

	"remotto/agent/internal/pairing"
)

// SystemLister reports the local interfaces by joining pairing.ListAdapters
// (gateway and IPv4 data) with net.Interfaces (multicast and loopback flags).
// It only reads state.
type SystemLister struct{}

// List returns one Iface per adapter that also appears in net.Interfaces.
// Adapters without a matching interface are skipped. Matching is by name: on
// Windows, net.Interface.Name is the adapter FriendlyName.
func (SystemLister) List() ([]Iface, error) {
	adapters, err := pairing.ListAdapters()
	if err != nil {
		return nil, fmt.Errorf("list adapters: %w", err)
	}
	ifaces, err := net.Interfaces()
	if err != nil {
		return nil, fmt.Errorf("list interfaces: %w", err)
	}
	byName := make(map[string]net.Interface, len(ifaces))
	for _, ni := range ifaces {
		byName[ni.Name] = ni
	}
	out := make([]Iface, 0, len(adapters))
	for _, a := range adapters {
		ni, ok := byName[a.Name]
		if !ok {
			continue
		}
		out = append(out, Iface{
			Name:       a.Name,
			Up:         a.Up,
			Multicast:  ni.Flags&net.FlagMulticast != 0,
			Loopback:   ni.Flags&net.FlagLoopback != 0,
			HasGateway: a.HasGateway,
			IPv4:       append([]netip.Addr(nil), a.IPv4...),
			Raw:        ni,
		})
	}
	return out, nil
}
