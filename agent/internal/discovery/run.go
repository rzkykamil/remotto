package discovery

import (
	"context"
	"io"
	"log/slog"
	"net/netip"
	"strings"
	"time"
)

// Options configures Run. Registrar and Lister are the system adapters in
// production; tests pass fakes. After is the wait between polls and defaults
// to time.After. Run never receives the token, so nothing it logs or
// advertises can contain it.
type Options struct {
	Enabled   bool
	AgentID   string
	Name      string
	Port      int
	Interval  time.Duration
	Logger    *slog.Logger
	Registrar Registrar
	Lister    InterfaceLister
	After     func(time.Duration) <-chan time.Time
}

// Run advertises the agent while ctx is alive. It polls the interfaces every
// Interval and re-registers whenever the set of LAN addresses changes. It
// returns when ctx is done, after withdrawing the active advertisement.
//
// Run does not return an error: discovery is best effort, so a failed
// registration is logged and retried on the next poll while the agent keeps
// serving HTTP.
func Run(ctx context.Context, o Options) {
	log := o.Logger
	if log == nil {
		log = slog.Default()
	}
	if !o.Enabled {
		log.Info("discovery disabled by config")
		return
	}
	if !ValidAgentID(o.AgentID) {
		log.Warn("discovery skipped: agent id is missing or invalid")
		return
	}
	if o.Registrar == nil || o.Lister == nil {
		log.Warn("discovery skipped: registrar or lister is not set")
		return
	}
	if o.Interval <= 0 {
		o.Interval = DefaultInterval
	}
	if o.After == nil {
		o.After = time.After
	}
	o.Logger = log

	a := &advertiser{opts: o, log: log}
	defer a.withdraw()

	for {
		if ctx.Err() != nil {
			return
		}
		a.poll()
		select {
		case <-ctx.Done():
			return
		case <-o.After(o.Interval):
		}
	}
}

// advertiser holds the state of one Run: the active registration and the
// signature of the interfaces it was made for.
type advertiser struct {
	opts    Options
	log     *slog.Logger
	active  io.Closer
	lastSig string
	// checked is false when the last attempt failed, so the next poll
	// retries even if the interfaces did not change.
	checked bool
	// warnedSig is the signature a registration warning was logged for.
	// Repeated failures for the same set log at debug level only.
	warnedSig  string
	listFailed bool
}

// poll compares the current LAN interfaces with the last registration and
// changes the advertisement only when they differ.
func (a *advertiser) poll() {
	ifaces, err := a.opts.Lister.List()
	if err != nil {
		if !a.listFailed {
			a.log.Warn("list network interfaces failed, keeping current advertisement", "err", err)
		}
		a.listFailed = true
		return
	}
	a.listFailed = false

	sel := SelectInterfaces(ifaces)
	sig := Signature(sel)
	if a.checked && sig == a.lastSig {
		return
	}

	a.withdraw()
	a.lastSig = sig

	if len(sel) == 0 {
		a.checked = true
		a.warnedSig = ""
		a.log.Info("no LAN interface to advertise on, waiting for one")
		return
	}

	svc := a.service(sel)
	c, err := a.opts.Registrar.Register(svc)
	if err != nil {
		if sig != a.warnedSig {
			a.log.Warn("advertise failed, will retry", "err", err)
			a.warnedSig = sig
		} else {
			a.log.Debug("advertise still failing", "err", err)
		}
		a.checked = false
		return
	}

	a.active = c
	a.checked = true
	a.warnedSig = ""
	a.log.Info("advertising on LAN", "interfaces", len(sel), "port", svc.Port)
	a.log.Debug("advertised addresses", "ips", ipList(svc.IPs))
}

// withdraw closes the active registration, if any. A close error is logged at
// debug level because the advertisement is already being replaced or stopped.
func (a *advertiser) withdraw() {
	if a.active == nil {
		return
	}
	if err := a.active.Close(); err != nil {
		a.log.Debug("withdraw advertisement", "err", err)
	}
	a.active = nil
}

// service builds the advertisement for the selected interfaces: the IPv4
// addresses and interfaces, the port, and TXT records from BuildTXT.
func (a *advertiser) service(sel []Iface) Service {
	svc := Service{
		Instance: InstanceName(a.opts.AgentID),
		Type:     ServiceType,
		Port:     a.opts.Port,
		TXT:      BuildTXT(a.opts.AgentID, a.opts.Name),
	}
	for _, f := range sel {
		svc.IPs = append(svc.IPs, f.IPv4...)
		svc.Ifaces = append(svc.Ifaces, f.Raw)
	}
	return svc
}

// ipList formats addresses as a comma-separated string for debug logs.
func ipList(addrs []netip.Addr) string {
	parts := make([]string, 0, len(addrs))
	for _, a := range addrs {
		parts = append(parts, a.String())
	}
	return strings.Join(parts, ",")
}
