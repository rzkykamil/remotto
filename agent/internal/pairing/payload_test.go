package pairing

import (
	"bytes"
	"encoding/json"
	"errors"
	"strings"
	"testing"
	"unicode/utf8"
)

const testToken = "4f9c1a2b3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8"

func TestBuildPayloadMatchesDataDesignExample(t *testing.T) {
	t.Parallel()

	got, err := BuildPayload("Laptop Kamar", "192.168.1.10", 8765, testToken)
	if err != nil {
		t.Fatalf("BuildPayload() error = %v", err)
	}
	want := `{"v":1,"name":"Laptop Kamar","host":"192.168.1.10","port":8765,"token":"` + testToken + `"}`
	if got != want {
		t.Fatalf("payload = %s\nwant    %s", got, want)
	}
	if strings.Contains(got, "\n") {
		t.Errorf("payload must be one line, got %q", got)
	}
	if !ValidToken(testToken) {
		t.Fatalf("test token %q does not match the token format", testToken)
	}
}

func TestBuildPayloadRoundTripsFields(t *testing.T) {
	t.Parallel()

	got, err := BuildPayload("Laptop", "100.100.1.2", 65535, testToken)
	if err != nil {
		t.Fatalf("BuildPayload() error = %v", err)
	}
	var decoded struct {
		V     int    `json:"v"`
		Name  string `json:"name"`
		Host  string `json:"host"`
		Port  int    `json:"port"`
		Token string `json:"token"`
	}
	if err := json.Unmarshal([]byte(got), &decoded); err != nil {
		t.Fatalf("payload is not JSON: %v", err)
	}
	if decoded.V != 1 || decoded.Host != "100.100.1.2" || decoded.Port != 65535 || decoded.Token != testToken {
		t.Errorf("decoded = %+v", decoded)
	}
}

func TestBuildPayloadTruncatesNameToRunesWithoutBreakingUTF8(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name     string
		input    string
		wantRune int
	}{
		{name: "long ascii", input: strings.Repeat("a", 60), wantRune: 32},
		{name: "long japanese", input: strings.Repeat("日本", 30), wantRune: 32},
		{name: "emoji at cut", input: strings.Repeat("x", 31) + "😀😀", wantRune: 32},
		{name: "short kept", input: "Laptop", wantRune: 6},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()

			got, err := BuildPayload(tt.input, "192.168.1.10", 8765, testToken)
			if err != nil {
				t.Fatalf("BuildPayload() error = %v", err)
			}
			if !utf8.ValidString(got) {
				t.Fatalf("payload is not valid UTF-8: %q", got)
			}
			var decoded struct {
				Name string `json:"name"`
			}
			if err := json.Unmarshal([]byte(got), &decoded); err != nil {
				t.Fatalf("payload is not JSON: %v", err)
			}
			if n := utf8.RuneCountInString(decoded.Name); n != tt.wantRune {
				t.Errorf("name has %d runes, want %d", n, tt.wantRune)
			}
			if !strings.HasPrefix(tt.input, decoded.Name) {
				t.Errorf("name %q is not a prefix of input", decoded.Name)
			}
		})
	}
}

func TestBuildPayloadRejectsInvalidInput(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name       string
		laptopName string
		host       string
		port       int
		token      string
	}{
		{name: "short token", laptopName: "L", host: "192.168.1.10", port: 8765, token: "abc"},
		{name: "uppercase token", laptopName: "L", host: "192.168.1.10", port: 8765, token: strings.ToUpper(testToken)},
		{name: "port zero", laptopName: "L", host: "192.168.1.10", port: 0, token: testToken},
		{name: "port too large", laptopName: "L", host: "192.168.1.10", port: 65536, token: testToken},
		{name: "public host", laptopName: "L", host: "8.8.8.8", port: 8765, token: testToken},
		{name: "hostname", laptopName: "L", host: "laptop.local", port: 8765, token: testToken},
		{name: "empty name", laptopName: "   ", host: "192.168.1.10", port: 8765, token: testToken},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()

			got, err := BuildPayload(tt.laptopName, tt.host, tt.port, tt.token)
			if !errors.Is(err, ErrInvalidPayload) {
				t.Fatalf("err = %v, want ErrInvalidPayload", err)
			}
			if got != "" {
				t.Errorf("payload = %q, want empty on error", got)
			}
			if strings.Contains(err.Error(), tt.token) && tt.token != "" && len(tt.token) > 3 {
				t.Errorf("error leaks token: %v", err)
			}
		})
	}
}

func TestRenderQRWritesBlockGlyphs(t *testing.T) {
	t.Parallel()

	payload, err := BuildPayload("Laptop", "192.168.1.10", 8765, testToken)
	if err != nil {
		t.Fatalf("BuildPayload() error = %v", err)
	}
	var buf bytes.Buffer
	if err := RenderQR(&buf, payload); err != nil {
		t.Fatalf("RenderQR() error = %v", err)
	}
	out := buf.String()
	if !strings.ContainsAny(out, "█▀▄") {
		t.Fatalf("output has no QR block characters: %q", out)
	}
	if !strings.Contains(out, "\n") {
		t.Errorf("output has no rows")
	}
}

func TestRenderQRRejectsBadPayloadAndWriter(t *testing.T) {
	t.Parallel()

	var buf bytes.Buffer
	if err := RenderQR(&buf, ""); !errors.Is(err, ErrQRPayload) {
		t.Errorf("empty payload err = %v, want ErrQRPayload", err)
	}
	if err := RenderQR(&buf, strings.Repeat("a", maxQRPayloadBytes+1)); !errors.Is(err, ErrQRPayload) {
		t.Errorf("oversized payload err = %v, want ErrQRPayload", err)
	}
	if err := RenderQR(nil, "x"); !errors.Is(err, ErrQRPayload) {
		t.Errorf("nil writer err = %v, want ErrQRPayload", err)
	}
	if err := RenderQR(failWriter{}, "{}"); err == nil {
		t.Error("failing writer: want error, got nil")
	}
}

// failWriter fails every write, to check that RenderQR reports write errors.
type failWriter struct{}

func (failWriter) Write([]byte) (int, error) { return 0, errors.New("broken pipe") }
