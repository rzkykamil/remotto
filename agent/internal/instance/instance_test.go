//go:build windows

package instance

import (
	"crypto/rand"
	"encoding/hex"
	"errors"
	"testing"
)

// uniqueName returns a mutex name no other test or agent uses.
func uniqueName(t *testing.T) string {
	t.Helper()
	b := make([]byte, 8)
	if _, err := rand.Read(b); err != nil {
		t.Fatal(err)
	}
	return `Local\RemottoAgentTest-` + hex.EncodeToString(b)
}

func TestAcquireSecondTimeFailsUntilRelease(t *testing.T) {
	name := uniqueName(t)

	release, err := Acquire(name)
	if err != nil {
		t.Fatalf("first Acquire: %v", err)
	}

	if _, err := Acquire(name); !errors.Is(err, ErrAlreadyRunning) {
		t.Fatalf("second Acquire err = %v, want ErrAlreadyRunning", err)
	}

	release()

	release2, err := Acquire(name)
	if err != nil {
		t.Fatalf("Acquire after release: %v", err)
	}
	release2()
}

func TestReleaseTwiceDoesNotPanic(t *testing.T) {
	release, err := Acquire(uniqueName(t))
	if err != nil {
		t.Fatalf("Acquire: %v", err)
	}
	release()
	release()
}
