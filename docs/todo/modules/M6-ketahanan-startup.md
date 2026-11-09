# M6 Ketahanan & Startup

## Frontend

- Selesai dengan Reviewer LOLOS DENGAN SARAN. Gerbang: `flutter test` lulus, `flutter analyze` bersih.
- Dibangun: `WidgetsBindingObserver` di `RemoteScreen` untuk pause dan resume polling, `ConnectionController.pause()` dan `resume()`, timeout tunggal `RMotion.commandTimeout`, retry `VolumeSender` hanya untuk kegagalan transien, dan monitor raster di `raster_monitor.dart`.
- Dicentang di `docs/todo/frontend.md` berdasarkan test lifecycle, test resume, dan test raster. Empat item pembuktian di HP ada di `docs/todo/waiting.md` bagian M6.
- Keputusan di `docs/decision-log.md` dengan tag `[Frontend M6]`. Saran di `docs/todo/backlog/integration.md` bagian M6.
- Branch `team/m6-ketahanan-startup` dibuat dari `team/m5-pengaturan-tema`, bukan dari `main`.

## Backend

- Selesai dengan Reviewer LOLOS DENGAN SARAN. Gerbang: `go test`, `go vet`, dan `gofmt` hijau.
- Dibangun: `internal/startup` (task XML), `run --background` dengan FreeConsole, named mutex `Local\RemottoAgent`, rate limit token bucket di `internal/server/ratelimit.go`, graceful shutdown, rotasi log 5 MiB dengan 3 file, dan pesan port bentrok per OS.
- Perbaikan reviewer: kegagalan rotasi tidak mematikan log. File dibuka ulang dan tulisan dicoba lagi.
- Dicentang di `docs/todo/backend.md` bagian M6. Keputusan `[Backend M6]` di `docs/decision-log.md`. Saran di `docs/todo/backlog/backend.md` bagian M6.
- Delapan item pembuktian di `docs/todo/waiting.md` bagian M6 (Backend), belum dicentang karena butuh laptop dan HP.

## Integrasi

- Selesai dengan Reviewer LOLOS DENGAN SARAN. Gerbang: `go test` dan `flutter test` hijau.
- Resume app dan Semua repository selesai di `docs/todo/integration.md`. Q12 setelah reset-token (baris M5) selesai, dibuktikan di sisi agent dan app.
- Tes baru: `app/test/integration/connection_resume_http_test.dart` dan 429 di media, volume, power, poll status (`agent/cmd/agent/run_e2e_test.go`).
- Keputusan `[Integrasi M6]` di `docs/decision-log.md`. Saran di `docs/todo/backlog/integration.md` bagian M6.
- Item pembuktian di HP ditambah di `docs/todo/waiting.md` bagian M6 (Integrasi).

## QA

- Semua enam `[O]` di `docs/todo/qa.md` tercakup tes, dengan bukti per item di file itu.
- Tidak ada bug baru. `docs/todo/backlog/qa.md` M6 tetap "Belum ada temuan".
- Item `[M]` (auto-start, kedip konsol, APK dari CI) ada di `docs/todo/waiting.md`.
- Fase M6 Selesai setelah push akhir.
