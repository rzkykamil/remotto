# Backlog Backend

Satu baris per temuan, dengan referensi inline. Heading modul tidak boleh dihapus.

## M0 Fondasi Proyek

- `go test -race` belum bisa dijalankan lokal karena CGO mati dan gcc tidak ada. Jalankan di CI atau mesin ber-gcc (`agent/internal/oscontrol/fake`, `agent/internal/server`).
- [Ditutup M1] Ganti nama `TestLoggingNeverRecordsSecrets` (`agent/internal/server/middleware_test.go`) dan `TestNewRedactsSensitiveAttributes` (`agent/internal/logging/logging_test.go`) agar menyebut `BR-11`: `TestBR11_*`.
- [Ditutup M1] `agent/config.example.json` kini `"token": ""` dengan `_note`; first run mengisi token (`agent/internal/config/lifecycle.go`).
- `Logging` mencatat `http.ErrAbortHandler` sebagai 500/`internal`, padahal abort itu disengaja. Kecualikan satu baris (`agent/internal/server/middleware.go`).
- [Ditutup M6 untuk startup] Subcommand `pair`, `reset-token`, `install-startup`, dan `uninstall-startup` masih stub yang mengembalikan "belum tersedia" (`agent/cmd/agent/app.go`). Dikerjakan M1 (`pair`), M5 (`reset-token`), dan M6 (startup).

## M1 Pairing & Koneksi

- `BuildPayload` membatasi total 256 byte, padahal nama dengan emoji atau escape HTML bisa membengkak; tinjau batasnya (`agent/internal/pairing/payload.go`).
- `listAdapters` read-only ada di paket `pairing`, pengecualian aturan `os-integration`; pindah ke `internal/control` atau catat sebagai pengecualian di M5/M6 (`agent/internal/pairing/host_windows.go`).
- Komentar `server.go` sudah basi, dan `NewHandler` lama belum dihapus atau dimigrasikan ke `NewAPIHandler` (`agent/internal/server/server.go`).
- `NetworkFilter` mencatat warn per penolakan; turunkan ke Debug atau batasi per IP sampai rate limit M6 (`agent/internal/server/netfilter.go`).
- Pengisian token kosong saat first run belum punya event sendiri, hanya tercatat sebagai `FirstRun` (`agent/internal/config/lifecycle.go`).
- Pembuktian `pair` dengan adapter nyata: lihat `docs/todo/waiting.md` (M1 Backend).

## M2 Kontrol Media

- `SendInput` di `oswin/media_windows.go` belum memakai `runtime.KeepAlive(inputs)` setelah `proc.Call`; tambahkan agar pointer tidak dikumpulkan sebelum panggilan selesai.
- `MediaService.Do` (`agent/internal/control/media.go`) mengambil mutex tanpa cek `ctx`. Dampak nol untuk sekarang.
- SendInput yang diblokir UIPI memberi n=0 dengan Errno 0, sehingga log berbunyi "operation completed successfully" dan menyesatkan. Respons 500 `media_failed` sudah benar (`agent/internal/oswin/media_windows.go`).
- `go test -race` untuk paket M2 belum bisa lokal (CGO mati). Dicek di CI (`agent/internal/control`, `agent/internal/oswin`, `agent/internal/server`).

## M3 Volume

- [Ditutup M6] `oswin.Audio.Close()` belum dipanggil saat shutdown, menunggu graceful shutdown M6 (`agent/cmd/agent/platform_windows.go`, `agent/internal/oswin/audio_windows.go`).
- Operasi COM tidak bisa dibatalkan. Bila device macet, pekerja tertahan dan request berikutnya timeout 1 dtk; timeout hanya membebaskan pemanggil (`agent/internal/oswin/audio_windows.go`).
- Notifikasi perubahan volume Windows (`IAudioEndpointVolumeCallback`) tidak dipakai; polling cukup untuk sekarang (`agent/internal/oswin/audio_windows.go`).
- Race baca-tulis dengan proses atau HP lain di luar mutex diterima (`agent/internal/control/volume.go`).
- `go test -race` untuk paket M3 belum bisa lokal (CGO mati). Dicek di CI (`agent/internal/control`, `agent/internal/oswin`, `agent/internal/server`).
- go-wca terakhir rilis 2023. Risiko dibatasi di balik `AudioController` (`agent/go.mod`).
- `CoInitializeEx` yang mengembalikan S_FALSE dianggap error oleh go-ole 1.3.0. Tidak realistis di thread baru yang dibuat pekerja (`agent/internal/oswin/audio_windows.go`).
- Warning `status audio read failed` di `GET /status` tidak dibatasi rate limit, bisa berulang tiap poll. Dedupe bila berisik (`agent/internal/server/status.go`, lihat `[Fixing M3]`).
- `step()` membaca `Volume()` dua kali, satu panggilan COM tambahan per step. Tidak kritis (`agent/internal/control/volume.go`).
- Tambah satu test handler `POST /volume/mute` dengan `SetMuteErr`. Kontrak 500 sudah tercakup lewat `SetErr` (`agent/internal/server/volume_test.go`).

## M4 Daya

- `go test -race` untuk test Cancel vs fire belum bisa lokal (CGO mati). Jalankan di CI (`agent/internal/control`, `agent/internal/server`).
- Rate limit khusus endpoint daya belum didefinisikan spec; ditunda ke M6 (`agent/internal/server`).
- `Close()` tidak menunggu eksekusi yang sedang berjalan; graceful shutdown penuh di M6 (`agent/internal/control/power.go`).
- `TestServeAgentStopDiscardsPendingPower` hanya membuktikan tidak ada eksekusi di jendela singkat; pembuangan timer dibuktikan `TestCloseDiscardsSchedule` (`agent/cmd/agent`).
- Offset `AoAc` (20) dan ukuran struct 76 byte di `SYSTEM_POWER_CAPABILITIES` perlu dicocokkan dengan `winnt.h` SDK bila tersedia (`agent/internal/oswin/sleep_windows.go`).
- Deskripsi request Status di `postman/` belum menyebut bentuk `pending` (objek atau null); opsional (`postman/collections/Remotto Agent/`).

## M5 Pengaturan & Tema

- [ ] Perintah `reset-token` masih "belum tersedia" (`agent/cmd/agent/app.go` `plannedCommands`) padahal M5 Selesai. Perlu keputusan pemilik: tampilkan perintah atau catat sebagai ditunda. Ditemukan Integrasi M7.

## M6 Ketahanan & Startup

- `startup.go` `isAccessDenied` dan `isNotFound` mencocokkan teks Inggris; di Windows non-Inggris deteksi bisa meleset. Pertimbangkan `schtasks /Query` atau exit code (`agent/internal/startup/startup.go`).
- Panic di `Recover` mencatat stack ke log; pastikan tidak ada token di stack. Sudah diuji, catatan saja (`agent/internal/server`).
- `TestServeAgentStopDiscardsPendingPower` belum memakai fake clock karena `serveAgent` belum menerima clock (`agent/cmd/agent`).
- `PowerScheduler.Close()` tidak menunggu eksekusi yang sedang berjalan. Sama dengan backlog M4 (`agent/internal/control/power.go`).
- `go test -race` belum dijalankan lokal (CGO mati). Jalankan di CI (`agent/internal/server`, `agent/internal/startup`, `agent/cmd/agent`).
- `http.ErrAbortHandler` dicatat sebagai 500 di `Logging`; minor. Sama dengan backlog M0 (`agent/internal/server/middleware.go`).
- Rate limit khusus endpoint daya belum didefinisikan spec. Sama dengan backlog M4 (`agent/internal/server/ratelimit.go`).
- `NetworkFilter` mencatat warn per penolakan; pertimbangkan dedupe. Sama dengan backlog M1 (`agent/internal/server/netfilter.go`).
- `ConfigTokenSource` (`agent/internal/server/auth.go`) memuat ulang config hanya bila mtime atau ukuran berubah. Dua penulisan token berukuran sama dalam satu tick mtime Windows (sekitar 15 ms) bisa terlewat. Tes sudah diberi `bumpConfigMtime` di `run_e2e_test.go`. Pertimbangkan membandingkan isi (hash) saat reload; SARAN, tidak mendesak.

## M7 Auto-Discovery Jaringan

- `laptopName` buatan user bisa memuat teks (mis. token yang tertempel) ke TXT `name`; tolak `laptopName` yang cocok `[0-9a-f]{64}` di `config.Validate` atau abaikan `name` bila mirip token (`agent/internal/config/validate.go`, `agent/internal/discovery/txt.go`).
- Aturan firewall UDP 5353 di `docs/release.md` tanpa `-Program` membuka 5353 untuk semua program di profil Private, sama dengan aturan TCP yang ada; bisa diketatkan (`docs/release.md`).
- `Lister.List()` tidak membaca ctx, sehingga stop discovery bisa menunggu maks 2 dtk (catatan, `agent/internal/discovery`).
- Pantau `govulncheck` dan dependensi `grandcat/zeroconf` yang tidak dirawat, dengan `miekg/dns` v1.1.27. Fallback libp2p tetap tercatat di `[Backend M7] Library mDNS agent` (`agent/go.mod`).

## Stretch

Hanya dikerjakan kalau pemilik menyebutnya.

- [ ] Now playing lewat API sesi media Windows; juga bisa mengatasi media key saat layar terkunci (R-16)
- [ ] Wake-on-LAN
- [ ] WebSocket `GET /ws` untuk push status
- [ ] TLS di LAN (R-6)
