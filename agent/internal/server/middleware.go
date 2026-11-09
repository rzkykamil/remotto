package server

import (
	"fmt"
	"log/slog"
	"net"
	"net/http"
	"runtime/debug"
	"time"
)

// Middleware wraps a handler with extra behavior.
type Middleware func(http.Handler) http.Handler

// Chain applies mws to h. The first middleware is the outermost layer.
func Chain(h http.Handler, mws ...Middleware) http.Handler {
	for i := len(mws) - 1; i >= 0; i-- {
		h = mws[i](h)
	}
	return h
}

// statusRecorder wraps an http.ResponseWriter and remembers the status code,
// whether the header was written, and the error code set by WriteError.
type statusRecorder struct {
	http.ResponseWriter
	status      int
	wroteHeader bool
	errorCode   string
}

func newStatusRecorder(w http.ResponseWriter) *statusRecorder {
	return &statusRecorder{ResponseWriter: w, status: http.StatusOK}
}

func (s *statusRecorder) WriteHeader(code int) {
	if !s.wroteHeader {
		s.status = code
		s.wroteHeader = true
	}
	s.ResponseWriter.WriteHeader(code)
}

func (s *statusRecorder) Write(b []byte) (int, error) {
	// An implicit 200 is already the default status.
	s.wroteHeader = true
	return s.ResponseWriter.Write(b)
}

// SetErrorCode records the error code so the access log can include it.
func (s *statusRecorder) SetErrorCode(code string) {
	s.errorCode = code
}

// Unwrap lets http.ResponseController reach the underlying writer.
func (s *statusRecorder) Unwrap() http.ResponseWriter {
	return s.ResponseWriter
}

// Recover turns a panic in the handler into a 500 internal envelope and logs
// the panic value and stack. http.ErrAbortHandler is re-panicked so that the
// server can abort the connection as the standard library expects.
func Recover(logger *slog.Logger) Middleware {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			rec := newStatusRecorder(w)
			defer func() {
				v := recover()
				if v == nil {
					return
				}
				if v == http.ErrAbortHandler {
					panic(v)
				}
				logger.Error("panic",
					slog.String("panic", fmt.Sprint(v)),
					slog.String("stack", string(debug.Stack())),
				)
				if !rec.wroteHeader {
					WriteError(rec, http.StatusInternalServerError, CodeInternal, "internal error")
				}
			}()
			next.ServeHTTP(rec, r)
		})
	}
}

// Logging writes one "request" line per request after the handler returns.
// Only the client IP, method, URL path, status, error code and duration are
// logged. Headers, body, and query string never are.
//
// On panic it logs status 500 with errorCode "internal" and re-panics so that
// Recover writes the response. This keeps panicking requests in the log.
func Logging(logger *slog.Logger) Middleware {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			start := time.Now()
			rec := newStatusRecorder(w)
			defer func() {
				if v := recover(); v != nil {
					if !rec.wroteHeader {
						rec.status = http.StatusInternalServerError
					}
					rec.errorCode = CodeInternal
					logRequest(logger, r, rec, start)
					panic(v)
				}
				logRequest(logger, r, rec, start)
			}()
			next.ServeHTTP(rec, r)
		})
	}
}

func logRequest(logger *slog.Logger, r *http.Request, rec *statusRecorder, start time.Time) {
	attrs := []slog.Attr{
		slog.String("ip", clientIP(r.RemoteAddr)),
		slog.String("method", r.Method),
		slog.String("path", r.URL.Path),
		slog.Int("status", rec.status),
	}
	if rec.errorCode != "" {
		attrs = append(attrs, slog.String("errorCode", rec.errorCode))
	}
	attrs = append(attrs, slog.Int64("durationMs", time.Since(start).Milliseconds()))
	logger.LogAttrs(r.Context(), slog.LevelInfo, "request", attrs...)
}

func clientIP(remoteAddr string) string {
	host, _, err := net.SplitHostPort(remoteAddr)
	if err != nil {
		return remoteAddr
	}
	return host
}
