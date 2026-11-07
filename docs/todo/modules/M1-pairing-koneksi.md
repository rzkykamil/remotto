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
