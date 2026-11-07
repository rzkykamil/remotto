# M2 Kontrol Media

## Frontend

- Selesai dengan Reviewer LOLOS DENGAN SARAN. 7 task `docs/todo/frontend.md` M2 dicentang. Gerbang lolos: analyze dan format bersih, 493 test lulus.
- Dibangun: `MediaRepository` dan mock dengan skrip, `MediaController` (optimistic, cincin 400 ms, tap ulang diabaikan, toast "Ulangi"), `PlayKey`, `MediaDock` dengan kedip prev/next, pemasangan di `RemoteScreen`, dan inset toast.
- Data masih tiruan. Tombol media selalu sukses sampai HTTP asli di Integrasi. Volume (M3) dan daya (M4) belum dikerjakan.
- Keputusan ada di `docs/decision-log.md` dengan tag `[Frontend M2]`. Saran dan item lanjutan: `docs/todo/backlog/frontend.md`.
- Pembuktian di HP dan perbandingan visual: `docs/todo/waiting.md`.
- Fase aktif pindah ke Backend karena DoD Frontend terpenuhi.

## Backend

- Selesai dengan Reviewer LOLOS DENGAN SARAN, tanpa temuan WAJIB. 4 task `docs/todo/backend.md` M2 dicentang.
- Dibangun: `MediaService` di `internal/control`, `SendInput` di `internal/oswin` (satu panggilan berisi tekan dan lepas), rute `POST /api/v1/media/play-pause|next|prev` lewat `WithMedia`, wiring di `cmd/agent`, dan `postman/` Media sinkron.
- Gerbang lolos: gofmt, vet, test semua paket, dan build. `-race` belum jalan lokal (CGO mati) dan dicek di CI. `SendInput` asli belum dijalankan; pembuktian ada di `docs/todo/waiting.md`.
- Keputusan ada di `docs/decision-log.md` dengan tag `[Backend M2]`. Saran di `docs/todo/backlog/backend.md`.
- Fase aktif pindah ke Integrasi karena DoD Backend terpenuhi.

## Integrasi

- Selesai dengan Reviewer LOLOS DENGAN SARAN, tanpa temuan WAJIB. 3 baris `docs/todo/integration.md` M2 berstatus Selesai (tes loopback).
- Dibangun: `AgentHttpClient.postMedia` ke `POST /api/v1/media/{action}`, `HttpMediaRepository`, `mediaRepositoryProvider` memakai HTTP, `MockMediaRepository` dipindah ke `test/support/` sebagai fake, dan `FakeAgentServer` menangani rute media. Tes: 12 kasus di `test/integration/media_http_flow_test.dart`.
- Gerbang lolos: format dan analyze bersih, 529 test lulus. `agent/` dan `postman/` tidak berubah.
- Keputusan ada di `docs/decision-log.md` dengan tag `[Integrasi M2]`. Saran di `docs/todo/backlog/integration.md`.
- Pembuktian dengan agent asli dan HP sungguhan ada di `docs/todo/waiting.md`.
- Fase aktif pindah ke QA karena DoD Integrasi terpenuhi.
