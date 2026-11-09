package oswin

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"unsafe"

	"golang.org/x/sys/windows"

	"remotto/agent/internal/control"
)

// sleepPath names how the agent puts the laptop to sleep.
type sleepPath string

const (
	// pathMonitorOff turns the display off. On Modern Standby hardware (S0 Low
	// Power Idle) Windows then enters the low power idle state by itself.
	pathMonitorOff sleepPath = "monitor_off"
	// pathSuspend calls SetSuspendState for S3 sleep.
	pathSuspend sleepPath = "suspend"
)

// errNoSleepSupport is the cause when the firmware offers neither path.
var errNoSleepSupport = errors.New("no supported sleep state")

// sleepCaps is the part of SYSTEM_POWER_CAPABILITIES that the sleep choice uses.
type sleepCaps struct {
	AoAc bool // S0 Low Power Idle (Modern Standby)
	S3   bool
}

// systemPowerCapabilities mirrors SYSTEM_POWER_CAPABILITIES from winnt.h.
// GetPwrCapabilities writes into it directly, so the field order and sizes
// must match the header exactly. The total is 76 bytes. The layout is checked
// by a test.
type systemPowerCapabilities struct {
	PowerButtonPresent        uint8
	SleepButtonPresent        uint8
	LidPresent                uint8
	SystemS1                  uint8
	SystemS2                  uint8
	SystemS3                  uint8
	SystemS4                  uint8
	SystemS5                  uint8
	HiberFilePresent          uint8
	FullWake                  uint8
	VideoDimPresent           uint8
	ApmPresent                uint8
	UpsPresent                uint8
	ThermalControl            uint8
	ProcessorThrottle         uint8
	ProcessorMinThrottle      uint8
	ProcessorMaxThrottle      uint8
	FastSystemS4              uint8
	Hiberboot                 uint8
	WakeAlarmPresent          uint8
	AoAc                      uint8
	DiskSpinDown              uint8
	HiberFileType             uint8
	AoAcConnectivitySupported uint8
	Spare3                    [6]uint8
	SystemBatteriesPresent    uint8
	BatteriesAreShortTerm     uint8
	BatteriesScale            [3]batteryReportingScale
	AcOnLineWake              int32 // SYSTEM_POWER_STATE
	SoftLidWake               int32 // SYSTEM_POWER_STATE
	RtcWake                   int32 // SYSTEM_POWER_STATE
	MinDeviceWakeState        int32 // SYSTEM_POWER_STATE
	DefaultLowLatencyWake     int32 // SYSTEM_POWER_STATE
}

// batteryReportingScale mirrors BATTERY_REPORTING_SCALE.
type batteryReportingScale struct {
	Granularity uint32
	Capacity    uint32
}

// Constants used by PostMessageW for the monitor-off path (winuser.h).
const (
	hwndBroadcast    = 0xFFFF
	wmSysCommand     = 0x0112
	scMonitorPower   = 0xF170
	monitorPowerOff  = 2 // lParam of SC_MONITORPOWER: 2 turns the display off
	shutdownPrivName = "SeShutdownPrivilege"
)

// chooseSleepPath picks the sleep path for c. AoAc wins over S3, because on
// Modern Standby hardware SetSuspendState can hibernate or fail (decision log,
// Gate 1 sleep entry).
func chooseSleepPath(c sleepCaps) (sleepPath, error) {
	switch {
	case c.AoAc:
		return pathMonitorOff, nil
	case c.S3:
		return pathSuspend, nil
	}
	return "", control.Wrap(control.ErrPower, errNoSleepSupport)
}

// sleepImpl runs one sleep request. The three funcs are fields so tests can
// replace them; production fills them with the real OS calls.
type sleepImpl struct {
	readCaps   func() (sleepCaps, error)
	monitorOff func(ctx context.Context) error
	suspend    func(ctx context.Context) error
	logger     *slog.Logger // nil means slog.Default()
}

// newSleep returns a sleepImpl bound to the production OS calls. It does not
// touch the OS until run is called.
func newSleep(logger *slog.Logger) *sleepImpl {
	return &sleepImpl{
		readCaps:   productionReadCaps(),
		monitorOff: productionMonitorOff(),
		suspend:    productionSuspend(),
		logger:     logger,
	}
}

// run reads the capabilities at call time, picks a path, and runs it. Every
// error it returns matches control.ErrPower, and the OS detail stays reachable
// through Unwrap for logs.
func (s *sleepImpl) run(ctx context.Context) error {
	if err := ctx.Err(); err != nil {
		return control.Wrap(control.ErrPower, err)
	}
	caps, err := s.readCaps()
	if err != nil {
		return control.Wrap(control.ErrPower, fmt.Errorf("read power capabilities: %w", err))
	}
	path, err := chooseSleepPath(caps)
	if err != nil {
		return err
	}

	logger := s.logger
	if logger == nil {
		logger = slog.Default()
	}
	logger.Info("sleep path chosen",
		slog.String("path", string(path)),
		slog.Bool("aoac", caps.AoAc),
		slog.Bool("s3", caps.S3),
	)

	switch path {
	case pathMonitorOff:
		err = s.monitorOff(ctx)
	case pathSuspend:
		err = s.suspend(ctx)
	}
	if err != nil {
		return control.Wrap(control.ErrPower, err)
	}
	return nil
}

// productionReadCaps reads SYSTEM_POWER_CAPABILITIES through
// powrprof.dll!GetPwrCapabilities. It only reads, so it has no effect on power.
func productionReadCaps() func() (sleepCaps, error) {
	proc := windows.NewLazySystemDLL("powrprof.dll").NewProc("GetPwrCapabilities")
	return func() (sleepCaps, error) {
		var c systemPowerCapabilities
		r1, _, callErr := proc.Call(uintptr(unsafe.Pointer(&c)))
		// GetPwrCapabilities returns BOOLEAN. callErr is only the last OS error
		// and is not meaningful when r1 is nonzero.
		if r1 == 0 {
			return sleepCaps{}, fmt.Errorf("GetPwrCapabilities returned FALSE: %v", callErr)
		}
		return sleepCaps{AoAc: c.AoAc != 0, S3: c.SystemS3 != 0}, nil
	}
}

// productionMonitorOff posts SC_MONITORPOWER to all top-level windows. It uses
// PostMessageW, not SendMessage, so a window that does not answer cannot block
// the caller.
func productionMonitorOff() func(ctx context.Context) error {
	proc := windows.NewLazySystemDLL("user32.dll").NewProc("PostMessageW")
	return func(context.Context) error {
		r1, _, callErr := proc.Call(hwndBroadcast, wmSysCommand, scMonitorPower, monitorPowerOff)
		if r1 == 0 {
			return fmt.Errorf("PostMessageW returned FALSE: %v", callErr)
		}
		return nil
	}
}

// productionSuspend enables SeShutdownPrivilege and calls
// powrprof.dll!SetSuspendState(Hibernate=FALSE, ForceCritical=FALSE,
// DisableWakeEvent=FALSE).
func productionSuspend() func(ctx context.Context) error {
	proc := windows.NewLazySystemDLL("powrprof.dll").NewProc("SetSuspendState")
	return func(context.Context) error {
		if err := enableShutdownPrivilege(); err != nil {
			return fmt.Errorf("enable %s: %w", shutdownPrivName, err)
		}
		r1, _, callErr := proc.Call(0, 0, 0)
		if r1 == 0 {
			return fmt.Errorf("SetSuspendState returned FALSE: %v", callErr)
		}
		return nil
	}
}

// enableShutdownPrivilege turns SeShutdownPrivilege on for this process. Windows
// requires it for SetSuspendState.
func enableShutdownPrivilege() error {
	var token windows.Token
	if err := windows.OpenProcessToken(windows.CurrentProcess(), windows.TOKEN_ADJUST_PRIVILEGES|windows.TOKEN_QUERY, &token); err != nil {
		return fmt.Errorf("open process token: %w", err)
	}
	defer token.Close()

	name, err := windows.UTF16PtrFromString(shutdownPrivName)
	if err != nil {
		return fmt.Errorf("encode privilege name: %w", err)
	}
	var luid windows.LUID
	if err := windows.LookupPrivilegeValue(nil, name, &luid); err != nil {
		return fmt.Errorf("lookup privilege value: %w", err)
	}
	tp := windows.Tokenprivileges{
		PrivilegeCount: 1,
		Privileges: [1]windows.LUIDAndAttributes{
			{Luid: luid, Attributes: windows.SE_PRIVILEGE_ENABLED},
		},
	}
	if err := windows.AdjustTokenPrivileges(token, false, &tp, 0, nil, nil); err != nil {
		return fmt.Errorf("adjust token privileges: %w", err)
	}
	return nil
}
