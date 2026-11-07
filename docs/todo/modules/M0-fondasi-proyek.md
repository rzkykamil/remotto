# M0 Fondasi Proyek

## Frontend

- Selesai dengan Reviewer LOLOS DENGAN SARAN. 14 item `docs/todo/frontend.md` M0 dicentang.
- Dibangun: proyek Flutter Android + iOS portrait, package, generator token, Geist, ikon app gelap, ThemeData terang/gelap, primitif `Pressable`/`GlassPanel`/`GlassKey`, latar cahaya, router, storage, dan haptic.
- Keputusan ada di `docs/decision-log.md` dengan tag `[Frontend M0]`.
- Saran yang tidak dikerjakan dan temuan lanjutan: `docs/todo/backlog/frontend.md`.
- Pembuktian di HP dan build iOS/APK: `docs/todo/waiting.md`.

## Backend

- Selesai dengan Reviewer LOLOS DENGAN SARAN. 8 item `docs/todo/backend.md` M0 dicentang.
- Dibangun: modul Go 1.27.3 (`remotto/agent`, stdlib saja), subcommand `version`/`run`/help, logging JSON, config (path, default, validasi, tulis atomik), router dan middleware server, interface `control` dengan error domain, fake OS, dan stub non-Windows. Tanpa endpoint, jadi `postman/` tidak berubah.
- Keputusan ada di `docs/decision-log.md` dengan tag `[Backend M0]`.
- Saran yang tidak dikerjakan dan temuan lanjutan: `docs/todo/backlog/backend.md`.
- Pembuktian `run` di laptop, build Go 1.27, dan job CI: `docs/todo/waiting.md`.
