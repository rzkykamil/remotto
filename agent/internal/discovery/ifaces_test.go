package discovery

import (
	"net/netip"
	"reflect"
	"testing"
)

func addr(s string) netip.Addr { return netip.MustParseAddr(s) }

// wifi is a typical active WiFi adapter on a home LAN.
func wifi() Iface {
	return Iface{
		Name: "Wi-Fi", Up: true, Multicast: true, HasGateway: true,
		IPv4: []netip.Addr{addr("192.168.1.10")},
	}
}

func TestSelectInterfaces(t *testing.T) {
	tests := []struct {
		name  string
		in    []Iface
		names []string // expected names, in order
		ips   [][]string
	}{
		{
			name:  "wifi with 192.168 and gateway is selected",
			in:    []Iface{wifi()},
			names: []string{"Wi-Fi"},
			ips:   [][]string{{"192.168.1.10"}},
		},
		{
			name: "ethernet with 10.x is selected",
			in: []Iface{{
				Name: "Ethernet", Up: true, Multicast: true, HasGateway: true,
				IPv4: []netip.Addr{addr("10.0.0.5")},
			}},
			names: []string{"Ethernet"},
			ips:   [][]string{{"10.0.0.5"}},
		},
		{
			name: "wsl 172.x without gateway is not selected",
			in: []Iface{{
				Name: "vEthernet (WSL)", Up: true, Multicast: true, HasGateway: false,
				IPv4: []netip.Addr{addr("172.20.160.1")},
			}},
			names: nil,
		},
		{
			name: "tailscale 100.x is not selected",
			in: []Iface{{
				Name: "Tailscale", Up: true, Multicast: true, HasGateway: true,
				IPv4: []netip.Addr{addr("100.101.102.103")},
			}},
			names: nil,
		},
		{
			name: "down interface is not selected",
			in: []Iface{{
				Name: "Wi-Fi", Up: false, Multicast: true, HasGateway: true,
				IPv4: []netip.Addr{addr("192.168.1.10")},
			}},
			names: nil,
		},
		{
			name: "interface without multicast is not selected",
			in: []Iface{{
				Name: "Wi-Fi", Up: true, Multicast: false, HasGateway: true,
				IPv4: []netip.Addr{addr("192.168.1.10")},
			}},
			names: nil,
		},
		{
			name: "loopback is not selected",
			in: []Iface{{
				Name: "Loopback", Up: true, Multicast: true, Loopback: true, HasGateway: true,
				IPv4: []netip.Addr{addr("127.0.0.1")},
			}},
			names: nil,
		},
		{
			name: "apipa and public addresses are not selected",
			in: []Iface{{
				Name: "Wi-Fi", Up: true, Multicast: true, HasGateway: true,
				IPv4: []netip.Addr{addr("169.254.10.20"), addr("8.8.8.8")},
			}},
			names: nil,
		},
		{
			name: "only the lan addresses of a mixed interface are kept",
			in: []Iface{{
				Name: "Wi-Fi", Up: true, Multicast: true, HasGateway: true,
				IPv4: []netip.Addr{addr("100.64.0.9"), addr("192.168.0.7")},
			}},
			names: []string{"Wi-Fi"},
			ips:   [][]string{{"192.168.0.7"}},
		},
		{
			name: "two interfaces are both selected and sorted by name",
			in: []Iface{
				wifi(),
				{
					Name: "Ethernet", Up: true, Multicast: true, HasGateway: true,
					IPv4: []netip.Addr{addr("10.0.0.5")},
				},
			},
			names: []string{"Ethernet", "Wi-Fi"},
			ips:   [][]string{{"10.0.0.5"}, {"192.168.1.10"}},
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := SelectInterfaces(tt.in)
			if len(got) != len(tt.names) {
				t.Fatalf("got %d interfaces, want %d", len(got), len(tt.names))
			}
			for i, f := range got {
				if f.Name != tt.names[i] {
					t.Errorf("iface[%d].Name = %q, want %q", i, f.Name, tt.names[i])
				}
				var ips []string
				for _, a := range f.IPv4 {
					ips = append(ips, a.String())
				}
				if !reflect.DeepEqual(ips, tt.ips[i]) {
					t.Errorf("iface[%d].IPv4 = %v, want %v", i, ips, tt.ips[i])
				}
			}
		})
	}
}

func TestSelectInterfacesStableOrder(t *testing.T) {
	a := Iface{
		Name: "Wi-Fi", Up: true, Multicast: true, HasGateway: true,
		IPv4: []netip.Addr{addr("192.168.1.20"), addr("192.168.1.10")},
	}
	b := Iface{
		Name: "Ethernet", Up: true, Multicast: true, HasGateway: true,
		IPv4: []netip.Addr{addr("10.0.0.5")},
	}
	first := SelectInterfaces([]Iface{a, b})
	second := SelectInterfaces([]Iface{b, a})
	if !reflect.DeepEqual(first, second) {
		t.Fatalf("order depends on input order:\n%v\n%v", first, second)
	}
	if got := first[1].IPv4; got[0] != addr("192.168.1.10") || got[1] != addr("192.168.1.20") {
		t.Fatalf("IPv4 not sorted: %v", got)
	}
}

func TestSelectInterfacesDoesNotModifyInput(t *testing.T) {
	in := []Iface{{
		Name: "Wi-Fi", Up: true, Multicast: true, HasGateway: true,
		IPv4: []netip.Addr{addr("100.64.0.9"), addr("192.168.0.7")},
	}}
	SelectInterfaces(in)
	if len(in[0].IPv4) != 2 || in[0].IPv4[0] != addr("100.64.0.9") {
		t.Fatalf("input was modified: %v", in[0].IPv4)
	}
}

func TestSignature(t *testing.T) {
	base := []Iface{wifi()}

	t.Run("same input gives same signature", func(t *testing.T) {
		if Signature(base) != Signature([]Iface{wifi()}) {
			t.Fatal("signature differs for identical input")
		}
	})

	t.Run("changed ip changes signature", func(t *testing.T) {
		moved := wifi()
		moved.IPv4 = []netip.Addr{addr("192.168.1.99")}
		if Signature(base) == Signature([]Iface{moved}) {
			t.Fatal("signature did not change when the IP changed")
		}
	})

	t.Run("added interface changes signature", func(t *testing.T) {
		extra := Iface{
			Name: "Ethernet", Up: true, Multicast: true, HasGateway: true,
			IPv4: []netip.Addr{addr("10.0.0.5")},
		}
		if Signature(base) == Signature([]Iface{wifi(), extra}) {
			t.Fatal("signature did not change when an interface was added")
		}
	})

	t.Run("input order does not change signature", func(t *testing.T) {
		a := Iface{
			Name: "Wi-Fi", Up: true, Multicast: true, HasGateway: true,
			IPv4: []netip.Addr{addr("192.168.1.20"), addr("192.168.1.10")},
		}
		b := Iface{
			Name: "Ethernet", Up: true, Multicast: true, HasGateway: true,
			IPv4: []netip.Addr{addr("10.0.0.5")},
		}
		fwd := Signature([]Iface{a, b})
		rev := Signature([]Iface{b, a})
		if fwd != rev {
			t.Fatalf("signature depends on order: %q vs %q", fwd, rev)
		}
		// Address order inside one interface must not matter either.
		swapped := a
		swapped.IPv4 = []netip.Addr{addr("192.168.1.10"), addr("192.168.1.20")}
		if Signature([]Iface{a, b}) != Signature([]Iface{swapped, b}) {
			t.Fatal("signature depends on address order")
		}
	})
}
