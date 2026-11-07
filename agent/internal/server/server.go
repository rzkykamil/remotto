package server

import (
	"context"
	"errors"
	"log/slog"
	"net"
	"net/http"
	"time"

	"remotto/agent/internal/control"
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

// APIPrefix is the base path of every API route (docs/api-spec.md).
const APIPrefix = "/api/v1"

// APIOption sets an optional dependency of NewAPIHandler.
type APIOption func(*apiOptions)

type apiOptions struct {
	media control.MediaController
}

// WithMedia sets the controller behind the /media routes. Without it the routes
// still exist and answer 500 media_failed (fail-closed).
func WithMedia(c control.MediaController) APIOption {
	return func(o *apiOptions) { o.media = c }
}

// NewAPIHandler returns the complete agent handler: the API routes wrapped in
// the global middleware. The order is Recover, Logging, NetworkFilter, then
// the rate limit slot (M6), then Auth, so a request from outside the LAN gets
// 403 before any token check and unknown routes still need a valid token.
// Options are optional; callers that pass none get the routes without the
// hardware controllers.
func NewAPIHandler(logger *slog.Logger, tokens TokenSource, status StatusDeps, opts ...APIOption) http.Handler {
	var o apiOptions
	for _, opt := range opts {
		opt(&o)
	}
	router := NewRouter()
	router.Handle(http.MethodGet, APIPrefix+"/status", newStatusHandler(status))
	media := control.NewMediaService(o.media)
	router.Handle(http.MethodPost, APIPrefix+"/media/play-pause", newMediaHandler(control.MediaPlayPause, media, logger))
	router.Handle(http.MethodPost, APIPrefix+"/media/next", newMediaHandler(control.MediaNext, media, logger))
	router.Handle(http.MethodPost, APIPrefix+"/media/prev", newMediaHandler(control.MediaPrev, media, logger))
	// Rate limit (M6) goes here, between NetworkFilter and Auth.
	return Chain(router,
		Recover(logger),
		Logging(logger),
		NetworkFilter(logger),
		Auth(tokens),
	)
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
