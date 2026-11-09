package server

import (
	"log/slog"
	"net/http"
	"net/netip"
)

// allowedPrefixes lists the source ranges that may reach the agent (BR-12):
// private LAN ranges and the Tailscale CGNAT range 100.64.0.0/10.
// Loopback is accepted separately by IsLoopback.
var allowedPrefixes = []netip.Prefix{
	netip.MustParsePrefix("10.0.0.0/8"),
	netip.MustParsePrefix("172.16.0.0/12"),
	netip.MustParsePrefix("192.168.0.0/16"),
	netip.MustParsePrefix("100.64.0.0/10"),
}

// NetworkFilter rejects requests whose source address is outside the allowed
// LAN ranges with 403 forbidden_network. It is the second line of defense
// after the firewall profile. Unparsable source addresses are rejected too.
//
// The source address is logged without the request itself. Headers, query
// string and token never reach the log from this middleware.
func NetworkFilter(logger *slog.Logger) Middleware {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if allowedSource(r.RemoteAddr) {
				next.ServeHTTP(w, r)
				return
			}
			logger.Warn("request from outside allowed network",
				slog.String("ip", clientIP(r.RemoteAddr)),
			)
			WriteError(w, http.StatusForbidden, CodeForbiddenNetwork, "forbidden network")
		})
	}
}

// allowedSource reports whether remoteAddr ("host:port") is in an allowed range.
// IPv4-mapped IPv6 addresses are unmapped first, so ::ffff:192.168.1.5 is
// treated as 192.168.1.5. Any other IPv6 address is rejected unless it is loopback.
func allowedSource(remoteAddr string) bool {
	ap, err := netip.ParseAddrPort(remoteAddr)
	if err != nil {
		return false
	}
	addr := ap.Addr().Unmap()
	if addr.IsLoopback() {
		return true
	}
	for _, p := range allowedPrefixes {
		if p.Contains(addr) {
			return true
		}
	}
	return false
}
