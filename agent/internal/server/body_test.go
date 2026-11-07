package server

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

type portBody struct {
	Port int `json:"port"`
}

const invalidRequestEnvelope = `{"error":{"code":"invalid_request","message":"invalid request body"}}`

func newJSONRequest(body, contentType string) *http.Request {
	req := httptest.NewRequest(http.MethodPut, "/api/v1/volume", strings.NewReader(body))
	if contentType != "" {
		req.Header.Set("Content-Type", contentType)
	}
	return req
}

func TestDecodeBody(t *testing.T) {
	padded := func(size int) string {
		// A valid object followed by spaces, so the total length is exactly size bytes.
		const obj = `{"port":8765}`
		return obj + strings.Repeat(" ", size-len(obj))
	}

	tests := []struct {
		name        string
		body        string
		contentType string
		wantOK      bool
		wantPort    int
	}{
		{name: "valid json", body: `{"port":8765}`, contentType: "application/json", wantOK: true, wantPort: 8765},
		{name: "charset allowed", body: `{"port":8765}`, contentType: "application/json; charset=utf-8", wantOK: true, wantPort: 8765},
		{name: "wrong content type", body: `{"port":8765}`, contentType: "text/plain", wantOK: false},
		{name: "missing content type", body: `{"port":8765}`, contentType: "", wantOK: false},
		{name: "unknown field", body: `{"port":8765,"extra":1}`, contentType: "application/json", wantOK: false},
		{name: "broken json", body: `{"port":`, contentType: "application/json", wantOK: false},
		{name: "body 1025 bytes", body: padded(1025), contentType: "application/json", wantOK: false},
		{name: "body exactly 1024 bytes", body: padded(1024), contentType: "application/json", wantOK: true, wantPort: 8765},
		{name: "two json objects", body: `{"port":1}{"port":2}`, contentType: "application/json", wantOK: false},
		{name: "trailing garbage", body: `{"port":1} x`, contentType: "application/json", wantOK: false},
		{name: "empty body", body: ``, contentType: "application/json", wantOK: false},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			req := newJSONRequest(tt.body, tt.contentType)
			rec := httptest.NewRecorder()
			var dst portBody

			ok := DecodeBody(rec, req, &dst)

			if ok != tt.wantOK {
				t.Fatalf("DecodeBody = %v, want %v", ok, tt.wantOK)
			}
			if tt.wantOK {
				if dst.Port != tt.wantPort {
					t.Errorf("port = %d, want %d", dst.Port, tt.wantPort)
				}
				return
			}
			if rec.Code != http.StatusBadRequest {
				t.Errorf("status = %d, want 400", rec.Code)
			}
			if got := rec.Body.String(); got != invalidRequestEnvelope {
				t.Errorf("body = %s, want %s", got, invalidRequestEnvelope)
			}
		})
	}
}
