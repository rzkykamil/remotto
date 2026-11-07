# M1 Pairing & Koneksi

## Frontend

- Selesai dengan Reviewer LOLOS DENGAN SARAN. Saran wajib sudah diperbaiki. 15 item `docs/todo/frontend.md` M1 dicentang.
- Dibangun: validator QR dan input manual, mock pairing dan status, `ConnectionController`, primitif (RIcon, PairingScaffold, GlassToast, GlassTextField, StepProgressList, StatusPill, QrViewfinder), layar Q01 sampai Q12, dan SCR-010 dengan state S01 sampai S11.
- Gerbang akhir lolos: format bersih, analyze bersih, 382 test lulus. Tanpa HTTP sungguhan; data masih mock.
- Keputusan ada di `docs/decision-log.md` dengan tag `[Frontend M1]`.
- Saran dan temuan lanjutan: `docs/todo/backlog/frontend.md`. Pembuktian di HP dan perbandingan visual: `docs/todo/waiting.md`.
- Fase aktif pindah ke Backend karena DoD Frontend terpenuhi. Endpoint `/status` dan auth belum ada.
