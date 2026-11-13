package discovery

import "regexp"

// agentIDPattern matches the agentId format: 32 lowercase hex characters.
var agentIDPattern = regexp.MustCompile(`^[0-9a-f]{32}$`)

// ValidAgentID reports whether s has the agentId format.
func ValidAgentID(s string) bool {
	return agentIDPattern.MatchString(s)
}

// InstanceName returns the DNS-SD instance name, "Remotto-" followed by the
// first 8 characters of agentID. A shorter ID is used whole and does not panic.
func InstanceName(agentID string) string {
	id := agentID
	if len(id) > 8 {
		id = id[:8]
	}
	return "Remotto-" + id
}

// BuildTXT returns the TXT records for the advertisement: v (schema version),
// id (agentId), and name (laptop name, at most 32 runes). The name key is
// left out when the name is empty. The token never appears here; this
// function takes no token parameter.
func BuildTXT(agentID, name string) []string {
	txt := []string{"v=" + TXTVersion, "id=" + agentID}
	if n := truncateRunes(name, maxNameRunes); n != "" {
		txt = append(txt, "name="+n)
	}
	return txt
}

// truncateRunes returns at most max runes of s. It cuts only at rune
// boundaries, so UTF-8 sequences are never split.
func truncateRunes(s string, limit int) string {
	count := 0
	for i := range s {
		if count == limit {
			return s[:i]
		}
		count++
	}
	return s
}
