package server

import (
	"context"
	"errors"
	"log/slog"
	"net"
	"net/http"
	"time"
)

// shutdownTimeout is how long in-flight requests get after the context is
// cancelled (docs/technical-spec.md, section 9).
const shutdownTimeout = 3 * time.Second

// NewHandler assembles the global middleware around router. The order is
// fixed: Recover (outermost), then Logging, then the router. Network filter,
// rate limit, and auth are added in M1 between Logging and the router, without
// changing this order.
func NewHandler(router http.Handler, logger *slog.Logger) http.Handler {
	return Chain(router, Recover(logger), Logging(logger))
}

// NewHTTPServer returns an http.Server with the timeouts from the tech spec.
func NewHTTPServer(addr string, h http.Handler) *http.Server {
	return &http.Server{
		Addr:              addr,
		Handler:           h,
		ReadHeaderTimeout: 2 * time.Second,
		ReadTimeout:       3 * time.Second,
		WriteTimeout:      5 * time.Second,
		IdleTimeout:       60 * time.Second,
		MaxHeaderBytes:    8 << 10,
	}
}

// Serve runs srv on ln until ctx is done or the listener fails. On ctx done it
// stops accepting new requests, waits up to shutdownTimeout for in-flight ones,
// then closes any connection still open. It returns nil on a normal stop.
func Serve(ctx context.Context, srv *http.Server, ln net.Listener, logger *slog.Logger) error {
	errCh := make(chan error, 1)
	go func() {
		errCh <- srv.Serve(ln)
	}()
	logger.Info("server started", slog.String("addr", ln.Addr().String()))

	select {
	case err := <-errCh:
		// Serve returned before ctx was done, so the listener failed.
		logger.Info("server stopped")
		if errors.Is(err, http.ErrServerClosed) {
			return nil
		}
		return err
	case <-ctx.Done():
	}

	shutdownCtx, cancel := context.WithTimeout(context.Background(), shutdownTimeout)
	defer cancel()
	if err := srv.Shutdown(shutdownCtx); err != nil {
		logger.Warn("graceful shutdown timed out, closing connections", slog.String("error", err.Error()))
		_ = srv.Close()
	}

	err := <-errCh
	logger.Info("server stopped")
	if err != nil && !errors.Is(err, http.ErrServerClosed) {
		return err
	}
	return nil
}
