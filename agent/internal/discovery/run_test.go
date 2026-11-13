package discovery

import (
	"context"
	"errors"
	"strings"
	"testing"
	"time"
)

func TestRunDisabledMakesNoCalls(t *testing.T) {
	o := testOptions()
	o.Enabled = false
	h := newHarness(t, o)
	h.lister.set([]Iface{lanIface("Wi-Fi", 3, "192.168.1.10")}, nil)
	h.start()
	h.waitDone()

	if n := h.lister.callCount(); n != 0 {
		t.Errorf("List calls = %d, want 0", n)
	}
	if n := h.reg.attemptCount(); n != 0 {
		t.Errorf("Register calls = %d, want 0", n)
	}
	if n := len(h.clock.intervals()); n != 0 {
		t.Errorf("After calls = %d, want 0", n)
	}
}

func TestRunInvalidAgentIDMakesNoCalls(t *testing.T) {
	cases := map[string]string{
		"empty":     "",
		"uppercase": strings.ToUpper(testAgentID),
		"short":     testAgentID[:31],
	}
	for name, id := range cases {
		t.Run(name, func(t *testing.T) {
			o := testOptions()
			o.AgentID = id
			h := newHarness(t, o)
			h.lister.set([]Iface{lanIface("Wi-Fi", 3, "192.168.1.10")}, nil)
			h.start()
			h.waitDone()

			if n := h.lister.callCount(); n != 0 {
				t.Errorf("List calls = %d, want 0", n)
			}
			if n := h.reg.attemptCount(); n != 0 {
				t.Errorf("Register calls = %d, want 0", n)
			}
		})
	}
}

// TestRunNilLoggerDisabled checks that a nil Logger falls back to slog.Default
// without panicking.
func TestRunNilLoggerDisabled(t *testing.T) {
	o := testOptions()
	o.Enabled = false
	o.Logger = nil
	done := make(chan struct{})
	go func() {
		defer close(done)
		Run(context.Background(), o)
	}()
	select {
	case <-done:
	case <-time.After(harnessWait):
		t.Fatal("Run did not return for disabled options")
	}
}

func TestRunRegistersOnceWhileAddressesStable(t *testing.T) {
	h := newHarness(t, testOptions())
	h.lister.set([]Iface{lanIface("Wi-Fi", 3, "192.168.1.10")}, nil)
	h.start()
	h.park()
	h.poll()
	h.poll()

	if got, want := h.reg.eventLog(), []string{"register 192.168.1.10"}; !equalStrings(got, want) {
		t.Fatalf("events = %v, want %v", got, want)
	}
	if n := h.lister.callCount(); n != 3 {
		t.Errorf("List calls = %d, want 3", n)
	}

	svc := h.reg.serviceList()[0]
	if svc.Instance != "Remotto-01234567" {
		t.Errorf("Instance = %q, want Remotto-01234567", svc.Instance)
	}
	if svc.Type != ServiceType {
		t.Errorf("Type = %q, want %q", svc.Type, ServiceType)
	}
	if svc.Port != testPort {
		t.Errorf("Port = %d, want %d", svc.Port, testPort)
	}
	wantTXT := []string{"v=1", "id=" + testAgentID, "name=" + testName}
	if !equalStrings(svc.TXT, wantTXT) {
		t.Errorf("TXT = %v, want %v", svc.TXT, wantTXT)
	}
	if len(svc.Ifaces) != 1 || svc.Ifaces[0].Name != "Wi-Fi" {
		t.Errorf("Ifaces = %+v, want one interface named Wi-Fi", svc.Ifaces)
	}
	if len(svc.IPs) != 1 || svc.IPs[0].String() != "192.168.1.10" {
		t.Errorf("IPs = %v, want [192.168.1.10]", svc.IPs)
	}
	if strings.Contains(h.logs.String(), testName) {
		t.Errorf("log output contains the TXT name value")
	}

	h.stop()
}

func TestRunReregistersWhenAddressChanges(t *testing.T) {
	h := newHarness(t, testOptions())
	h.lister.set([]Iface{lanIface("Wi-Fi", 3, "192.168.1.10")}, nil)
	h.start()
	h.park()

	h.lister.set([]Iface{lanIface("Wi-Fi", 3, "192.168.1.20")}, nil)
	h.poll()

	want := []string{"register 192.168.1.10", "close", "register 192.168.1.20"}
	if got := h.reg.eventLog(); !equalStrings(got, want) {
		t.Fatalf("events = %v, want %v", got, want)
	}
	svcs := h.reg.serviceList()
	if svcs[1].Port != testPort || svcs[1].Instance != svcs[0].Instance {
		t.Errorf("re-registration changed port or instance: %+v", svcs[1])
	}
	h.stop()
}

func TestRunInterfaceGoneAndBack(t *testing.T) {
	h := newHarness(t, testOptions())
	h.lister.set([]Iface{lanIface("Wi-Fi", 3, "192.168.1.10")}, nil)
	h.start()
	h.park()

	h.lister.set(nil, nil)
	h.poll()
	h.lister.set([]Iface{lanIface("Wi-Fi", 3, "192.168.1.10")}, nil)
	h.poll()

	want := []string{"register 192.168.1.10", "close", "register 192.168.1.10"}
	if got := h.reg.eventLog(); !equalStrings(got, want) {
		t.Fatalf("events = %v, want %v", got, want)
	}
	h.stop()
}

func TestRunNoInterfaceAtStartRegistersWhenOneAppears(t *testing.T) {
	h := newHarness(t, testOptions())
	h.lister.set(nil, nil)
	h.start()
	h.park()
	h.poll()

	if got := h.reg.eventLog(); len(got) != 0 {
		t.Fatalf("events while no interface = %v, want none", got)
	}

	h.lister.set([]Iface{lanIface("Wi-Fi", 3, "192.168.1.10")}, nil)
	h.poll()

	if got, want := h.reg.eventLog(), []string{"register 192.168.1.10"}; !equalStrings(got, want) {
		t.Fatalf("events = %v, want %v", got, want)
	}
	h.stop()
}

func TestRunRegisterFailureIsRetried(t *testing.T) {
	h := newHarness(t, testOptions())
	h.reg.failNext = 2
	h.lister.set([]Iface{lanIface("Wi-Fi", 3, "192.168.1.10")}, nil)
	h.start()
	h.park()
	h.poll()
	h.poll()

	select {
	case <-h.done:
		t.Fatal("run stopped after register failures")
	default:
	}
	if n := h.reg.attemptCount(); n != 3 {
		t.Errorf("Register attempts = %d, want 3", n)
	}
	if got, want := h.reg.eventLog(), []string{"register 192.168.1.10"}; !equalStrings(got, want) {
		t.Fatalf("events = %v, want %v", got, want)
	}
	h.stop()
}

func TestRunListErrorKeepsRegistration(t *testing.T) {
	h := newHarness(t, testOptions())
	h.lister.set([]Iface{lanIface("Wi-Fi", 3, "192.168.1.10")}, nil)
	h.start()
	h.park()

	h.lister.set(nil, errors.New("fake list failure"))
	h.poll()
	h.poll()
	h.lister.set([]Iface{lanIface("Wi-Fi", 3, "192.168.1.10")}, nil)
	h.poll()

	if got, want := h.reg.eventLog(), []string{"register 192.168.1.10"}; !equalStrings(got, want) {
		t.Fatalf("events = %v, want %v (list error must not withdraw)", got, want)
	}
	h.stop()
}

func TestRunStopWithdrawsActiveRegistration(t *testing.T) {
	h := newHarness(t, testOptions())
	h.lister.set([]Iface{lanIface("Wi-Fi", 3, "192.168.1.10")}, nil)
	h.start()
	h.park()
	h.stop()

	want := []string{"register 192.168.1.10", "close"}
	if got := h.reg.eventLog(); !equalStrings(got, want) {
		t.Fatalf("events = %v, want %v", got, want)
	}
}

func TestRunIntervalDefaultsAndCustom(t *testing.T) {
	cases := []struct {
		name     string
		interval time.Duration
		want     time.Duration
	}{
		{"default", 0, DefaultInterval},
		{"custom", 3 * time.Second, 3 * time.Second},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			o := testOptions()
			o.Interval = tc.interval
			h := newHarness(t, o)
			h.lister.set(nil, nil)
			h.start()
			h.park()
			h.poll()
			h.stop()

			for i, d := range h.clock.intervals() {
				if d != tc.want {
					t.Errorf("interval[%d] = %v, want %v", i, d, tc.want)
				}
			}
		})
	}
}
