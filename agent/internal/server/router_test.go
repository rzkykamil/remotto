package server

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func okHandler(body string) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte(body))
	})
}

func TestRouterDispatch(t *testing.T) {
	router := NewRouter()
	router.Handle(http.MethodGet, "/api/v1/status", okHandler("status"))
	router.Handle(http.MethodGet, "/api/v1/volume", okHandler("volume"))
	router.Handle(http.MethodPost, "/api/v1/volume", okHandler("volume-post"))

	tests := []struct {
		name       string
		method     string
		path       string
		wantStatus int
		wantBody   string
		wantAllow  string
		wantCode   string
	}{
		{
			name:       "registered route is called",
			method:     http.MethodGet,
			path:       "/api/v1/status",
			wantStatus: http.StatusOK,
			wantBody:   "status",
		},
		{
			name:       "same path, second method",
			method:     http.MethodPost,
			path:       "/api/v1/volume",
			wantStatus: http.StatusOK,
			wantBody:   "volume-post",
		},
		{
			name:       "unknown path is 404 envelope",
			method:     http.MethodGet,
			path:       "/api/v1/unknown",
			wantStatus: http.StatusNotFound,
			wantBody:   `{"error":{"code":"not_found","message":"route not found"}}`,
			wantCode:   CodeNotFound,
		},
		{
			name:       "trailing slash is not normalized",
			method:     http.MethodGet,
			path:       "/api/v1/status/",
			wantStatus: http.StatusNotFound,
			wantBody:   `{"error":{"code":"not_found","message":"route not found"}}`,
			wantCode:   CodeNotFound,
		},
		{
			name:       "wrong method is 405 with Allow",
			method:     http.MethodDelete,
			path:       "/api/v1/volume",
			wantStatus: http.StatusMethodNotAllowed,
			wantBody:   `{"error":{"code":"method_not_allowed","message":"method not allowed"}}`,
			wantAllow:  "GET, POST",
			wantCode:   CodeMethodNotAllowed,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			req := httptest.NewRequest(tt.method, tt.path, nil)
			rec := httptest.NewRecorder()
			router.ServeHTTP(rec, req)

			if rec.Code != tt.wantStatus {
				t.Errorf("status = %d, want %d", rec.Code, tt.wantStatus)
			}
			if tt.wantBody != "" && rec.Body.String() != tt.wantBody {
				t.Errorf("body = %s, want %s", rec.Body.String(), tt.wantBody)
			}
			if got := rec.Header().Get("Allow"); got != tt.wantAllow {
				t.Errorf("Allow = %q, want %q", got, tt.wantAllow)
			}
		})
	}
}

func TestRouterAllowHeaderIsSorted(t *testing.T) {
	router := NewRouter()
	router.Handle(http.MethodPut, "/api/v1/volume", okHandler("put"))
	router.Handle(http.MethodGet, "/api/v1/volume", okHandler("get"))
	router.Handle(http.MethodPost, "/api/v1/volume", okHandler("post"))

	req := httptest.NewRequest(http.MethodPatch, "/api/v1/volume", nil)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if got, want := rec.Header().Get("Allow"), "GET, POST, PUT"; got != want {
		t.Errorf("Allow = %q, want %q", got, want)
	}
}

func TestRouterDuplicateRegistrationPanics(t *testing.T) {
	tests := []struct {
		name   string
		first  [2]string
		second [2]string
	}{
		{"same method and path", [2]string{"GET", "/api/v1/status"}, [2]string{"GET", "/api/v1/status"}},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			router := NewRouter()
			router.Handle(tt.first[0], tt.first[1], okHandler("a"))

			defer func() {
				if recover() == nil {
					t.Error("expected panic on duplicate registration")
				}
			}()
			router.Handle(tt.second[0], tt.second[1], okHandler("b"))
		})
	}
}

func TestRouterSameRouteDifferentMethodsDoesNotPanic(t *testing.T) {
	router := NewRouter()
	router.Handle(http.MethodGet, "/api/v1/status", okHandler("a"))
	router.Handle(http.MethodPost, "/api/v1/status", okHandler("b"))

	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, httptest.NewRequest(http.MethodPost, "/api/v1/status", strings.NewReader("")))
	if rec.Body.String() != "b" {
		t.Errorf("body = %q, want %q", rec.Body.String(), "b")
	}
}
