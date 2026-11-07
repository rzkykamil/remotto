package server

import (
	"bytes"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

// wrongToken is a well-formed token that differs from testTokenA.
const wrongToken = testTokenB

// TestBR11_FullHandlerNeverLogsOrEchoesSecrets runs the complete handler
// (NewAPIHandler: recover, logging, network filter, auth, router) and checks
// that neither the log nor any response body carries the token, the
// Authorization value, or a query string token (BR-11).
func TestBR11_FullHandlerNeverLogsOrEchoesSecrets(t *testing.T) {
	tests := []struct {
		name        string
		remoteAddr  string
		path        string
		authHeader  string
		wantStatus  int
		wantCode    string
		wantIP      string
		logsFailure bool
	}{
		{
			name:       "valid token",
			remoteAddr: "192.168.1.20:51234",
			path:       "/api/v1/status",
			authHeader: "Bearer " + testTokenA,
			wantStatus: http.StatusOK,
		},
		{
			name:        "wrong token",
			remoteAddr:  "192.168.1.20:51234",
			path:        "/api/v1/status",
			authHeader:  "Bearer " + wrongToken,
			wantStatus:  http.StatusUnauthorized,
			wantCode:    CodeInvalidToken,
			wantIP:      "192.168.1.20",
			logsFailure: true,
		},
		{
			name:        "no token",
			remoteAddr:  "192.168.1.20:51234",
			path:        "/api/v1/status",
			wantStatus:  http.StatusUnauthorized,
			wantCode:    CodeInvalidToken,
			wantIP:      "192.168.1.20",
			logsFailure: true,
		},
		{
			name:        "token in query string",
			remoteAddr:  "192.168.1.20:51234",
			path:        "/api/v1/status?token=" + testTokenA,
			wantStatus:  http.StatusUnauthorized,
			wantCode:    CodeInvalidToken,
			wantIP:      "192.168.1.20",
			logsFailure: true,
		},
		{
			name:       "public source address",
			remoteAddr: "8.8.8.8:4444",
			path:       "/api/v1/status",
			authHeader: "Bearer " + testTokenA,
			wantStatus: http.StatusForbidden,
			wantCode:   CodeForbiddenNetwork,
			wantIP:     "8.8.8.8",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var buf bytes.Buffer
			h := NewAPIHandler(newTestLogger(&buf), staticToken(testTokenA), StatusDeps{
				Name:      "Laptop-Kamar",
				Version:   "test",
				StartedAt: time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC),
				Now:       func() time.Time { return time.Date(2026, 1, 1, 0, 1, 0, 0, time.UTC) },
			})

			req := httptest.NewRequest(http.MethodGet, tt.path, nil)
			req.RemoteAddr = tt.remoteAddr
			if tt.authHeader != "" {
				req.Header.Set("Authorization", tt.authHeader)
			}
			rec := httptest.NewRecorder()
			h.ServeHTTP(rec, req)

			if rec.Code != tt.wantStatus {
				t.Fatalf("status = %d, want %d (body %q)", rec.Code, tt.wantStatus, rec.Body.String())
			}
			if tt.wantCode != "" && !strings.Contains(rec.Body.String(), `"code":"`+tt.wantCode+`"`) {
				t.Errorf("body %q lacks code %q", rec.Body.String(), tt.wantCode)
			}

			assertNoSecrets(t, "response body", rec.Body.String())
			assertNoSecrets(t, "log", buf.String())

			if !tt.logsFailure && tt.wantStatus != http.StatusForbidden {
				return
			}
			lines := requestLines(t, &buf)
			if len(lines) != 1 {
				t.Fatalf("request lines = %d, want 1: %q", len(lines), buf.String())
			}
			m := lines[0]
			if m["ip"] != tt.wantIP {
				t.Errorf("ip = %v, want %s", m["ip"], tt.wantIP)
			}
			if m["status"] != float64(tt.wantStatus) {
				t.Errorf("status = %v, want %d", m["status"], tt.wantStatus)
			}
			if m["errorCode"] != tt.wantCode {
				t.Errorf("errorCode = %v, want %s", m["errorCode"], tt.wantCode)
			}
		})
	}
}

// assertNoSecrets fails when s contains the token, the Authorization scheme,
// or a query string marker.
func assertNoSecrets(t *testing.T, where, s string) {
	t.Helper()
	for _, forbidden := range []string{testTokenA, wrongToken, "Authorization", "Bearer", "token="} {
		if strings.Contains(s, forbidden) {
			t.Errorf("%s contains %q: %q", where, forbidden, s)
		}
	}
}
