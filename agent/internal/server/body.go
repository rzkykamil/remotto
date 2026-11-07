package server

import (
	"encoding/json"
	"errors"
	"io"
	"mime"
	"net/http"
)

// MaxBodyBytes is the largest request body accepted, per docs/api-spec.md.
const MaxBodyBytes = 1024

const invalidBodyMessage = "invalid request body"

// DecodeBody decodes a JSON request body into dst. It returns false after
// writing a 400 invalid_request envelope when the body is not acceptable.
//
// Rules: Content-Type must be application/json (charset allowed), the body is
// capped at MaxBodyBytes, unknown fields are rejected, and the body must hold
// exactly one JSON value. An empty body is rejected.
func DecodeBody(w http.ResponseWriter, r *http.Request, dst any) bool {
	if !isJSONContentType(r.Header.Get("Content-Type")) {
		WriteError(w, http.StatusBadRequest, CodeInvalidRequest, invalidBodyMessage)
		return false
	}

	r.Body = http.MaxBytesReader(w, r.Body, MaxBodyBytes)
	dec := json.NewDecoder(r.Body)
	dec.DisallowUnknownFields()

	if err := dec.Decode(dst); err != nil {
		WriteError(w, http.StatusBadRequest, CodeInvalidRequest, invalidBodyMessage)
		return false
	}
	// A second value, or leftover bytes that are not whitespace, must fail.
	// Only io.EOF means the body ended cleanly after the first value.
	if err := dec.Decode(&struct{}{}); !errors.Is(err, io.EOF) {
		WriteError(w, http.StatusBadRequest, CodeInvalidRequest, invalidBodyMessage)
		return false
	}
	return true
}

func isJSONContentType(value string) bool {
	mediaType, _, err := mime.ParseMediaType(value)
	return err == nil && mediaType == "application/json"
}
