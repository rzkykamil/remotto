package main

import (
	"context"
	"time"

	"remotto/agent/internal/discovery"
)

// discoveryStopTimeout bounds how long stop waits for the advertising loop to
// withdraw its registration.
const discoveryStopTimeout = 2 * time.Second

// startDiscovery starts the mDNS advertisement and returns the function that
// withdraws it. Tests replace it so they never open a real multicast socket.
var startDiscovery = realStartDiscovery

// realStartDiscovery runs discovery.Run in its own goroutine with the system
// registrar and interface lister. stop cancels the loop and waits up to
// discoveryStopTimeout for it to return.
func realStartDiscovery(ctx context.Context, opts discovery.Options) (stop func()) {
	opts.Registrar = discovery.ZeroconfRegistrar{}
	opts.Lister = discovery.SystemLister{}
	ctx, cancel := context.WithCancel(ctx)
	done := make(chan struct{})
	go func() {
		defer close(done)
		discovery.Run(ctx, opts)
	}()
	return func() {
		cancel()
		select {
		case <-done:
		case <-time.After(discoveryStopTimeout):
		}
	}
}
