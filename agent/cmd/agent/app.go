package main

import (
	"context"
	"crypto/rand"
	"errors"
	"flag"
	"fmt"
	"io"
	"log/slog"
	"net"
	"os"
	"path/filepath"
	"time"

	"remotto/agent/internal/config"
	"remotto/agent/internal/control"
	"remotto/agent/internal/instance"
	"remotto/agent/internal/logging"
	"remotto/agent/internal/pairing"
	"remotto/agent/internal/server"
)

const usageText = `Usage: remotto-agent <perintah>

Perintah:
  run                 jalankan agent
  version             cetak versi
  help                tampilkan bantuan
  pair                tampilkan QR dan teks pairing
  reset-token         buat ulang token (belum tersedia)
  install-startup     pasang autostart
  uninstall-startup   hapus autostart

Opsi run:
  --config <path>     file config.json (default %APPDATA%\Remotto\config.json)
  --background        jalankan tanpa konsol, log hanya ke file

Opsi pair:
  --config <path>     file config.json (default %APPDATA%\Remotto\config.json)
  --host <ipv4>       alamat laptop di QR (default: adapter LAN terdeteksi)
`

// acquireInstance takes the single-instance lock before any config, log or
// listener is touched. Tests replace it so they never depend on a running agent.
var acquireInstance = func() (instance.Release, error) {
	return instance.Acquire(instance.MutexName)
}

// detach releases the console for run --background. Tests replace it so they
// never call FreeConsole.
var detach = detachConsole

// plannedCommands are subcommands reserved for later milestones (M5).
var plannedCommands = map[string]bool{
	"reset-token": true,
}

// run dispatches the subcommand in args and returns the process exit code.
func run(ctx context.Context, args []string, stdout, stderr io.Writer) int {
	if len(args) == 0 {
		fmt.Fprint(stderr, usageText)
		return 2
	}
	switch args[0] {
	case "-h", "--help", "help":
		fmt.Fprint(stdout, usageText)
		return 0
	case "version":
		fmt.Fprintf(stdout, "remotto-agent %s\n", version)
		return 0
	case "run":
		return cmdRun(ctx, args[1:], stdout, stderr)
	case "pair":
		return cmdPair(args[1:], stdout, stderr)
	case "install-startup":
		return cmdInstallStartup(stdout, stderr, args[1:])
	case "uninstall-startup":
		return cmdUninstallStartup(stdout, stderr, args[1:])
	}
	if plannedCommands[args[0]] {
		fmt.Fprintf(stderr, "perintah %q belum tersedia di versi ini\n", args[0])
		return 1
	}
	fmt.Fprintf(stderr, "perintah tidak dikenal: %s\n", args[0])
	fmt.Fprint(stderr, usageText)
	return 2
}

// defaultConfigPath returns path, or the default config.json when path is empty.
func defaultConfigPath(path string) (string, error) {
	if path != "" {
		return path, nil
	}
	return config.DefaultPath()
}

// loadConfigFile creates, repairs, migrates or loads the config at path. It
// secures the config folder and file with the platform permission checker
// first. Errors never include the token value.
func loadConfigFile(path string) (config.Config, []config.Event, error) {
	perm, err := config.NewPermChecker()
	if err != nil {
		return config.Config{}, nil, err
	}
	hostname, _ := os.Hostname()
	defaults := config.Default(hostname, time.Now())
	return config.LoadOrInit(path, defaults, func() (string, error) {
		return pairing.GenerateToken(rand.Reader)
	}, perm, time.Now())
}

// logEvent writes one lifecycle event to the log. Events carry no token value.
func logEvent(logger *slog.Logger, ev config.Event) {
	switch ev.Kind {
	case config.EventFirstRun:
		logger.Info("config created", slog.String("event", string(ev.Kind)))
	case config.EventCorruptReplaced:
		logger.Warn("config was unreadable, moved aside and replaced", slog.String("event", string(ev.Kind)), slog.String("file", ev.Detail))
	case config.EventMigrated:
		logger.Info("config migrated", slog.String("event", string(ev.Kind)), slog.String("detail", ev.Detail))
	case config.EventPermFixed:
		logger.Warn("config permissions tightened", slog.String("event", string(ev.Kind)), slog.String("file", ev.Detail))
	default:
		logger.Info("config event", slog.String("event", string(ev.Kind)))
	}
}

// cmdRun loads the config, opens the log, and serves HTTP until ctx is done.
func cmdRun(ctx context.Context, args []string, stdout, stderr io.Writer) int {
	flags := flag.NewFlagSet("run", flag.ContinueOnError)
	flags.SetOutput(stderr)
	configPath := flags.String("config", "", `path to config.json (default %APPDATA%\Remotto\config.json)`)
	background := flags.Bool("background", false, "run without a console; log to file only")
	if err := flags.Parse(args); err != nil {
		if errors.Is(err, flag.ErrHelp) {
			return 0
		}
		return 2
	}
	if flags.NArg() > 0 {
		fmt.Fprintf(stderr, "remotto-agent: argumen tidak dikenal: %s\n", flags.Arg(0))
		return 2
	}

	release, err := acquireInstance()
	if err != nil {
		if errors.Is(err, instance.ErrAlreadyRunning) {
			fmt.Fprintln(stderr, "remotto-agent: agent sudah berjalan di sesi ini")
			return 1
		}
		fmt.Fprintf(stderr, "remotto-agent: %v\n", err)
		return 1
	}
	defer release()

	// Detach before config and log are touched. A failure does not stop the
	// agent; it is logged once the logger exists.
	var detachErr error
	if *background {
		detachErr = detach()
	}

	path, err := defaultConfigPath(*configPath)
	if err != nil {
		fmt.Fprintf(stderr, "remotto-agent: %v\n", err)
		return 1
	}

	// The config must be valid before the log and the listener exist, so a
	// bad config leaves no logs folder and opens no port.
	cfg, events, err := loadConfigFile(path)
	if err != nil {
		fmt.Fprintf(stderr, "remotto-agent: %v\n", err)
		return 1
	}

	var console io.Writer = stderr
	if *background {
		// Without a console, JSON lines go to agent.log only.
		console = nil
	}
	logger, closer, err := logging.New(logging.Options{
		Level:   cfg.LogLevel,
		File:    filepath.Join(filepath.Dir(path), "logs", "agent.log"),
		Console: console,
	})
	if err != nil {
		fmt.Fprintf(stderr, "remotto-agent: %v\n", err)
		return 1
	}
	defer func() { _ = closer.Close() }()
	// Packages without a logger of their own (oswin logs the sleep path through
	// slog.Default) must write to the same JSON file. The previous default is
	// restored when run returns.
	prevDefault := slog.Default()
	slog.SetDefault(logger)
	defer slog.SetDefault(prevDefault)

	if detachErr != nil {
		logger.Warn("console detach failed", slog.String("error", detachErr.Error()))
	}
	for _, ev := range events {
		logEvent(logger, ev)
	}

	ctrl := newControllers()
	// Runs after serveAgent returns, so no request can reach the audio port
	// while it closes.
	defer closeAudio(logger, ctrl.Audio)
	status := server.StatusDeps{
		Name:      cfg.LaptopName,
		Version:   version,
		StartedAt: time.Now(),
		Now:       time.Now,
		Audio:     ctrl.Audio,
	}

	addr := net.JoinHostPort(cfg.BindAddress, fmt.Sprint(cfg.Port))
	ln, err := listenAgent(addr, cfg.Port)
	if err != nil {
		logger.Error("listen failed", slog.String("addr", addr), slog.String("error", err.Error()))
		fmt.Fprintf(stderr, "remotto-agent: gagal membuka %s: %v\n", addr, err)
		return 1
	}
	if err := serveAgent(ctx, ln, logger, path, cfg, status, ctrl.Media, ctrl.Audio, ctrl.Power); err != nil {
		logger.Error("server failed", slog.String("error", err.Error()))
		fmt.Fprintf(stderr, "remotto-agent: server berhenti dengan error: %v\n", err)
		return 1
	}
	return 0
}

// closeAudio closes the audio port when it implements io.Closer, so its COM
// worker stops at shutdown. A failure is logged as a warning and does not stop
// the shutdown.
func closeAudio(logger *slog.Logger, audio control.AudioController) {
	c, ok := audio.(io.Closer)
	if !ok {
		return
	}
	if err := c.Close(); err != nil {
		logger.Warn("audio close failed", slog.String("error", err.Error()))
	}
}

// serveAgent serves the API on ln until ctx is done. The token comes from the
// config file at cfgPath, so a token reset takes effect without a restart
// (BR-10). media is the media port behind /media/*, audio the volume port
// behind /volume, and power the OS port behind /power/*. Power commands go
// through a control.PowerScheduler owned by this call. When serveAgent returns,
// the scheduler is closed, so a pending power command is discarded and never
// runs (docs/technical-spec.md, graceful shutdown). It returns nil on a normal
// stop.
func serveAgent(ctx context.Context, ln net.Listener, logger *slog.Logger, cfgPath string, cfg config.Config, status server.StatusDeps, media control.MediaController, audio control.AudioController, power control.PowerController) error {
	sched := control.NewPowerScheduler(power, control.PowerOptions{Logger: logger})
	defer sched.Close()

	tokens := server.NewConfigTokenSource(cfgPath, cfg.Token, logger)
	handler := server.NewAPIHandler(logger, tokens, status,
		server.WithMedia(media),
		server.WithAudio(audio),
		server.WithPower(sched),
		server.WithRateLimit(cfg.RateLimit.RequestsPerSecond, cfg.RateLimit.Burst),
	)
	srv := server.NewHTTPServer(ln.Addr().String(), handler)
	return server.Serve(ctx, srv, ln, logger)
}
