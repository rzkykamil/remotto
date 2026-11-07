//go:build windows

package config

import (
	"fmt"
	"os"
	"runtime"
	"unsafe"

	"golang.org/x/sys/windows"
)

// fileAllAccess is FILE_ALL_ACCESS, the mask granted to the owning user.
const fileAllAccess windows.ACCESS_MASK = 0x1F01FF

// inheritMask selects the inheritance bits that a folder ACE carries.
const inheritMask = windows.OBJECT_INHERIT_ACE | windows.CONTAINER_INHERIT_ACE

// NewPermChecker returns a checker that grants access only to the user that
// runs this process, through a protected DACL.
func NewPermChecker() (PermChecker, error) {
	return newUserDACL()
}

// userDACL keeps a path's DACL to one ACE: the current user, full control.
type userDACL struct {
	sid *windows.SID
}

func newUserDACL() (*userDACL, error) {
	tu, err := windows.GetCurrentProcessToken().GetTokenUser()
	if err != nil {
		return nil, fmt.Errorf("read current user: %w", err)
	}
	sid, err := tu.User.Sid.Copy()
	if err != nil {
		return nil, fmt.Errorf("copy user sid: %w", err)
	}
	return &userDACL{sid: sid}, nil
}

// Ensure makes the DACL of path match the expected single ACE. Folders get
// object and container inheritance so that new files inherit the same ACE.
// It returns true when the DACL had to be replaced. Errors name only the
// file system operation, never the file content.
func (d *userDACL) Ensure(path string) (bool, error) {
	info, err := os.Stat(path)
	if err != nil {
		return false, fmt.Errorf("stat permissions: %w", err)
	}
	var inherit uint32 = windows.NO_INHERITANCE
	if info.IsDir() {
		inherit = windows.OBJECT_INHERIT_ACE | windows.CONTAINER_INHERIT_ACE
	}
	ok, err := d.matches(path, inherit)
	if err != nil {
		return false, err
	}
	if ok {
		return false, nil
	}
	if err := d.apply(path, inherit); err != nil {
		return false, err
	}
	return true, nil
}

// matches reports whether the DACL of path has exactly one allowed ACE for
// the user with file_all_access and the expected inheritance. The protected
// flag is not required: a file created inside a secured folder inherits the
// same single ACE, and that is already correct.
func (d *userDACL) matches(path string, inherit uint32) (bool, error) {
	sd, err := windows.GetNamedSecurityInfo(path, windows.SE_FILE_OBJECT, windows.DACL_SECURITY_INFORMATION)
	if err != nil {
		return false, fmt.Errorf("read permissions: %w", err)
	}
	if sd == nil {
		return false, nil
	}
	acl, _, err := sd.DACL()
	if err != nil {
		return false, fmt.Errorf("read dacl: %w", err)
	}
	// A nil DACL grants everyone access, so it is loose.
	if acl == nil || acl.AceCount != 1 {
		return false, nil
	}
	var ace *windows.ACCESS_ALLOWED_ACE
	if err := windows.GetAce(acl, 0, &ace); err != nil {
		return false, fmt.Errorf("read ace: %w", err)
	}
	sid := (*windows.SID)(unsafe.Pointer(&ace.SidStart))
	ok := ace.Header.AceType == windows.ACCESS_ALLOWED_ACE_TYPE &&
		ace.Mask == fileAllAccess &&
		uint32(ace.Header.AceFlags)&inheritMask == inherit &&
		sid.Equals(d.sid)
	runtime.KeepAlive(sd)
	return ok, nil
}

// apply replaces the DACL of path with the single user ACE and blocks
// inheritance from the parent, so no other ACE can come in.
func (d *userDACL) apply(path string, inherit uint32) error {
	entries := []windows.EXPLICIT_ACCESS{{
		AccessPermissions: fileAllAccess,
		AccessMode:        windows.GRANT_ACCESS,
		Inheritance:       inherit,
		Trustee: windows.TRUSTEE{
			TrusteeForm:  windows.TRUSTEE_IS_SID,
			TrusteeValue: windows.TrusteeValueFromSID(d.sid),
		},
	}}
	acl, err := windows.ACLFromEntries(entries, nil)
	if err != nil {
		return fmt.Errorf("build dacl: %w", err)
	}
	var info windows.SECURITY_INFORMATION = windows.DACL_SECURITY_INFORMATION | windows.PROTECTED_DACL_SECURITY_INFORMATION
	if err := windows.SetNamedSecurityInfo(path, windows.SE_FILE_OBJECT, info, nil, nil, acl, nil); err != nil {
		return fmt.Errorf("set dacl: %w", err)
	}
	runtime.KeepAlive(d.sid)
	return nil
}
