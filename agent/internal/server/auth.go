package server

import (
	"crypto/subtle"
	"log/slog"
	"net/http"
	"os"
	"strings"
	"sync"
	"time"

	"remotto/agent/internal/config"
	"remotto/agent/internal/pairing"
)

// TokenSource returns the token a request must present. An empty string means
// no token is accepted, so every request is rejected (fail closed).
type TokenSource interface {
	Token() string
}

// tokenFileDefaults only supplies the fields that config.Load needs when the
// file omits them. Only the token is read from the result.
var tokenFileDefaults = config.Default("", time.Time{})

// fileSignature identifies one state of config.json. ok is false when the
// file could not be stat'ed.
type fileSignature struct {
	modTime time.Time
	size    int64
	ok      bool
}

// ConfigTokenSource serves the token stored in config.json. It checks the
// file on every Token call and reloads it when the modification time or the
// size changes, so a token reset takes effect without restarting the agent
// (BR-10). A failed reload keeps the last valid token. Warnings never include
// the token value.
type ConfigTokenSource struct {
	path   string
	logger *slog.Logger

	mu    sync.RWMutex
	token string
	sig   fileSignature
}

// NewConfigTokenSource returns a source that starts with initial, the token
// read at startup. An initial value with an invalid format is treated as
// empty. The file state is recorded now, so only later changes trigger a
// reload.
func NewConfigTokenSource(path, initial string, logger *slog.Logger) *ConfigTokenSource {
	if !pairing.ValidToken(initial) {
		initial = ""
	}
	return &ConfigTokenSource{
		path:   path,
		logger: logger,
		token:  initial,
		sig:    statSignature(path),
	}
}

// Token returns the current token. It reloads config.json first when the file
// has changed since the last check.
func (s *ConfigTokenSource) Token() string {
	sig := statSignature(s.path)

	s.mu.RLock()
	unchanged := sig == s.sig
	s.mu.RUnlock()
	if unchanged {
		s.mu.RLock()
		defer s.mu.RUnlock()
		return s.token
	}

	s.mu.Lock()
	defer s.mu.Unlock()
	if sig == s.sig {
		return s.token
	}
	// Record the state first, so a failing file is reported once per change
	// and not on every request.
	s.sig = sig
	if !sig.ok {
		s.logger.Warn("config file unreadable, keeping last token", slog.String("path", s.path))
		return s.token
	}

	cfg, err := config.Load(s.path, tokenFileDefaults)
	if err != nil {
		s.logger.Warn("config reload failed, keeping last token", slog.String("error", err.Error()))
		return s.token
	}
	if !pairing.ValidToken(cfg.Token) {
		s.token = ""
		s.logger.Warn("config token invalid, rejecting all requests until config is fixed")
		return s.token
	}
	if cfg.Token != s.token {
		s.logger.Info("token reloaded from config")
	}
	s.token = cfg.Token
	return s.token
}

func statSignature(path string) fileSignature {
	fi, err := os.Stat(path)
	if err != nil {
		return fileSignature{}
	}
	return fileSignature{modTime: fi.ModTime(), size: fi.Size(), ok: true}
}

// Auth rejects requests without a valid "Authorization: Bearer <token>"
// header with 401 invalid_token. The scheme is case-insensitive and the token
// is compared in constant time. The response never includes the token. The
// logging middleware records the failed request.
func Auth(src TokenSource) Middleware {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if !authorized(src.Token(), r.Header.Get("Authorization")) {
				WriteError(w, http.StatusUnauthorized, CodeInvalidToken, "invalid token")
				return
			}
			next.ServeHTTP(w, r)
		})
	}
}

// authorized reports whether header carries the expected token. An empty
// expected token never matches.
func authorized(expected, header string) bool {
	if expected == "" {
		return false
	}
	scheme, presented, found := strings.Cut(header, " ")
	if !found || !strings.EqualFold(scheme, "Bearer") {
		return false
	}
	if len(presented) != len(expected) {
		return false
	}
	return subtle.ConstantTimeCompare([]byte(presented), []byte(expected)) == 1
}
