package server

import (
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"regexp"
	"strconv"

	"remotto/agent/internal/control"
)

// volumeLevelPattern matches a plain JSON integer literal. Decimals, exponents,
// quoted strings, true, false and null do not match.
var volumeLevelPattern = regexp.MustCompile(`^-?(0|[1-9][0-9]*)$`)

// volumeSetBody is the PUT /volume request body. Level stays raw so that a
// missing field, a null, and a non-integer value can be told apart.
type volumeSetBody struct {
	Level json.RawMessage `json:"level"`
}

// volumeMuteBody is the POST /volume/mute request body. Muted is a pointer so
// that a missing field or a null is told apart from false.
type volumeMuteBody struct {
	Muted *bool `json:"muted"`
}

// registerVolumeRoutes adds the /volume routes (M3, docs/api-spec.md section
// "Volume").
func registerVolumeRoutes(r *Router, svc *control.VolumeService, logger *slog.Logger) {
	r.Handle(http.MethodGet, APIPrefix+"/volume", newVolumeGetHandler(svc, logger))
	r.Handle(http.MethodPut, APIPrefix+"/volume", newVolumeSetHandler(svc, logger))
	r.Handle(http.MethodPost, APIPrefix+"/volume/up", newVolumeStepHandler(true, svc, logger))
	r.Handle(http.MethodPost, APIPrefix+"/volume/down", newVolumeStepHandler(false, svc, logger))
	r.Handle(http.MethodPost, APIPrefix+"/volume/mute", newVolumeMuteHandler(svc, logger))
}

// newVolumeGetHandler returns the handler for GET /api/v1/volume.
func newVolumeGetHandler(svc *control.VolumeService, logger *slog.Logger) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		v, err := svc.Get(r.Context())
		if err != nil {
			writeVolumeError(w, logger, "get", err)
			return
		}
		WriteData(w, http.StatusOK, v)
	})
}

// newVolumeSetHandler returns the handler for PUT /api/v1/volume. A body that
// is malformed or lacks level is 400 invalid_request. A level that is not an
// integer from 0 to 100 is 400 invalid_level, and the OS is not touched.
func newVolumeSetHandler(svc *control.VolumeService, logger *slog.Logger) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var body volumeSetBody
		if !DecodeBody(w, r, &body) {
			return
		}
		if body.Level == nil {
			WriteError(w, http.StatusBadRequest, CodeInvalidRequest, invalidBodyMessage)
			return
		}
		level, ok := parseVolumeLevel(body.Level)
		if !ok {
			WriteError(w, http.StatusBadRequest, CodeInvalidLevel, control.ErrInvalidLevel.Error())
			return
		}
		v, err := svc.SetLevel(r.Context(), level)
		if err != nil {
			writeVolumeError(w, logger, "set", err)
			return
		}
		WriteData(w, http.StatusOK, v)
	})
}

// newVolumeStepHandler returns the handler for POST /api/v1/volume/up (up=true)
// and POST /api/v1/volume/down (up=false). The request body is ignored. A step
// is not idempotent, so it is not retried on failure. The result is 200 Volume,
// also at the 0 and 100 limits.
func newVolumeStepHandler(up bool, svc *control.VolumeService, logger *slog.Logger) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		step, op := svc.Down, "down"
		if up {
			step, op = svc.Up, "up"
		}
		v, err := step(r.Context())
		if err != nil {
			writeVolumeError(w, logger, op, err)
			return
		}
		WriteData(w, http.StatusOK, v)
	})
}

// newVolumeMuteHandler returns the handler for POST /api/v1/volume/mute. It sets
// mute to the given value and leaves the level alone. Repeating the request gives
// the same result. A body without a boolean muted is 400 invalid_request.
func newVolumeMuteHandler(svc *control.VolumeService, logger *slog.Logger) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var body volumeMuteBody
		if !DecodeBody(w, r, &body) {
			return
		}
		if body.Muted == nil {
			WriteError(w, http.StatusBadRequest, CodeInvalidRequest, invalidBodyMessage)
			return
		}
		v, err := svc.SetMuted(r.Context(), *body.Muted)
		if err != nil {
			writeVolumeError(w, logger, "mute", err)
			return
		}
		WriteData(w, http.StatusOK, v)
	})
}

// parseVolumeLevel converts a raw JSON integer literal to int. It reports false
// for anything that is not a plain integer, or that does not fit in an int.
// Range checks are left to control.VolumeService.
func parseVolumeLevel(raw json.RawMessage) (int, bool) {
	if !volumeLevelPattern.Match(raw) {
		return 0, false
	}
	n, err := strconv.Atoi(string(raw))
	if err != nil {
		return 0, false
	}
	return n, true
}

// writeVolumeError maps a service error to a response. ErrInvalidLevel is a
// client error with a safe message. Anything else is an OS failure: the cause
// goes to the log only, and the response carries a generic message.
func writeVolumeError(w http.ResponseWriter, logger *slog.Logger, op string, err error) {
	if errors.Is(err, control.ErrInvalidLevel) {
		WriteError(w, http.StatusBadRequest, CodeInvalidLevel, control.ErrInvalidLevel.Error())
		return
	}
	attrs := []any{slog.String("op", op), slog.String("error", err.Error())}
	if cause := errors.Unwrap(err); cause != nil {
		attrs = append(attrs, slog.String("cause", cause.Error()))
	}
	logger.Error("audio failed", attrs...)
	WriteError(w, http.StatusInternalServerError, CodeAudioFailed, "audio control failed")
}
