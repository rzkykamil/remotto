//go:build windows && manual

package config

import (
	"path/filepath"
	"testing"

	"golang.org/x/sys/windows"
)

// loosen replaces the DACL of path with an unprotected one that also grants
// Everyone full control. It only touches a t.TempDir path.
func loosen(t *testing.T, path string, user *windows.SID) {
	t.Helper()
	everyone, err := windows.StringToSid("S-1-1-0")
	if err != nil {
		t.Fatalf("parse Everyone sid: %v", err)
	}
	entries := []windows.EXPLICIT_ACCESS{
		{
			AccessPermissions: fileAllAccess,
			AccessMode:        windows.GRANT_ACCESS,
			Trustee: windows.TRUSTEE{
				TrusteeForm:  windows.TRUSTEE_IS_SID,
				TrusteeValue: windows.TrusteeValueFromSID(user),
			},
		},
		{
			AccessPermissions: fileAllAccess,
			AccessMode:        windows.GRANT_ACCESS,
			Trustee: windows.TRUSTEE{
				TrusteeForm:  windows.TRUSTEE_IS_SID,
				TrusteeValue: windows.TrusteeValueFromSID(everyone),
			},
		},
	}
	acl, err := windows.ACLFromEntries(entries, nil)
	if err != nil {
		t.Fatalf("build loose dacl: %v", err)
	}
	var info windows.SECURITY_INFORMATION = windows.DACL_SECURITY_INFORMATION | windows.UNPROTECTED_DACL_SECURITY_INFORMATION
	if err := windows.SetNamedSecurityInfo(path, windows.SE_FILE_OBJECT, info, nil, nil, acl, nil); err != nil {
		t.Fatalf("loosen dacl: %v", err)
	}
}

func TestUserDACLEnsureRepairsLooseDACL(t *testing.T) {
	perm, err := newUserDACL()
	if err != nil {
		t.Fatalf("newUserDACL() error: %v", err)
	}

	folder := t.TempDir()
	file := filepath.Join(t.TempDir(), "config.json")
	writeFile(t, file, "{}")

	for _, tc := range []struct {
		name string
		path string
	}{
		{name: "folder", path: folder},
		{name: "file", path: file},
	} {
		t.Run(tc.name, func(t *testing.T) {
			loosen(t, tc.path, perm.sid)

			fixed, err := perm.Ensure(tc.path)
			if err != nil {
				t.Fatalf("Ensure() error: %v", err)
			}
			if !fixed {
				t.Fatal("Ensure() fixed = false, want true for loose DACL")
			}

			sd, err := windows.GetNamedSecurityInfo(tc.path, windows.SE_FILE_OBJECT, windows.DACL_SECURITY_INFORMATION)
			if err != nil {
				t.Fatalf("read dacl: %v", err)
			}
			control, _, err := sd.Control()
			if err != nil {
				t.Fatalf("read control: %v", err)
			}
			if control&windows.SE_DACL_PROTECTED == 0 {
				t.Fatal("DACL is not protected after repair")
			}

			fixed, err = perm.Ensure(tc.path)
			if err != nil {
				t.Fatalf("second Ensure() error: %v", err)
			}
			if fixed {
				t.Fatal("second Ensure() fixed = true, want false")
			}
		})
	}
}
