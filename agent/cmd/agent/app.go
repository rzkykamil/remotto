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
  install-startup     pasang autostart (belum tersedia)
  uninstall-startup   hapus autostart (belum tersedia)

Opsi run:
  --config <path>     file config.json (default %APPDATA%\Remotto\config.json)
  --background        jalankan tanpa konsol (belum berefek)

Opsi pair:
  --config <path>     file config.json (default %APPDATA%\Remotto\config.json)
  --host <ipv4>       alamat laptop di QR (default: adapter LAN terdeteksi)
`

// plannedCommands are subcommands reserved for later milestones (M1 and M6).
var plannedCommands = map[string]bool{
	"reset-token":       true,
	"install-startup":   true,
	"uninstall-startup": true,
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
	// --background is accepted so the Task Scheduler entry in M6 does not fail.
	// It has no effect yet.
	flags.Bool("background", false, "run without a console (no effect yet)")
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

	logger, closer, err := logging.New(logging.Options{
		Level:   cfg.LogLevel,
		File:    filepath.Join(filepath.Dir(path), "logs", "agent.log"),
		Console: stderr,
	})
	if err != nil {
		fmt.Fprintf(stderr, "remotto-agent: %v\n", err)
		return 1
	}
	defer func() { _ = closer.Close() }()

	for _, ev := range events {
		logEvent(logger, ev)
	}

	ctrl := newControllers()
	status := server.StatusDeps{
		Name:      cfg.LaptopName,
		Version:   version,
		StartedAt: time.Now(),
		Now:       time.Now,
		Audio:     ctrl.Audio,
	}

	addr := net.JoinHostPort(cfg.BindAddress, fmt.Sprint(cfg.Port))
	ln, err := net.Listen("tcp", addr)
	if err != nil {
		logger.Error("listen failed", slog.String("addr", addr), slog.String("error", err.Error()))
		fmt.Fprintf(stderr, "remotto-agent: gagal membuka %s: %v\n", addr, err)
		return 1
	}
	if err := serveAgent(ctx, ln, logger, path, cfg, status); err != nil {
		logger.Error("server failed", slog.String("error", err.Error()))
		fmt.Fprintf(stderr, "remotto-agent: server berhenti dengan error: %v\n", err)
		return 1
	}
	return 0
}

// serveAgent serves the API on ln until ctx is done. The token comes from the
// config file at cfgPath, so a token reset takes effect without a restart
// (BR-10). It returns nil on a normal stop.
func serveAgent(ctx context.Context, ln net.Listener, logger *slog.Logger, cfgPath string, cfg config.Config, status server.StatusDeps) error {
	tokens := server.NewConfigTokenSource(cfgPath, cfg.Token, logger)
	handler := server.NewAPIHandler(logger, tokens, status)
	srv := server.NewHTTPServer(ln.Addr().String(), handler)
	return server.Serve(ctx, srv, ln, logger)
}
