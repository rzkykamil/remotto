package pairing

import (
	"bytes"
	"errors"
	"strings"
	"testing"
)

// errReader always fails, to simulate an entropy source that breaks.
type errReader struct{ err error }

func (e errReader) Read([]byte) (int, error) { return 0, e.err }

func TestGenerateTokenFormat(t *testing.T) {
	t.Parallel()

	token, err := GenerateToken(bytes.NewReader(bytes.Repeat([]byte{0xAB}, tokenBytes)))
	if err != nil {
		t.Fatalf("GenerateToken() error = %v", err)
	}
	if len(token) != 64 {
		t.Fatalf("len(token) = %d, want 64", len(token))
	}
	if token != strings.Repeat("ab", tokenBytes) {
		t.Fatalf("token = %q, want lowercase hex of input bytes", token)
	}
	if !ValidToken(token) {
		t.Fatalf("ValidToken(%q) = false, want true", token)
	}
}

func TestGenerateTokenDeterministicReader(t *testing.T) {
	t.Parallel()

	input := make([]byte, tokenBytes)
	for i := range input {
		input[i] = byte(i)
	}

	first, err := GenerateToken(bytes.NewReader(input))
	if err != nil {
		t.Fatalf("first GenerateToken() error = %v", err)
	}
	second, err := GenerateToken(bytes.NewReader(input))
	if err != nil {
		t.Fatalf("second GenerateToken() error = %v", err)
	}
	if first != second {
		t.Fatalf("same input gave different tokens: %q vs %q", first, second)
	}
	want := "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"
	if first != want {
		t.Fatalf("token = %q, want %q", first, want)
	}
}

func TestGenerateTokenDiffersAcrossInputs(t *testing.T) {
	t.Parallel()

	a, err := GenerateToken(bytes.NewReader(bytes.Repeat([]byte{1}, tokenBytes)))
	if err != nil {
		t.Fatalf("GenerateToken(a) error = %v", err)
	}
	b, err := GenerateToken(bytes.NewReader(bytes.Repeat([]byte{2}, tokenBytes)))
	if err != nil {
		t.Fatalf("GenerateToken(b) error = %v", err)
	}
	if a == b {
		t.Fatalf("different entropy produced the same token %q", a)
	}
}

func TestGenerateTokenShortOrFailedReadReturnsNoToken(t *testing.T) {
	t.Parallel()

	readErr := errors.New("entropy source offline")

	tests := []struct {
		name string
		r    interface{ Read([]byte) (int, error) }
	}{
		{name: "empty reader", r: bytes.NewReader(nil)},
		{name: "one byte short", r: bytes.NewReader(make([]byte, tokenBytes-1))},
		{name: "reader error", r: errReader{err: readErr}},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()

			token, err := GenerateToken(tt.r)
			if err == nil {
				t.Fatalf("GenerateToken() error = nil, want error")
			}
			if token != "" {
				t.Fatalf("GenerateToken() token = %q, want empty on error", token)
			}
		})
	}
}

func TestGenerateTokenReaderErrorIsWrapped(t *testing.T) {
	t.Parallel()

	readErr := errors.New("entropy source offline")
	_, err := GenerateToken(errReader{err: readErr})
	if !errors.Is(err, readErr) {
		t.Fatalf("GenerateToken() error = %v, want wrapped %v", err, readErr)
	}
}

func TestValidToken(t *testing.T) {
	t.Parallel()

	valid := strings.Repeat("0123456789abcdef", 4)

	tests := []struct {
		name  string
		token string
		want  bool
	}{
		{name: "valid 64 lowercase hex", token: valid, want: true},
		{name: "empty", token: "", want: false},
		{name: "63 chars", token: valid[:63], want: false},
		{name: "65 chars", token: valid + "0", want: false},
		{name: "uppercase letter", token: "A" + valid[1:], want: false},
		{name: "non-hex letter", token: "g" + valid[1:], want: false},
		{name: "leading space", token: " " + valid[1:], want: false},
		{name: "trailing newline", token: valid + "\n", want: false},
		{name: "contains dash", token: valid[:10] + "-" + valid[11:], want: false},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()

			if got := ValidToken(tt.token); got != tt.want {
				t.Fatalf("ValidToken(%q) = %v, want %v", tt.token, got, tt.want)
			}
		})
	}
}
