package server

import (
	"errors"
	"log/slog"
	"net/http"

	"remotto/agent/internal/control"
)

// mediaData is the body of a 200 response, see docs/api-spec.md, section "Media".
type mediaData struct {
	Action string `json:"action"`
}

// newMediaHandler returns the handler for one POST /api/v1/media/* route. The
// request body is ignored. The action is not retried: the OS call is not
// idempotent, so a failure is reported once as 500 media_failed.
func newMediaHandler(action control.MediaAction, svc *control.MediaService, logger *slog.Logger) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if err := svc.Do(r.Context(), action); err != nil {
			attrs := []any{slog.String("action", string(action)), slog.String("error", err.Error())}
			// The OS cause is logged only. It never reaches the response.
			if cause := errors.Unwrap(err); cause != nil {
				attrs = append(attrs, slog.String("cause", cause.Error()))
			}
			logger.Error("media failed", attrs...)
			WriteError(w, http.StatusInternalServerError, CodeMediaFailed, "media control failed")
			return
		}
		WriteData(w, http.StatusOK, mediaData{Action: string(action)})
	})
}
