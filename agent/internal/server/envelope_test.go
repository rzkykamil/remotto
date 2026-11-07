package server

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

// codeSetterRecorder records the code passed to SetErrorCode.
type codeSetterRecorder struct {
	*httptest.ResponseRecorder
	code string
}

func (c *codeSetterRecorder) SetErrorCode(code string) { c.code = code }

func TestWriteDataEnvelope(t *testing.T) {
	tests := []struct {
		name   string
		status int
		data   any
		want   string
	}{
		{
			name:   "object",
			status: http.StatusOK,
			data:   map[string]any{"name": "Laptop"},
			want:   `{"data":{"name":"Laptop"}}`,
		},
		{
			name:   "nil data",
			status: http.StatusOK,
			data:   nil,
			want:   `{"data":null}`,
		},
		{
			name:   "accepted status",
			status: http.StatusAccepted,
			data:   map[string]string{"action": "shutdown"},
			want:   `{"data":{"action":"shutdown"}}`,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			rec := httptest.NewRecorder()
			WriteData(rec, tt.status, tt.data)

			if rec.Code != tt.status {
				t.Errorf("status = %d, want %d", rec.Code, tt.status)
			}
			if got := rec.Header().Get("Content-Type"); got != "application/json; charset=utf-8" {
				t.Errorf("Content-Type = %q", got)
			}
			if got := rec.Header().Get("Cache-Control"); got != "no-store" {
				t.Errorf("Cache-Control = %q", got)
			}
			if got := rec.Body.String(); got != tt.want {
				t.Errorf("body = %s, want %s", got, tt.want)
			}
		})
	}
}

func TestWriteDataMarshalFailureReturnsInternalError(t *testing.T) {
	rec := httptest.NewRecorder()
	WriteData(rec, http.StatusOK, make(chan int)) // channels cannot be marshaled

	if rec.Code != http.StatusInternalServerError {
		t.Errorf("status = %d, want 500", rec.Code)
	}
	want := `{"error":{"code":"internal","message":"internal error"}}`
	if got := rec.Body.String(); got != want {
		t.Errorf("body = %s, want %s", got, want)
	}
}

func TestWriteErrorEnvelope(t *testing.T) {
	tests := []struct {
		name    string
		status  int
		code    string
		message string
		want    string
	}{
		{
			name:    "not found",
			status:  http.StatusNotFound,
			code:    CodeNotFound,
			message: "route not found",
			want:    `{"error":{"code":"not_found","message":"route not found"}}`,
		},
		{
			name:    "invalid token",
			status:  http.StatusUnauthorized,
			code:    CodeInvalidToken,
			message: "invalid token",
			want:    `{"error":{"code":"invalid_token","message":"invalid token"}}`,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			rec := httptest.NewRecorder()
			WriteError(rec, tt.status, tt.code, tt.message)

			if rec.Code != tt.status {
				t.Errorf("status = %d, want %d", rec.Code, tt.status)
			}
			if got := rec.Header().Get("Content-Type"); got != "application/json; charset=utf-8" {
				t.Errorf("Content-Type = %q", got)
			}
			if got := rec.Body.String(); got != tt.want {
				t.Errorf("body = %s, want %s", got, tt.want)
			}
		})
	}
}

func TestWriteErrorReportsCodeToSetter(t *testing.T) {
	rec := &codeSetterRecorder{ResponseRecorder: httptest.NewRecorder()}
	WriteError(rec, http.StatusBadRequest, CodeInvalidRequest, "invalid request body")

	if rec.code != CodeInvalidRequest {
		t.Errorf("SetErrorCode got %q, want %q", rec.code, CodeInvalidRequest)
	}
}

func TestErrorCodeConstantsMatchAPISpec(t *testing.T) {
	// Strings from docs/api-spec.md, section "Kode error".
	tests := []struct {
		name string
		got  string
		want string
	}{
		{"invalid_token", CodeInvalidToken, "invalid_token"},
		{"forbidden_network", CodeForbiddenNetwork, "forbidden_network"},
		{"invalid_request", CodeInvalidRequest, "invalid_request"},
		{"invalid_level", CodeInvalidLevel, "invalid_level"},
		{"not_found", CodeNotFound, "not_found"},
		{"method_not_allowed", CodeMethodNotAllowed, "method_not_allowed"},
		{"power_pending", CodePowerPending, "power_pending"},
		{"no_pending_power", CodeNoPendingPower, "no_pending_power"},
		{"power_executing", CodePowerExecuting, "power_executing"},
		{"rate_limited", CodeRateLimited, "rate_limited"},
		{"media_failed", CodeMediaFailed, "media_failed"},
		{"audio_failed", CodeAudioFailed, "audio_failed"},
		{"power_failed", CodePowerFailed, "power_failed"},
		{"internal", CodeInternal, "internal"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if tt.got != tt.want {
				t.Errorf("code = %q, want %q", tt.got, tt.want)
			}
			if strings.ContainsAny(tt.got, " \t") {
				t.Errorf("code %q contains whitespace", tt.got)
			}
		})
	}
}
