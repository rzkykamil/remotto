//go:build !windows

package instance

// acquire has no named mutex outside Windows, so it always succeeds and the
// release does nothing.
func acquire(string) (Release, error) {
	return func() {}, nil
}
