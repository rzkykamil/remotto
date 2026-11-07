package config

// PermChecker secures a config path (folder or file) so that only the owning
// user can read it. Implementations live in the platform files (T3).
//
// Ensure reports whether the permissions were loose and had to be fixed.
// It never includes the file content in its errors.
type PermChecker interface {
	Ensure(path string) (fixed bool, err error)
}
