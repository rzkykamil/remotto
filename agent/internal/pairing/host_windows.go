package pairing

import (
	"fmt"
	"net/netip"
	"unsafe"

	"golang.org/x/sys/windows"
)

// listAdapters reads the IPv4 adapter table with GetAdaptersAddresses. It is
// a read-only query. Only adapters with IPv4 unicast addresses are returned.
func listAdapters() ([]Adapter, error) {
	// Start with 15 KB, the size Microsoft recommends, and grow on overflow.
	// The buffer is []uint64 so it is 8-byte aligned for the struct cast.
	size := uint32(15 * 1024)
	var buf []uint64
	for range 3 {
		buf = make([]uint64, (size+7)/8)
		first := (*windows.IpAdapterAddresses)(unsafe.Pointer(&buf[0]))
		err := windows.GetAdaptersAddresses(
			windows.AF_INET,
			windows.GAA_FLAG_SKIP_ANYCAST|windows.GAA_FLAG_SKIP_MULTICAST|windows.GAA_FLAG_SKIP_DNS_SERVER,
			0,
			first,
			&size,
		)
		if err == nil {
			return collectAdapters(first), nil
		}
		if err != windows.ERROR_BUFFER_OVERFLOW {
			return nil, fmt.Errorf("GetAdaptersAddresses: %w", err)
		}
	}
	return nil, fmt.Errorf("GetAdaptersAddresses: buffer kept overflowing")
}

// collectAdapters walks the linked list returned by GetAdaptersAddresses.
// The list is read while the buffer is still alive, so the caller must keep
// buf referenced until this returns.
func collectAdapters(first *windows.IpAdapterAddresses) []Adapter {
	var out []Adapter
	for aa := first; aa != nil; aa = aa.Next {
		a := Adapter{
			Name:       windows.UTF16PtrToString(aa.FriendlyName),
			Up:         aa.OperStatus == windows.IfOperStatusUp,
			HasGateway: aa.FirstGatewayAddress != nil,
		}
		for u := aa.FirstUnicastAddress; u != nil; u = u.Next {
			ip, ok := netip.AddrFromSlice(u.Address.IP())
			if ok && ip.Is4() {
				a.IPv4 = append(a.IPv4, ip)
			}
		}
		if len(a.IPv4) > 0 {
			out = append(out, a)
		}
	}
	return out
}
