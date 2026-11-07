package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"io"
	"io/fs"
	"log/slog"
	"net"
	"os"
	"path/filepath"
	"strconv"
	"time"

	"remotto/agent/internal/config"
	"remotto/agent/internal/logging"
	"remotto/agent/internal/server"
)

const usageText = `Usage: remotto-agent <perintah>

Perintah:
  run                 jalankan agent
  version             cetak versi
  help                tampilkan bantuan
  pair                pasangkan ponsel (belum tersedia)
  reset-token         buat ulang token (belum tersedia)
  install-startup     pasang autostart (belum tersedia)
  uninstall-startup   hapus autostart (belum tersedia)

Opsi run:
  --config <path>     file config.json (default %APPDATA%\Remotto\config.json)
  --background        jalankan tanpa konsol (belum berefek)
`

// plannedCommands are subcommands reserved for later milestones (M1 and M6).
var plannedCommands = map[string]bool{
	"pair":              true,
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
	}
	if plannedCommands[args[0]] {
		fmt.Fprintf(stderr, "perintah %q belum tersedia di versi ini\n", args[0])
		return 1
	}
	fmt.Fprintf(stderr, "perintah tidak dikenal: %s\n", args[0])
	fmt.Fprint(stderr, usageText)
	return 2
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

	path := *configPath
	if path == "" {
		p, err := config.DefaultPath()
		if err != nil {
			fmt.Fprintf(stderr, "remotto-agent: %v\n", err)
			return 1
		}
		path = p
	}

	hostname, _ := os.Hostname()
	defaults := config.Default(hostname, time.Now())
	cfg, err := config.Load(path, defaults)
	missing := false
	if err != nil {
		if !errors.Is(err, fs.ErrNotExist) {
			fmt.Fprintf(stderr, "remotto-agent: %v\n", err)
			return 1
		}
		// No config file yet. The file itself is created in M1, so run on
		// in-memory defaults and write nothing.
		cfg = defaults
		missing = true
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

	if missing {
		logger.Warn("config file not found, using in-memory defaults", slog.String("path", path))
	}

	// M2 to M4 connect these controllers to the handlers. Until then nothing
	// reads them, so they are only built here.
	ctrl := newControllers()
	_ = ctrl

	router := server.NewRouter()
	handler := server.NewHandler(router, logger)
	addr := net.JoinHostPort(cfg.BindAddress, strconv.Itoa(cfg.Port))
	ln, err := net.Listen("tcp", addr)
	if err != nil {
		logger.Error("listen failed", slog.String("addr", addr), slog.String("error", err.Error()))
		fmt.Fprintf(stderr, "remotto-agent: gagal membuka %s: %v\n", addr, err)
		return 1
	}
	if err := server.Serve(ctx, server.NewHTTPServer(addr, handler), ln, logger); err != nil {
		logger.Error("server failed", slog.String("error", err.Error()))
		fmt.Fprintf(stderr, "remotto-agent: server berhenti dengan error: %v\n", err)
		return 1
	}
	return 0
}
