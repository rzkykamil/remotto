# Development Workflow

Pengembangan dikerjakan per modul, berurutan M0 → M6. Urutan dinyatakan lewat fase dan Definition of Done, tanpa estimasi waktu.

## Siklus per modul

```text
frontend (app Flutter + mock) → catat backlog FE → backend (agent Go + sinkron postman/)
→ catat backlog BE → integrasi (app pakai agent asli) → catat backlog integrasi
→ QA (otomatis + skenario manual) → catat backlog QA → fixing bugs → update docs & todo
```

Fase aktif berisi satu nilai: `Belum mulai` → `Frontend` → `Backend` → `Integrasi` → `QA` → `Fixing` → `Selesai`. Hanya satu modul aktif pada satu waktu, kecuali M0.

## Fase tidak relevan

Modul tanpa tampilan (mis. bagian agent di M6) atau tanpa sisi agent melewati fase tersebut. Dokumenter mencatat "tidak relevan: <alasan>" di `docs/todo/modules/<Mn>-<slug>.md`, lalu memindahkan Fase aktif ke fase berikutnya. Tidak ada fase yang dilewati diam-diam.

## Definition of Done

### Frontend

- Semua screen dan widget modul ada dan bisa dipakai dengan mock. Bentuk respons persis `docs/api-spec.md`, termasuk error.
- Sesuai `docs/design-system.md` dan `docs/flows/user-flow.md` di terang dan gelap.
- State menyambung, offline, gagal, dan berhasil sesuai desain.
- Semantics terpasang.
- `flutter analyze` bersih dan widget test lolos.
- `pubspec.yaml` bebas UI kit (§11).
- Lolos checklist anti-pattern.
- Perbandingan visual di HP fisik masuk `waiting.md`.

### Backend

- Semua endpoint modul di `docs/api-spec.md` terimplementasi.
- Domain dites dengan fake OS.
- Handler dites (`httptest`) untuk auth, validasi, dan kode error.
- `go vet` dan `gofmt` bersih.
- `postman/` sinkron.
- Efek nyata ke OS (lagu benar-benar pause, volume benar-benar berubah, laptop benar-benar sleep/restart/shutdown) masuk `waiting.md`.

### Integrasi

- Semua baris modul di `docs/todo/integration.md` berstatus `Selesai`.
- Tidak ada mock tersisa untuk modul ini.
- Error 401, 403, 409, 429, 500, dan timeout ditangani sesuai desain.
- Tes dengan agent asli di laptop dari HP sungguhan masuk `waiting.md` bila tidak bisa dibuktikan otomatis.

### QA

- Semua skenario modul di `docs/todo/qa.md` dicek: happy path, edge case `BR-n`, keamanan token.
- Bug closed, atau dicatat di `blockers.md`/`waiting.md` dengan alasan.

### CI

DoD tidak memuat CI. CI hanya diperiksa di push akhir modul dan saat `/merge-to-main`.

## Aturan efek OS

Tim pengembangan tidak boleh menjalankan sleep, restart, shutdown, media key sungguhan, atau mengubah volume laptop untuk membuktikan fitur. Bukti di tim berupa test dengan fake OS. Pembuktian nyata dilakukan pemilik lewat `waiting.md`, dan tidak menahan `Selesai`.

## Disiplin fokus

- Fase frontend tidak menyicil agent, dan sebaliknya.
- QA tidak menambah fitur.
- Temuan di luar fokus masuk `docs/todo/backlog/`.
- Modul berikutnya dimulai setelah checklist penutup modul sebelumnya lunas.

## Checklist penutup siklus modul

- [ ] DoD fase relevan terpenuhi
- [ ] Bugs beres
- [ ] `docs/` yang relevan ter-update
- [ ] `docs/decision-log.md` terisi bila perlu
- [ ] File todo, backlog, `status.md`, `modules/<Mn>-<slug>.md`, `waiting.md`, `blockers.md` ter-update
- [ ] `postman/` sinkron

## Penutup project

1. Semua modul `Selesai`.
2. `/agent-team backlog`.
3. Pemilik memeriksa `docs/todo/waiting.md`, lalu `/agent-team waiting-selesai`.
4. `/merge-to-main`.
