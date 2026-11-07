# Backlog Backend

Satu baris per temuan, dengan referensi inline. Heading modul tidak boleh dihapus.

## M0 Fondasi Proyek

- `go test -race` belum bisa dijalankan lokal karena CGO mati dan gcc tidak ada. Jalankan di CI atau mesin ber-gcc (`agent/internal/oscontrol/fake`, `agent/internal/server`).
- [Ditutup M1] Ganti nama `TestLoggingNeverRecordsSecrets` (`agent/internal/server/middleware_test.go`) dan `TestNewRedactsSensitiveAttributes` (`agent/internal/logging/logging_test.go`) agar menyebut `BR-11`: `TestBR11_*`.
- [Ditutup M1] `agent/config.example.json` kini `"token": ""` dengan `_note`; first run mengisi token (`agent/internal/config/lifecycle.go`).
- `Logging` mencatat `http.ErrAbortHandler` sebagai 500/`internal`, padahal abort itu disengaja. Kecualikan satu baris (`agent/internal/server/middleware.go`).
- Subcommand `pair`, `reset-token`, `install-startup`, dan `uninstall-startup` masih stub yang mengembalikan "belum tersedia" (`agent/cmd/agent/app.go`). Dikerjakan M1 (`pair`), M5 (`reset-token`), dan M6 (startup).

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

- `oswin.Audio.Close()` belum dipanggil saat shutdown, menunggu graceful shutdown M6 (`agent/cmd/agent/platform_windows.go`, `agent/internal/oswin/audio_windows.go`).
- Operasi COM tidak bisa dibatalkan. Bila device macet, pekerja tertahan dan request berikutnya timeout 1 dtk; timeout hanya membebaskan pemanggil (`agent/internal/oswin/audio_windows.go`).
- Notifikasi perubahan volume Windows (`IAudioEndpointVolumeCallback`) tidak dipakai; polling cukup untuk sekarang (`agent/internal/oswin/audio_windows.go`).
- Race baca-tulis dengan proses atau HP lain di luar mutex diterima (`agent/internal/control/volume.go`).
- `go test -race` untuk paket M3 belum bisa lokal (CGO mati). Dicek di CI (`agent/internal/control`, `agent/internal/oswin`, `agent/internal/server`).
- go-wca terakhir rilis 2023. Risiko dibatasi di balik `AudioController` (`agent/go.mod`).
- `CoInitializeEx` yang mengembalikan S_FALSE dianggap error oleh go-ole 1.3.0. Tidak realistis di thread baru yang dibuat pekerja (`agent/internal/oswin/audio_windows.go`).

## M4 Daya

Belum ada temuan.

## M5 Pengaturan & Tema

Belum ada temuan.

## M6 Ketahanan & Startup

Belum ada temuan.

## Stretch

Hanya dikerjakan kalau pemilik menyebutnya.

- [ ] Now playing lewat API sesi media Windows; juga bisa mengatasi media key saat layar terkunci (R-16)
- [ ] Wake-on-LAN
- [ ] WebSocket `GET /ws` untuk push status
- [ ] TLS di LAN (R-6)
