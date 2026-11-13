package discovery

import (
	"strings"
	"testing"
	"unicode/utf8"
)

const testAgentID = "0123456789abcdef0123456789abcdef"

func TestInstanceName(t *testing.T) {
	tests := []struct {
		name    string
		agentID string
		want    string
	}{
		{"uses first 8 hex", testAgentID, "Remotto-01234567"},
		{"short id is used whole", "abc", "Remotto-abc"},
		{"empty id does not panic", "", "Remotto-"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := InstanceName(tt.agentID); got != tt.want {
				t.Fatalf("InstanceName(%q) = %q, want %q", tt.agentID, got, tt.want)
			}
		})
	}
}

func TestValidAgentID(t *testing.T) {
	tests := []struct {
		in   string
		want bool
	}{
		{testAgentID, true},
		{"0123456789ABCDEF0123456789ABCDEF", false},
		{"0123456789abcdef0123456789abcde", false},
		{"0123456789abcdef0123456789abcdef0", false},
		{"", false},
		{"g123456789abcdef0123456789abcdef", false},
	}
	for _, tt := range tests {
		if got := ValidAgentID(tt.in); got != tt.want {
			t.Errorf("ValidAgentID(%q) = %v, want %v", tt.in, got, tt.want)
		}
	}
}

func TestBuildTXT(t *testing.T) {
	t.Run("normal name", func(t *testing.T) {
		got := BuildTXT(testAgentID, "Laptop Kantor")
		want := []string{"v=1", "id=" + testAgentID, "name=Laptop Kantor"}
		assertTXT(t, got, want)
	})

	t.Run("empty name omits name key", func(t *testing.T) {
		got := BuildTXT(testAgentID, "")
		want := []string{"v=1", "id=" + testAgentID}
		assertTXT(t, got, want)
	})

	t.Run("long ascii name is cut to 32 runes", func(t *testing.T) {
		long := strings.Repeat("a", 40)
		got := BuildTXT(testAgentID, long)
		want := []string{"v=1", "id=" + testAgentID, "name=" + strings.Repeat("a", 32)}
		assertTXT(t, got, want)
	})

	t.Run("utf-8 name is cut on rune boundary", func(t *testing.T) {
		long := strings.Repeat("ñ", 40)
		got := BuildTXT(testAgentID, long)
		if len(got) != 3 {
			t.Fatalf("len(TXT) = %d, want 3", len(got))
		}
		name := strings.TrimPrefix(got[2], "name=")
		if !utf8.ValidString(name) {
			t.Fatalf("name is not valid UTF-8: %q", name)
		}
		if n := utf8.RuneCountInString(name); n != 32 {
			t.Fatalf("name has %d runes, want 32", n)
		}
	})

	t.Run("mixed utf-8 at the limit keeps every rune", func(t *testing.T) {
		name := strings.Repeat("a", 31) + "日"
		got := BuildTXT(testAgentID, name)
		if got[2] != "name="+name {
			t.Fatalf("name = %q, want %q", got[2], "name="+name)
		}
	})
}

func assertTXT(t *testing.T, got, want []string) {
	t.Helper()
	if len(got) != len(want) {
		t.Fatalf("TXT = %q, want %q", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("TXT[%d] = %q, want %q", i, got[i], want[i])
		}
	}
}
