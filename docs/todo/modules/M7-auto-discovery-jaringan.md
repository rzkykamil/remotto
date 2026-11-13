# M7 Auto-Discovery Jaringan

## Frontend

- Selesai dengan Reviewer LOLOS DENGAN SARAN, tanpa temuan WAJIB. 8 task (T1 sampai T8) dicentang di `docs/todo/frontend.md` M7.
- Dibangun: `agentId` di app (storage opsional, `AgentStatus`, validator QR `id`), abstraksi discovery dengan implementasi `nsd`, `NetworkChangeSource` untuk `connectivity_plus`, `EndpointResolver`, dan integrasi ke `ConnectionController`. Tanpa layar, widget, atau teks baru.
- Gerbang lolos: `dart format` dan `flutter analyze` bersih, `flutter test` 1139 test hijau, `flutter build apk --debug` sukses. Pubspec bebas UI kit.
- Keputusan `[Frontend M7]` di `docs/decision-log.md`. Saran reviewer di `docs/todo/backlog/integration.md` bagian M7.
- Pembuktian di HP, di iOS, dan dengan agent asli ada di `docs/todo/waiting.md` bagian M7. Sebagian besar baru bisa dites setelah fase Backend selesai.

## Backend

- Selesai dengan Reviewer LOLOS DENGAN SARAN, tanpa temuan WAJIB. Gerbang: `gofmt`, `go vet` (termasuk tag `manual`), `go test ./...`, build Linux dan Windows, `go mod tidy` dan `go mod verify` hijau. `go test -race` belum bisa lokal (CGO mati), dicek lewat baca kode dan perlu CI.
- Dibangun: `agentId` di config (`EnsureAgentID` untuk config lama), `discovery.enabled`, `agentId` di `GET /status`, `id` opsional di QR, paket `internal/discovery` dengan `grandcat/zeroconf` v1.0.0, dan wiring di `run` dan `pair`.
- Dicentang di `docs/todo/backend.md` bagian M7 (B1 sampai B9). Keputusan `[Backend M7]` di `docs/decision-log.md`. Saran di `docs/todo/backlog/backend.md` bagian M7.
- Pembuktian mDNS nyata, adapter berganti, dan firewall UDP 5353 ada di `docs/todo/waiting.md` bagian M7 (Backend).

## Integrasi

- Selesai dengan Reviewer LOLOS DENGAN SARAN, tanpa temuan WAJIB. I1 sampai I6 di `docs/todo/integration.md` M7 berstatus Selesai.
- Tes: `discovery_http_flow_test.dart` (I2, I3, I6; klien rewrite loopback), `discovery_providers_test.dart` (I1, audit provider), `run_e2e_test.go` `TestRunStatusAgentIDMatchesPairOutputAndSurvivesTokenChange` (I4), dan `agent/internal/discovery/manual_test.go` bertag `manual` (I5).
- Gerbang lolos: `flutter test` 1162 hijau, analyze, format, `flutter build apk --debug`; agent gofmt, vet (termasuk tag `manual`), dan `go test ./...` hijau.
- Keputusan `[Integrasi M7]` di `docs/decision-log.md`. Saran di `docs/todo/backlog/integration.md` bagian M7.
- Pembuktian mDNS nyata, WiFi, iOS, dan HP ada di `docs/todo/waiting.md` bagian M7. Fase aktif pindah ke QA karena DoD Integrasi terpenuhi.

## QA

- Selesai dengan Reviewer LOLOS DENGAN SARAN, tanpa temuan WAJIB. Gerbang: `flutter analyze` dan `dart format` bersih, `flutter test` 1180 lulus dengan 1 merah, agent `gofmt`, `go vet`, dan `go test ./...` hijau.
- Dicentang dan dibuktikan: BR-22, LAN only, dua laptop tak tertukar, dan 12 edge case `[O]` (lihat `docs/todo/qa.md` M7).
- Bug open: `find` yang tak pernah selesai memblokir rediscover (test `a find that never completes must not block rediscover forever`, sengaja merah). Dicatat di `docs/todo/qa.md` §Bugs Ditemukan. Fase aktif pindah ke Fixing.
- Pembuktian manual WiFi cepat, data seluler, dan VPN/Tailscale ada di `docs/todo/waiting.md` bagian M7 (QA). SARAN yang tak dikerjakan ada di `docs/todo/backlog/qa.md` bagian M7.

## Fixing

- Selesai dengan Reviewer LOLOS DENGAN SARAN, tanpa temuan WAJIB. Bug `find` yang menggantung (`docs/todo/qa.md` §Bugs Ditemukan) berstatus fixed.
- Perbaikan: `RBehavior.discoveryGuardMargin` (1 dtk) dan `discoveryHardLimit` (4 dtk). `EndpointResolver._execute` memakai `.find(timeout).timeout(hardLimit)`, `NsdAgentDiscovery` membatasi start dan stop. `decodeTxt` dipisah jadi fungsi murni. Keputusan `[Fixing M7]` di `docs/decision-log.md`.
- Bukti: test (e) hijau, 3 test baru, 7 test `decodeTxt`. Reviewer membuktikan ketiga test baru gagal saat `.timeout` dihapus, lalu mutasi dikembalikan.
- Gerbang: `flutter analyze` dan `dart format` bersih, `flutter test` 1191 lulus. Agent `gofmt`, `go vet`, dan `go test ./...` hijau.
- Pembuktian di HP: `docs/todo/waiting.md` bagian M7 (Fixing). SARAN margin 1 dtk ada di `docs/todo/backlog/qa.md` M7.

## Penutup

- Checklist penutup siklus modul dicek dan lunas. Fase aktif: Selesai.
- Sisa yang menunggu pemilik ada di `docs/todo/waiting.md` bagian M7. Pembuktian itu tidak menahan Selesai.
- Tidak ada fase yang tidak relevan. Semua fase M7 (Frontend, Backend, Integrasi, QA, Fixing) dijalankan.

## CI (setelah push akhir)

- Run CI `43381256379` merah di `agent-test` (langkah govulncheck) dan `app-test` (langkah analyze, info `deprecated_member_use`). Job `build` skipped. Dugaan penyebab drift toolchain, belum diverifikasi sebagai bukan akibat M7.
- Detail dan langkah perbaikan di `docs/todo/blockers.md`. Status fase tetap Selesai.
