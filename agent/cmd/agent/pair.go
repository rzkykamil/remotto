package main

import (
	"errors"
	"flag"
	"fmt"
	"io"
	"net/netip"

	"remotto/agent/internal/config"
	"remotto/agent/internal/pairing"
)

// cmdPair prints the pairing QR and the manual pairing fields to stdout. It
// does not start the server and does not write to the log. It creates the
// config on first run, and otherwise keeps the existing token.
func cmdPair(args []string, stdout, stderr io.Writer) int {
	flags := flag.NewFlagSet("pair", flag.ContinueOnError)
	flags.SetOutput(stderr)
	configPath := flags.String("config", "", `path to config.json (default %APPDATA%\Remotto\config.json)`)
	hostFlag := flags.String("host", "", "laptop IPv4 address to show in the QR (default: detected LAN address)")
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

	// Pick the host before touching the config, so a bad --host does not
	// create a config file.
	var host netip.Addr
	if *hostFlag != "" {
		addr, err := pairing.ValidateHostOverride(*hostFlag)
		if err != nil {
			fmt.Fprintf(stderr, "remotto-agent: %v\n", err)
			return 1
		}
		host = addr
	} else {
		addr, err := pairing.DetectHost()
		if err != nil {
			fmt.Fprintf(stderr, "remotto-agent: %v\n", err)
			return 1
		}
		host = addr
	}

	cfg, events, err := loadConfigFile(path)
	if err != nil {
		fmt.Fprintf(stderr, "remotto-agent: %v\n", err)
		return 1
	}
	for _, ev := range events {
		fmt.Fprintln(stdout, describeEvent(ev))
	}

	raw, err := pairing.BuildPayload(cfg.LaptopName, host.String(), cfg.Port, cfg.Token)
	if err != nil {
		fmt.Fprintf(stderr, "remotto-agent: %v\n", err)
		return 1
	}

	fmt.Fprintln(stdout, "Pindai QR ini dari app Remotto:")
	fmt.Fprintln(stdout)
	if err := pairing.RenderQR(stdout, raw); err != nil {
		fmt.Fprintf(stderr, "remotto-agent: %v\n", err)
		return 1
	}
	fmt.Fprintln(stdout)
	fmt.Fprintln(stdout, "Jika kamera tidak bisa memindai, isi manual:")
	fmt.Fprintf(stdout, "  Alamat: %s\n", host)
	fmt.Fprintf(stdout, "  Port:   %d\n", cfg.Port)
	fmt.Fprintf(stdout, "  Token:  %s\n", cfg.Token)
	fmt.Fprintln(stdout)
	fmt.Fprintln(stdout, "Token ini rahasia. Jangan dibagikan ke siapa pun.")
	return 0
}

// describeEvent turns a lifecycle event into a line of text for the user. It
// never includes the token value.
func describeEvent(ev config.Event) string {
	switch ev.Kind {
	case config.EventFirstRun:
		return "Config baru dibuat."
	case config.EventCorruptReplaced:
		return fmt.Sprintf("Config rusak dipindahkan ke %s, config baru dibuat.", ev.Detail)
	case config.EventMigrated:
		return fmt.Sprintf("Config dimigrasi (%s).", ev.Detail)
	case config.EventPermFixed:
		return fmt.Sprintf("Izin %s diperbaiki.", ev.Detail)
	}
	return string(ev.Kind)
}
