# QA

Tanda: **[O]** otomatis, **[M]** manual oleh pemilik lewat `waiting.md`.

## M0 Fondasi Proyek

- [ ] [O] `flutter analyze`, `dart format`, `go vet`, `gofmt` bersih
- [x] [O] Generator menghasilkan semua token terang dan gelap
- [x] [O] App tanpa data pairing masuk ke Q01; dengan data ke Remote
- [x] [O] `pubspec.yaml` bebas UI kit
- [ ] [M] Tampilan dasar dan kinerja blur di HP

## M1 Pairing & Koneksi

- [x] [O] Token 64 hex dibuat saat first run
- [x] [O] BR-1: semua route menolak tanpa token
- [x] [O] BR-2: token salah format dan salah nilai → 401
- [x] [O] BR-11: token tidak ada di log dan respons
- [x] [O] BR-12: IP sumber publik → 403; app menolak host publik
- [x] [O] QR tidak valid: bukan JSON, `v` salah, token salah format, host publik
- [x] [O] Config rusak → config baru + cadangan; config lebih baru → agent menolak start
- [x] [O] BR-8: satu gagal tetap online, dua gagal offline
- [x] [O] BR-9: 401 → Q12, data lama dipertahankan
- [x] [O] Polling tidak menumpuk
- [ ] [M] Scan QR, firewall, offline → online

## M2 Kontrol Media

- [x] [O] Happy path tiga endpoint dengan fake OS
- [x] [O] `media_failed` → ikon kembali + toast
- [x] [O] Tap ulang selama proses diabaikan
- [x] [O] BR-7: kontrol nonaktif saat offline
- [x] [O] Tanpa retry otomatis
- [ ] [M] Brave, Spotify, layar terkunci

## M3 Volume

- [x] [O] BR-3: −1, 101, pecahan, teks → 400
- [x] [O] BR-15: level berubah mematikan mute
- [x] [O] BR-16: langkah 5, berhenti di 0 dan 100
- [x] [O] BR-14: throttle 100 ms, nilai akhir selalu terkirim
- [x] [O] Mute eksplisit idempoten
- [x] [O] Gagal → rollback; offline saat drag → gesture batal
- [x] [O] `volume: null` di status tidak dianggap offline
- [x] [O] Rate limit tidak terpicu laju slider
- [ ] [M] Volume nyata, headset, perubahan dari laptop

## M4 Daya

- [x] [O] BR-4: eksekusi setelah jeda, tidak sebelumnya. Bukti: `TestBR4_ExecutesOnlyAfterPowerDelay` (`agent/internal/control/power_test.go`), `TestBR4_ExecutesOnceAfterDelay` (`agent/internal/server/power_test.go`)
- [x] [O] BR-5: jadwal kedua → 409, jadwal lama utuh. Bukti: `TestBR5_SecondScheduleRejected` (`agent/internal/server/power_test.go`), `TestBR5_SecondScheduleRejected` dan `TestBR5_ScheduleRejectedWhileExecuting` (`agent/internal/control/power_test.go`)
- [x] [O] BR-17: batal tanpa jadwal → 409. Bukti: `TestBR17_CancelWithoutScheduleIsConflict` (`agent/internal/server/power_test.go`), `TestBR17_CancelWithoutScheduleFails` (`agent/internal/control/power_test.go`)
- [x] [O] Batal saat eksekusi → 409 `power_executing`. Bukti: `TestBR17_CancelWhileExecutingIsConflict` (`agent/internal/server/power_test.go`), `TestCancelWhileExecutingFails` (`agent/internal/control/power_test.go`)
- [x] [O] BR-6: satu ketukan tidak pernah cukup; lepas cepat mereset. Bukti: `plain tap does nothing and fires no haptic`, `releasing at 600 ms does not complete and rewinds to 0` (`app/test/ui/hold_to_confirm_test.dart`); `Lanjut replaces itself with the hold control` (`app/test/features/remote/widgets/confirm_sheet_test.dart`)
- [x] [O] BR-19: P14 tanpa tombol Batal. Bukti: `shows only "Oke" with no cancel action (BR-19)` (`app/test/features/remote/power/result_screen_test.dart`), `FR-4.10: pending sisa 800 / 0 ms langsung P14 tanpa tombol Batal` (`app/test/features/remote/power_resume_test.dart`)
- [x] [O] BR-20: sisa dari `remainingMs`. Bukti: `/status with pending is parsed by the HTTP repository and resumes counting` (`app/test/integration/power_http_flow_test.dart`), `timeout, then /status shows pending: counts from the remaining time` (`app/test/features/remote/power/power_flow_controller_test.dart`)
- [x] [O] Timeout ambigu tidak menampilkan P10. Bukti: `timeout, then /status fails: P11 from the full delay` (`app/test/features/remote/power/power_flow_controller_test.dart`), `timeout, schedule stored on the laptop: counts from the remaining time` (`app/test/integration/power_http_flow_test.dart`)
- [x] [O] Gagal eksekusi membersihkan `pending`. Bukti: `TestPowerExecuteFailureClearsScheduleAndLogs` (`agent/internal/server/power_test.go`), `TestExecuteFailureReturnsToIdle` (`agent/internal/control/power_test.go`)
- [ ] [O] Race batal dan eksekusi aman (`go test -race`). Test ada (`TestPowerCancelAndFireRaceSingleOutcome`, `agent/internal/control/power_test.go`), tetapi belum ada bukti dijalankan dengan `-race`: CI hanya `go test ./...` dan gcc/CGO belum tersedia lokal. Lihat `docs/todo/backlog/qa.md` M4.
- [ ] [M] Sleep, shutdown, restart, batal, tutup app saat hitung mundur. Perlu dicek manual oleh user, lihat `docs/todo/waiting.md`.

## M5 Pengaturan & Tema

- [ ] [O] Tema dan haptic tersimpan
- [ ] [O] Haptic mati menonaktifkan semua haptic
- [ ] [O] Pairing ulang menghapus data sambungan dan `lastPowerCommand`, tema tetap
- [ ] [O] BR-10: token lama ditolak agent yang berjalan
- [ ] [O] BR-18: pairing baru mengganti yang lama
- [ ] [M] Tampilan di HP, TalkBack, teks 130%

## M6 Ketahanan & Startup

- [x] [O] Rate limit → 429 + `Retry-After`. Bukti: `TestRateLimitBurstThenTooManyRequests`, `TestRateLimitRetryAfterRounding`, `TestRateLimitBodyIsRateLimitedEnvelope` (`agent/internal/server/ratelimit_test.go`); `TestRateLimitBeforeAuth` (`agent/internal/server/server_test.go`); `TestServeAgentRateLimitWithFakeOS`, `TestServeAgentRateLimitEnvelopeAllRoutes` (`agent/cmd/agent/run_e2e_test.go`); grup `429 dan timeout pada poll` (`app/test/integration/connection_resume_http_test.dart`)
- [x] [O] Panic handler tidak menjatuhkan proses. Bukti: `TestRecoverPanicReturnsInternalEnvelope` (`agent/internal/server/middleware_test.go`), `TestPanicInOneHandlerDoesNotStopServer` (`agent/internal/server/server_test.go`)
- [x] [O] Graceful shutdown membuang jadwal. Bukti: `TestCloseDiscardsSchedule` (`agent/internal/control/power_test.go`); `TestServeAgentStopDiscardsPendingPower` (`agent/cmd/agent/run_e2e_test.go`); `TestServeStopsGracefully`, `TestServeFinishesInFlightRequest` (`agent/internal/server/server_test.go`)
- [x] [O] Rotasi log. Bukti: `TestFR64_RotatesIntoBackupsAndDropsOldest`, `TestFR64_RotateFailureKeepsLogging` (`agent/internal/logging/rotate_test.go`)
- [x] [O] Polling berhenti di background, jalan saat resume. Bukti: `app/test/features/remote/remote_lifecycle_test.dart`; grup `pause dan resume (FR-6.6, BR-21)` (`app/test/core/connection/connection_controller_test.dart`)
- [x] [O] BR-21: kontrol tidak bisa ditekan selama S02. Bukti: `dock nonaktif saat menyambung (S02)` (`app/test/features/remote/remote_screen_test.dart`); `connecting shows the waiting hint and disables controls` (`app/test/features/remote/widgets/volume_panel_test.dart`); `still connecting` (`app/test/features/remote/power_flow_test.dart`)
- [ ] [M] Auto-start, kedip konsol, APK dari CI

## Bugs Ditemukan

| Bug | Status | Referensi |
|---|---|---|
| `Pending.fromData` menerima action tak dikenal (M4 Integrasi): ditemukan test kontrak | fixed | `app/test/core/network/power_contract_test.dart`; keputusan `[Integrasi M4] Pending.fromData memvalidasi action` di `docs/decision-log.md` |
