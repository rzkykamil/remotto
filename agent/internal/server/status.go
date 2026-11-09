package server

import (
	"context"
	"log/slog"
	"net/http"
	"time"

	"remotto/agent/internal/control"
)

// statusTimeout bounds the audio read so a stuck OS call cannot hold the
// status request (docs/technical-spec.md: fast responses).
const statusTimeout = 2 * time.Second

// StatusDeps holds what GET /status reports.
type StatusDeps struct {
	Name      string
	Version   string
	StartedAt time.Time
	// Now returns the current time. It is injected so tests can use a fake clock.
	Now   func() time.Time
	Audio control.AudioController
	// Pending returns the active power schedule, or nil when there is none.
	// It is nil until the power scheduler exists (M4); a nil func reports null.
	Pending func() any
}

// statusData is the body of the 200 response, see docs/api-spec.md, section "Status".
type statusData struct {
	Name          string          `json:"name"`
	Version       string          `json:"version"`
	UptimeSeconds int64           `json:"uptimeSeconds"`
	Volume        *control.Volume `json:"volume"`
	Pending       any             `json:"pending"`
}

// newStatusHandler returns the handler for GET /api/v1/status. A failed audio
// read reports volume as null and still answers 200, so the app keeps the
// connection and its last known volume.
func newStatusHandler(deps StatusDeps, logger *slog.Logger) http.Handler {
	now := deps.Now
	if now == nil {
		now = time.Now
	}
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		data := statusData{
			Name:          deps.Name,
			Version:       deps.Version,
			UptimeSeconds: uptimeSeconds(now().Sub(deps.StartedAt)),
		}
		if deps.Audio != nil {
			ctx, cancel := context.WithTimeout(r.Context(), statusTimeout)
			v, err := deps.Audio.Volume(ctx)
			if err == nil {
				data.Volume = &v
			} else if logger != nil {
				logger.Warn("status audio read failed", slog.String("error", err.Error()))
			}
			cancel()
		}
		if deps.Pending != nil {
			data.Pending = deps.Pending()
		}
		WriteData(w, http.StatusOK, data)
	})
}

// uptimeSeconds converts d to whole seconds, never below zero.
func uptimeSeconds(d time.Duration) int64 {
	if d < 0 {
		return 0
	}
	return int64(d / time.Second)
}
