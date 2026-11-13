// Package discovery advertises the agent on the LAN over mDNS (DNS-SD) so the
// app can find it again after its IP address changes. The advertisement never
// carries the token or a hash of it. See docs/flows/discovery-flow.md.
//
// This file holds the shared types. The pure helpers live in ifaces.go and
// txt.go, and the advertising loop lives in run.go.
package discovery

import (
	"io"
	"net"
	"net/netip"
	"time"
)

const (
	// ServiceType is the DNS-SD service type the app browses for.
	ServiceType = "_remotto._tcp"

	// Domain is the mDNS domain used for the advertisement.
	Domain = "local."

	// TXTVersion is the value of the TXT "v" key, the advertisement schema version.
	TXTVersion = "1"

	// DefaultInterval is how often the address set is polled for changes.
	DefaultInterval = 10 * time.Second

	// maxNameRunes caps the TXT "name" value, in runes.
	maxNameRunes = 32
)

// Service is one mDNS advertisement: an instance of ServiceType on Port with
// its TXT records, the IPv4 addresses it is reachable on, and the interfaces
// it is announced through.
type Service struct {
	Instance string
	Type     string
	Port     int
	TXT      []string
	IPs      []netip.Addr
	Ifaces   []net.Interface
}

// Registrar publishes a Service and returns a Closer that withdraws it.
// The system implementation lives in zeroconf.go.
type Registrar interface {
	Register(Service) (io.Closer, error)
}

// InterfaceLister reports the local network interfaces. It must be read-only.
// The system implementation lives in lister.go.
type InterfaceLister interface {
	List() ([]Iface, error)
}
