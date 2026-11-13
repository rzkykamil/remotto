package discovery

import (
	"errors"
	"fmt"
	"io"
	"strings"
	"sync"

	"github.com/grandcat/zeroconf"

	"remotto/agent/internal/pairing"
)

// instancePrefix is the prefix InstanceName puts in front of the agent ID.
const instancePrefix = "Remotto-"

// ZeroconfRegistrar publishes a Service over mDNS with github.com/grandcat/zeroconf.
//
// It always uses RegisterProxy with a host name derived from the instance and
// the LAN IPv4 addresses from the Service. It never falls back to Register,
// because Register would announce the OS host name and every address of the
// interface, which can include addresses that are not on the LAN.
type ZeroconfRegistrar struct{}

// Register announces s on the interfaces in s.Ifaces and returns a Closer that
// withdraws the advertisement. Close is safe to call more than once.
func (ZeroconfRegistrar) Register(s Service) (io.Closer, error) {
	host := hostName(s.Instance)
	if host == "" {
		return nil, errors.New("discovery: instance name must start with Remotto-")
	}
	if len(s.Ifaces) == 0 {
		// An empty list makes the library pick every interface, which is not allowed.
		return nil, errors.New("discovery: no interfaces to advertise on")
	}
	ips := make([]string, 0, len(s.IPs))
	for _, a := range s.IPs {
		if pairing.IsLANAddr(a) {
			ips = append(ips, a.String())
		}
	}
	if len(ips) == 0 {
		return nil, errors.New("discovery: no LAN IPv4 address to advertise")
	}
	srv, err := zeroconf.RegisterProxy(s.Instance, s.Type, Domain, s.Port, host, ips, s.TXT, s.Ifaces)
	if err != nil {
		return nil, fmt.Errorf("discovery: register mdns: %w", err)
	}
	return &serverCloser{srv: srv}, nil
}

// hostName returns the mDNS host label for an instance, such as
// "remotto-0a1b2c3d" for "Remotto-0a1b2c3d". The label has no ".local."
// suffix because RegisterProxy adds it. It returns "" for other instance names.
func hostName(instance string) string {
	if !strings.HasPrefix(instance, instancePrefix) {
		return ""
	}
	return "remotto-" + strings.ToLower(strings.TrimPrefix(instance, instancePrefix))
}

// serverCloser withdraws a zeroconf server exactly once.
type serverCloser struct {
	once sync.Once
	srv  *zeroconf.Server
}

// Close shuts the server down. Later calls do nothing.
func (c *serverCloser) Close() error {
	c.once.Do(c.srv.Shutdown)
	return nil
}
