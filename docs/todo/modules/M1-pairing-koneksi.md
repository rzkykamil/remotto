# M1 Pairing & Koneksi

## Frontend

- Selesai dengan Reviewer LOLOS DENGAN SARAN. Saran wajib sudah diperbaiki. 15 item `docs/todo/frontend.md` M1 dicentang.
- Dibangun: validator QR dan input manual, mock pairing dan status, `ConnectionController`, primitif (RIcon, PairingScaffold, GlassToast, GlassTextField, StepProgressList, StatusPill, QrViewfinder), layar Q01 sampai Q12, dan SCR-010 dengan state S01 sampai S11.
- Gerbang akhir lolos: format bersih, analyze bersih, 382 test lulus. Tanpa HTTP sungguhan; data masih mock.
- Keputusan ada di `docs/decision-log.md` dengan tag `[Frontend M1]`.
- Saran dan temuan lanjutan: `docs/todo/backlog/frontend.md`. Pembuktian di HP dan perbandingan visual: `docs/todo/waiting.md`.
- Fase aktif pindah ke Backend karena DoD Frontend terpenuhi. Endpoint `/status` dan auth belum ada.

## Backend

- Selesai dengan Reviewer LOLOS DENGAN SARAN, tanpa temuan WAJIB. 11 task (T1 sampai T11) dicentang di `docs/todo/backend.md` M1.
- Dibangun: token 256 bit, config lifecycle (first run, file rusak, migrasi, `ErrNewerVersion`), DACL Windows dan chmod non-Windows, `NetworkFilter`, auth constant-time dengan reload token, `GET /api/v1/status`, pemilihan host LAN, `pair` dengan QR, dan `run` yang terangkai dengan config.
- Gerbang lolos: gofmt, vet, dan test agent hijau; vet Linux dan Windows bersih; test DACL nyata (`-tags manual`) hijau.
- Keputusan ada di `docs/decision-log.md` dengan tag `[Backend M1]`. Saran di `docs/todo/backlog/backend.md`.
- Pembuktian di laptop dan HP (DACL nyata, reset token, `pair`, dan QR) ada di `docs/todo/waiting.md`.
- Fase aktif pindah ke Integrasi karena DoD Backend terpenuhi.

## Integrasi

- Selesai dengan Reviewer LOLOS DENGAN SARAN, tanpa temuan WAJIB. 3 baris `docs/todo/integration.md` M1 berstatus Selesai.
- Dibangun: `AgentHttpClient` (satu klien untuk pairing dan polling), `HttpStatusRepository`, dan `HttpPairingRepository`. Mock dipindah ke `test/support/` sebagai fake. Tes: 33 unit (MockClient), 10 server loopback Dart, dan 4 `ConnectionController` ke loopback.
- Gerbang lolos: format dan analyze bersih, 429 test app lulus, dan `go test ./...` agent tetap hijau. Go dan `postman/` tidak berubah. Konfigurasi platform Android (cleartext) dan iOS (NSAllowsLocalNetworking) sudah ada dan tidak diubah.
- Tidak ada mismatch kontrak dengan `docs/api-spec.md`. 409 tidak berlaku di M1 karena hanya endpoint daya yang memakainya.
- Keputusan ada di `docs/decision-log.md` dengan tag `[Integrasi M1]`. Saran di `docs/todo/backlog/integration.md`. Pembuktian di HP dan laptop sungguhan di `docs/todo/waiting.md`.
- Fase aktif pindah ke QA karena DoD Integrasi terpenuhi.

## QA

- Selesai dengan Reviewer LOLOS tanpa temuan. 10 skenario [O] M1 dicentang di `docs/todo/qa.md` dan dibuktikan tes yang ada (Go 130 test, app 430 test lulus, analyze dan format bersih).
- Satu tes ditambah: BR-9 "401 setelah sukses" di `app/test/core/connection/connection_controller_test.dart`.
- Tidak ada bug. Bagian Bugs Ditemukan tidak berubah.
- Keputusan `[QA M1]` ada di `docs/decision-log.md`. Backlog: `go test -race` (butuh gcc) dan sisi log app BR-11 di `docs/todo/backlog/qa.md`.
- Skenario [M] M1 (scan QR, firewall, offline ke online) tetap di `docs/todo/waiting.md`, bersama item pembuktian M1 lainnya.

## Fixing

Tidak relevan: QA tidak menemukan bug, jadi tidak ada yang perlu diperbaiki. Alasan dicatat di `docs/decision-log.md` `[QA M1]`.
