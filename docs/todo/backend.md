# Backend (agent Go)

Setiap task endpoint menyertakan sub-task "sinkronkan `postman/`".

## M0 Fondasi Proyek

- [ ] `go mod init` di `agent/` dengan Go 1.27
- [ ] Kerangka subcommand di `cmd/agent` dan variabel `version`
- [ ] `internal/logging`: slog JSON ke file + konsol, rotasi menyusul di M6
- [ ] `internal/config`: path, default, baca, validasi, tulis atomik + test
- [ ] Kerangka `internal/server`: router, envelope respons, recover, logging + test
- [ ] Interface `MediaController`, `AudioController`, `PowerController` di `internal/control`
- [ ] Implementasi `internal/oscontrol/fake`
- [ ] Stub non-Windows di `cmd/agent`

## M1 Pairing & Koneksi

- [ ] Pembuatan token 256 bit saat first run + test
- [ ] DACL config dan folder (`_windows.go`) + pemeriksaan saat start
- [ ] Migrasi versi dan penanganan file rusak + test
- [ ] Middleware filter jaringan + test
- [ ] Middleware auth constant-time + test semua route
- [ ] Muat ulang token lewat waktu modifikasi config + test BR-10
- [ ] Pemilihan host LAN + opsi `--host` + test
- [ ] Perintah `pair` dengan QR dan teks
- [ ] `GET /status` + test
  - [ ] Sinkronkan `postman/`
- [ ] Penulisan log akses tanpa token + test BR-11

## M2 Kontrol Media

- [ ] Domain media + test
- [ ] `SendInput` di `internal/oswin`
- [ ] `POST /media/play-pause`, `/media/next`, `/media/prev` + test
  - [ ] Sinkronkan `postman/`

## M3 Volume

- [ ] Domain volume: batas 0–100, langkah 5, unmute saat level berubah + test BR-3, BR-15, BR-16
- [ ] Pekerja COM Core Audio di `internal/oswin`
- [ ] Field `volume` di `/status`, `null` saat audio gagal
- [ ] `GET /volume` dan `PUT /volume` + test
  - [ ] Sinkronkan `postman/`
- [ ] `POST /volume/up` dan `/volume/down` + test
  - [ ] Sinkronkan `postman/`
- [ ] `POST /volume/mute` + test
  - [ ] Sinkronkan `postman/`

## M4 Daya

- [ ] Scheduler dengan clock palsu: jeda, batal, jadwal kedua, eksekusi, gagal + test BR-4, BR-5, BR-17
- [ ] Field `pending` di `/status`, sisa 0 selama eksekusi
- [ ] Shutdown dan restart tanpa `/f` di `internal/oswin`
- [ ] Pemilihan jalur sleep lewat `GetPwrCapabilities`
- [ ] `POST /power/sleep`, `/power/restart`, `/power/shutdown` + test
  - [ ] Sinkronkan `postman/`
- [ ] `POST /power/cancel`, termasuk `power_executing` + test
  - [ ] Sinkronkan `postman/`

## M5 Pengaturan & Tema

- [ ] Perintah `reset-token` + test
- [ ] Pastikan token lama langsung ditolak oleh agent yang berjalan + test BR-10

## M6 Ketahanan & Startup

- [ ] `internal/startup`: `install-startup`, `uninstall-startup` lewat XML task
- [ ] `run --background` dengan `FreeConsole`
- [ ] Satu instance lewat named mutex
- [ ] Middleware rate limit + header `Retry-After` + test
- [ ] Graceful shutdown + test
- [ ] Rotasi log 5 MiB, 3 file + test
- [ ] Pesan jelas saat port sudah dipakai
