# Backend (agent Go)

Setiap task endpoint menyertakan sub-task "sinkronkan `postman/`".

## M0 Fondasi Proyek

- [x] `go mod init` di `agent/` dengan Go 1.27
- [x] Kerangka subcommand di `cmd/agent` dan variabel `version`
- [x] `internal/logging`: slog JSON ke file + konsol, rotasi selesai di M6
- [x] `internal/config`: path, default, baca, validasi, tulis atomik + test
- [x] Kerangka `internal/server`: router, envelope respons, recover, logging + test
- [x] Interface `MediaController`, `AudioController`, `PowerController` di `internal/control`
- [x] Implementasi `internal/oscontrol/fake`
- [x] Stub non-Windows di `cmd/agent`

## M1 Pairing & Koneksi

- [x] Pembuatan token 256 bit saat first run + test
- [x] DACL config dan folder (`_windows.go`) + pemeriksaan saat start
- [x] Migrasi versi dan penanganan file rusak + test
- [x] Middleware filter jaringan + test
- [x] Middleware auth constant-time + test semua route
- [x] Muat ulang token lewat waktu modifikasi config + test BR-10
- [x] Pemilihan host LAN + opsi `--host` + test
- [x] Perintah `pair` dengan QR dan teks
- [x] `GET /status` + test
  - [x] Sinkronkan `postman/`
- [x] Penulisan log akses tanpa token + test BR-11

## M2 Kontrol Media

- [x] Domain media + test
- [x] `SendInput` di `internal/oswin`
- [x] `POST /media/play-pause`, `/media/next`, `/media/prev` + test
  - [x] Sinkronkan `postman/`

## M3 Volume

- [x] Domain volume: batas 0–100, langkah 5, unmute saat level berubah + test BR-3, BR-15, BR-16
- [x] Pekerja COM Core Audio di `internal/oswin`
- [x] Field `volume` di `/status`, `null` saat audio gagal
- [x] `GET /volume` dan `PUT /volume` + test
  - [x] Sinkronkan `postman/`
- [x] `POST /volume/up` dan `/volume/down` + test
  - [x] Sinkronkan `postman/`
- [x] `POST /volume/mute` + test
  - [x] Sinkronkan `postman/`

## M4 Daya

- [x] Scheduler dengan clock palsu: jeda, batal, jadwal kedua, eksekusi, gagal + test BR-4, BR-5, BR-17
- [x] Field `pending` di `/status`, sisa 0 selama eksekusi
- [x] Shutdown dan restart tanpa `/f` di `internal/oswin`
- [x] Pemilihan jalur sleep lewat `GetPwrCapabilities` (efek sleep nyata belum terbukti, lihat `waiting.md` M4)
- [x] `POST /power/sleep`, `/power/restart`, `/power/shutdown` + test
  - [x] Sinkronkan `postman/`
- [x] `POST /power/cancel`, termasuk `power_executing` + test
  - [x] Sinkronkan `postman/`

## M5 Pengaturan & Tema

- [ ] Perintah `reset-token` + test
- [x] Pastikan token lama langsung ditolak oleh agent yang berjalan + test BR-10

## M6 Ketahanan & Startup

- [x] `internal/startup`: `install-startup`, `uninstall-startup` lewat XML task
- [x] `run --background` dengan `FreeConsole`
- [x] Satu instance lewat named mutex
- [x] Middleware rate limit + header `Retry-After` + test
- [x] Graceful shutdown + test
- [x] Rotasi log 5 MiB, 3 file + test
- [x] Pesan jelas saat port sudah dipakai

## M7 Auto-Discovery Jaringan

- [ ] B1: Config `agentId` (32 hex `crypto/rand`, atomik, `reset-token` tak mengubah) dan `discovery.enabled` (default true)
- [ ] B2: `GET /status` memuat `agentId` + test
  - [ ] Sinkronkan `postman/`
- [ ] B3: Payload QR dengan field opsional `id`, ukuran < 256 byte, QR lama tetap valid
- [ ] B4: Paket `internal/discovery` (zeroconf, interface `Registrar`, filter interface D10, `Run(ctx)`, poll alamat 10 dtk, daftar ulang)
- [ ] B5: `cmd/agent/app.go` menjalankan discovery; `pair` menampilkan agentId
- [ ] B6: Test: TXT tak berisi token, semua rute tetap tolak tanpa token, daftar ulang saat alamat berubah, `enabled=false` tak mendaftar
- [ ] B7: `postman/` contoh respons Status + agentId
- [ ] B8: `docs/release.md` aturan firewall UDP 5353 profil Private
- [ ] B9: Decision-log pilihan library final (zeroconf atau fallback libp2p)
