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

## M7 Auto-Discovery Jaringan

- [x] [O] BR-22: token tidak ada di iklan mDNS (TXT) dan tidak ada di log discovery. Bukti: `TestBR22_BuildTXTNeverCarriesTokenMaterial`, `TestBR22_RunAdvertisementHasNoToken`, `TestBR22_RunLogsHaveNoTokenMaterial` (`agent/internal/discovery/security_test.go`); `kode discovery tidak memakai print, log, atau stderr`, `nsd_agent_discovery.dart tidak menyentuh token` (`app/test/core/discovery/discovery_hygiene_test.dart`)
- [x] [O] LAN only: iklan dan kandidat hanya IPv4 privat (BR-12), IPv6 dan IP publik diabaikan. Bukti: `TestSelectInterfaces` (`agent/internal/discovery/ifaces_test.go`); `ignores IPv6 and rejects when no IPv4 is present`, `rejects public IPv4 addresses`, `rejects Tailscale 100.64/10 range` (`app/test/core/discovery/discovery_candidate_test.dart`); `BR-12: non-private candidates (loopback, public) are never contacted` (`app/test/integration/discovery_http_flow_test.dart`)
- [x] [O] Dua laptop tak tertukar: kandidat dengan `agentId` berbeda ditolak dan tidak disimpan. Bukti: `I3a` dan `I3b` (`app/test/integration/discovery_http_flow_test.dart`); `drops a candidate whose status answers with another agentId` (`app/test/core/discovery/endpoint_resolver_test.dart`)
- [x] [O] Edge: `agentId` malformed di TXT ditolak, dan di `/status` kandidat dilewati. Bukti: `rejects malformed id` (`app/test/core/discovery/discovery_candidate_test.dart`); `a matching candidate with a malformed agentId in its status is ...` (`app/test/core/discovery/endpoint_resolver_test.dart`)
- [x] [O] Edge: TXT dengan `v` tak dikenal atau tanpa `v` ditolak. Bukti: `rejects TXT v other than 1`, `rejects TXT without v` (`app/test/core/discovery/discovery_candidate_test.dart`)
- [x] [O] Edge: batas 3 kandidat diverifikasi. Bukti: `verifies at most three candidates` (`app/test/core/discovery/endpoint_resolver_test.dart`)
- [x] [O] Edge: pencarian memakai `discoveryTimeout`. Bukti: `uses discoveryTimeout for the search` (`app/test/core/discovery/endpoint_resolver_test.dart`). Timeout saat `find` menggantung: lihat §Bugs Ditemukan (fixed)
- [x] [O] Edge: interval discovery dihormati, rediscover paksa melewatinya. Bukti: `a non-forced run waits for discoveryInterval before running again`, `force bypasses discoveryInterval` (`app/test/core/discovery/endpoint_resolver_test.dart`)
- [x] [O] Edge: proses bersamaan berbagi satu run dan satu discovery. Bukti: `concurrent calls share one run and one discovery` (`app/test/core/discovery/endpoint_resolver_test.dart`)
- [x] [O] Edge: tiga event jaringan beruntun menjadi satu rediscover paksa; event baru mereset debounce. Bukti: `tiga event jaringan berturut lalu satu debounce: rediscover paksa tepat sekali`, `event baru saat debounce masih hidup mereset timer: belum ada rediscover` (`app/test/core/connection/connection_controller_test.dart`)
- [x] [O] Edge: jaringan non-WiFi/Ethernet tidak memicu rediscover. Bukti: `event jaringan bukan Wi-Fi/Ethernet: tidak ada rediscover dan tidak ada poll` (`app/test/core/connection/connection_controller_test.dart`); `false for mobile-only or none` (`app/test/core/discovery/discovery_candidate_test.dart`); `onLocalNetwork` (`app/test/core/discovery/network_change_source_test.dart`)
- [x] [O] Edge: pairing lama tanpa `agentId` tidak memulai discovery dan pairing tak berubah. Bukti: `a legacy pairing without agentId gives none and runs no discovery` (`app/test/core/discovery/endpoint_resolver_test.dart`); `I6 legacy: no agentId means no discovery, pairing unchanged` (`app/test/integration/discovery_http_flow_test.dart`)
- [x] [O] Edge: config lama mendapat `agentId` sekali dan stabil. Bukti: `TestRunOldConfigGetsAgentIDAndDiscoveryUsesIt` (`agent/cmd/agent/run_e2e_test.go`), `TestPairOldConfigGetsAgentIDOnceAndStays` (`agent/cmd/agent/pair_test.go`), `TestEnsureAgentIDSecondCallIsNoOp` (`agent/internal/config/agentid_test.go`)
- [x] [O] Edge: `discovery.enabled=false` tidak memanggil discovery. Bukti: `TestRunDisabledMakesNoCalls` (`agent/internal/discovery/run_test.go`); `TestRunDiscoveryDisabledIsPassedThrough` (`agent/cmd/agent/run_e2e_test.go`)
- [x] [O] Edge: reset token saat discovery berjalan tidak menyimpan endpoint. Bukti: `a 401 gives none when the token was replaced during the run` (`app/test/core/discovery/endpoint_resolver_test.dart`); `TestRunStatusAgentIDMatchesPairOutputAndSurvivesTokenChange` (`agent/cmd/agent/run_e2e_test.go`)
- [x] [O] Edge: find yang tak pernah selesai tidak memblokir rediscover selamanya. Bukti: `a find that never completes must not block rediscover forever` (`app/test/core/discovery/endpoint_resolver_test.dart`, grup `edge cases`); 3 test baru di grup yang sama: rediscover berikutnya berjalan normal setelah timeout, `force` tidak macet, timeout tidak menyimpan apa pun dan hasil telat diabaikan. Mutasi (hapus `.timeout`) membuat ketiganya gagal (Reviewer Fixing M7).
- [ ] [M] WiFi cepat 3 kali, HP hanya data seluler, dan HP dengan VPN/Tailscale saat WiFi laptop berganti. Lihat `docs/todo/waiting.md` bagian M7 (QA).

## Bugs Ditemukan

| Bug | Status | Referensi |
|---|---|---|
| `Pending.fromData` menerima action tak dikenal (M4 Integrasi): ditemukan test kontrak | fixed | `app/test/core/network/power_contract_test.dart`; keputusan `[Integrasi M4] Pending.fromData memvalidasi action` di `docs/decision-log.md` |
| M7 Edge resolver: test `a find that never completes must not block rediscover forever` di grup `edge cases` (`app/test/core/discovery/endpoint_resolver_test.dart`, T2 e) sengaja merah. `EndpointResolver._execute` memanggil `find` tanpa timeout dan `_inFlight` hanya dibersihkan lewat `whenComplete`, jadi `find` yang menggantung membuat semua rediscover (termasuk `force`) mengembalikan future macet yang sama. `NsdAgentDiscovery.find` menunggu `startDiscovery` tanpa timeout. Spec: resolver tak macet selamanya (discoveryTimeout). Arah perbaikan di fase Fixing: `.timeout` di sekitar `find` pada `_execute` (hasil `none`) dan/atau di sekitar `startDiscovery`. Tidak ditambal di QA. | fixed | Test (e) `a find that never completes must not block rediscover forever` (`app/test/core/discovery/endpoint_resolver_test.dart`, tidak diubah) kini hijau; 3 test baru di grup `edge cases` (`endpoint_resolver_test.dart`) dan 7 test `decodeTxt` (`app/test/core/discovery/discovery_candidate_test.dart`). Perbaikan: `EndpointResolver._execute` memakai `.find(timeout: discoveryTimeout).timeout(discoveryHardLimit)` (`app/lib/core/discovery/endpoint_resolver.dart`); `NsdAgentDiscovery.find` membatasi `startDiscovery` dan `stopDiscovery` (`app/lib/core/discovery/nsd_agent_discovery.dart`). Keputusan `[Fixing M7] Batas keras find di resolver` di `docs/decision-log.md` |
