package main

import (
	"fmt"
	"net"
)

// listenAgent opens the TCP listener at addr. When the port is already held by
// another program, it returns a readable message that names the port and how to
// fix it. Other errors are returned unchanged.
func listenAgent(addr string, port int) (net.Listener, error) {
	ln, err := net.Listen("tcp", addr)
	if err != nil {
		if isAddrInUse(err) {
			return nil, fmt.Errorf(`port %d sudah dipakai program lain. Tutup program itu, atau ubah "port" di config.json`, port)
		}
		return nil, err
	}
	return ln, nil
}
