# Remotto — Design handoff

Remotto adalah app Flutter (Android + iOS) untuk mengontrol laptop Windows lewat WiFi yang sama: play/pause, volume, sleep, restart, shutdown. Folder ini berisi hasil desain yang sudah disetujui (gate D1–D2) untuk dipakai saat scaffold Flutter + agent Go.

## Urutan baca

1. `scope-and-flows.md` — tujuan, navigasi, flow utama + pemulihan, batas scope, keputusan terbuka.
2. `design-system.md` — prinsip, arah visual (Warm Liquid Glass), warna, tipografi, layout, motion, haptic, a11y.
3. `tokens.json` — sumber nilai token (warna, tipografi, spacing, radius, ukuran, durasi, easing).
4. `components.md` — 22 komponen kustom: anatomi, state, token, perilaku, Semantics, pemetaan Flutter.
5. `screens.md` — screen ID → modul → state → artefak → status.
6. `review.md` — pemeriksaan yang dilakukan, hasil, yang belum diverifikasi.

## Inventaris file

| File | Isi | Status |
| --- | --- | --- |
| `README.md` | Manifest ini | ada |
| `scope-and-flows.md` | Scope & flow | ada |
| `design-system.md` | Sistem desain | ada |
| `tokens.json` | Token (JSON valid, alias tervalidasi) | ada |
| `components.md` | Spesifikasi komponen | ada |
| `screens.md` | Matriks screen | ada |
| `review.md` | Hasil review | ada |
| `export/logo/remotto-app-icon-dark.svg` | Ikon app, varian gelap (1024) | lokal saja, tidak di-commit |
| `export/logo/remotto-app-icon-light.svg` | Ikon app, varian terang (1024) | lokal saja, tidak di-commit |
| `export/logo/remotto-app-icon-{dark,light}-{1024,512,192}.png` | Render PNG ikon app | lokal saja, tidak di-commit |
| `export/logo/remotto-mark.svg` | Logo mark tanpa latar (pakai `currentColor`) | lokal saja, tidak di-commit |
| `export/artboards/*.dc.html` | Sumber 21 artboard: susunan, nilai, copy persis, state | ada |
| `export/artboards/canvas.json` | Indeks artboard | ada |

Sumber logo yang ter-commit adalah SVG inline di `export/artboards/Logo.dc.html`.

## Pemetaan screen ID → artefak di canvas

| Screen ID | Artboard |
| --- | --- |
| SCR-001, SCR-002, SCR-003 (Q01–Q12) | "B3+B4 · Pairing & error · gelap/terang", "B3 · Prototype pairing" |
| SCR-010 (S01–S12) | "SCR-010 Remote · 412/360 · terang/gelap", "B1 · SCR-010 state · gelap/terang" |
| SCR-011, SCR-012, SCR-013 (P01–P12) | "B2 · Konfirmasi daya · gelap/terang", "B2 · Prototype daya" |
| SCR-013 (P13–P15) | "B2 revisi · Buka app saat hitung mundur (P13–P15)" |
| SCR-020, SCR-021 (R01–R06) | "B5 · Pengaturan · gelap/terang" |
| Komponen C01–C22 | "B1 · Komponen & perilaku", "B2 · Komponen & perilaku", "B3–B5 · Komponen, error & matriks D2" |
| Fondasi | "D1 · Arah visual & fondasi token", "D1 · Scope, navigasi, inventaris & flow" |

## Status export

Sumber artboard ada di `export/artboards/` dan menjadi acuan visual utama. File ini dibaca sebagai teks; pratinjaunya tidak berjalan sendiri karena butuh runtime canvas. Nama file terhubung ke judul artboard lewat `canvas.json`.

PNG per screen **tidak wajib** dan belum diekspor. Kalau nanti dibutuhkan untuk perbandingan visual, nama stabilnya:

- `SCR-010-S01-412-dark.png`, `SCR-010-S01-412-light.png`, `SCR-010-S01-360-dark.png`, `SCR-010-S01-360-light.png`
- `SCR-010-S02…S12-412-{dark,light}.png`
- `SCR-011-P01-412-{dark,light}.png`, `SCR-012-P02…P06-412-{dark,light}.png`, `SCR-013-P07…P12-412-{dark,light}.png`
- `SCR-013-P13…P15-412-{dark,light}.png`
- `SCR-001-Q01…Q05`, `SCR-002-Q06…Q07`, `SCR-003-Q08…Q11`, `SCR-003-Q12` — `-412-{dark,light}.png`
- `SCR-020-R01…R06`, `SCR-021-R04` — `-412-{dark,light}.png`

Langkah manual: buka canvas → pilih artboard → Share › Export (PNG, 2×) → simpan ke `export/screens/` dengan nama di atas. Board state berisi banyak layar sekaligus; crop per layar atau export board utuh sebagai `B1-states-dark.png` dst. lalu catat di tabel ini.

## Asumsi

- Port default agent 8765; format QR berisi alamat, token, nama laptop (format pastinya ditentukan saat scaffold).
- Jeda 5 detik sleep/restart/shutdown dipegang agent (perlu endpoint jadwalkan + batal + konfirmasi).
- Offline = 2 polling gagal berturut-turut (polling 5 detik).
- Haptic default nyala; tema default ikuti sistem.

## Celah yang disetujui

- Liquid Glass dipilih walau brief awal menghindari glassmorphism (keputusan pemilik produk). Wajib fallback solid.
- Restart ditambahkan ke scope Konfirmasi daya.
- Representasi 360 dp hanya untuk SCR-010 (layar lain mengikuti aturan layout di `components.md` C10).

## Aset pihak ketiga

| Aset | Sumber | Lisensi | Status |
| --- | --- | --- | --- |
| Geist, Geist Mono | Vercel (juga di Google Fonts) | SIL OFL 1.1 | belum diverifikasi |
| Ikon gaya Lucide (digambar ulang inline) | lucide.dev | ISC | belum diverifikasi |
| Scanner QR (`mobile_scanner`) | pub.dev | BSD-3-Clause | dipilih, lisensi terverifikasi di pub.dev |
