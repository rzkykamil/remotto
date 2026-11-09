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

## Integrasi

Tidak relevan: M0 tidak punya endpoint dan tidak ada mock repository di app; agent hanya kerangka server tanpa endpoint.

## QA

- Selesai dengan Reviewer LOLOS tanpa temuan. 4 skenario [O] M0 dicentang di `docs/todo/qa.md`.
- Ditambahkan `app/test/core/theme/tokens_completeness_test.dart` (5 test): seluruh 36 field warna per mode dibandingkan dengan `design/tokens.json`, kunci JSON sama dengan daftar field generator, dan struktur terang dan gelap identik.
- Gerbang penuh lolos: Flutter 126 test, analyze dan format bersih; Go 6 paket lolos, vet dan gofmt bersih.
- Keputusan ada di `docs/decision-log.md` dengan tag `[QA M0]`.
- Pembuktian di HP dan build tetap di `docs/todo/waiting.md`; bug tidak ditemukan.
