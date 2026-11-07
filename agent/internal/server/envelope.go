package server

import (
	"encoding/json"
	"net/http"
)

// Error codes from docs/api-spec.md, section "Kode error". Keep these in sync with the spec.
const (
	CodeInvalidToken     = "invalid_token"
	CodeForbiddenNetwork = "forbidden_network"
	CodeInvalidRequest   = "invalid_request"
	CodeInvalidLevel     = "invalid_level"
	CodeNotFound         = "not_found"
	CodeMethodNotAllowed = "method_not_allowed"
	CodePowerPending     = "power_pending"
	CodeNoPendingPower   = "no_pending_power"
	CodePowerExecuting   = "power_executing"
	CodeRateLimited      = "rate_limited"
	CodeMediaFailed      = "media_failed"
	CodeAudioFailed      = "audio_failed"
	CodePowerFailed      = "power_failed"
	CodeInternal         = "internal"
)

// errorCodeSetter is implemented by the logging response writer. WriteError
// reports the code through it so the access log can record errorCode.
type errorCodeSetter interface {
	SetErrorCode(code string)
}

type dataEnvelope struct {
	Data any `json:"data"`
}

type errorBody struct {
	Code    string `json:"code"`
	Message string `json:"message"`
}

type errorEnvelope struct {
	Error errorBody `json:"error"`
}

// WriteData writes a success response wrapped in the {"data": ...} envelope.
func WriteData(w http.ResponseWriter, status int, data any) {
	body, err := json.Marshal(dataEnvelope{Data: data})
	if err != nil {
		WriteError(w, http.StatusInternalServerError, CodeInternal, "internal error")
		return
	}
	writeBody(w, status, body)
}

// WriteError writes an error response wrapped in the {"error": {...}} envelope.
func WriteError(w http.ResponseWriter, status int, code, message string) {
	if s, ok := w.(errorCodeSetter); ok {
		s.SetErrorCode(code)
	}
	body, err := json.Marshal(errorEnvelope{Error: errorBody{Code: code, Message: message}})
	if err != nil {
		// Unreachable with string fields. Fall back to a constant body rather than panic.
		if s, ok := w.(errorCodeSetter); ok {
			s.SetErrorCode(CodeInternal)
		}
		status = http.StatusInternalServerError
		body = []byte(`{"error":{"code":"internal","message":"internal error"}}`)
	}
	writeBody(w, status, body)
}

func writeBody(w http.ResponseWriter, status int, body []byte) {
	h := w.Header()
	h.Set("Content-Type", "application/json; charset=utf-8")
	h.Set("Cache-Control", "no-store")
	w.WriteHeader(status)
	_, _ = w.Write(body)
}
