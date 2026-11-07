# Review

Pemeriksaan desain, bukan pengujian app berjalan.

## Pemeriksaan yang dilakukan

### 1. Kontras warna (dihitung)

**Metode:** rasio kontras WCAG 2.x dari nilai hex. Untuk teks di atas kaca, latar dihitung sebagai komposit kasus terburuk:

- Terang: `glass.fill` (putih 45%) di atas `bg.base` yang ditimpa `bg.glowA` (oranye 22%) di titik terkuatnya.
- Gelap: `glass.fill` (putih 7%) di atas `bg.base` yang ditimpa `bg.glowA` (18%).

| Pasangan | Terang | Gelap | Hasil |
| --- | --- | --- | --- |
| `fg.primary` / kaca terburuk | 14.0 | 10.4 | lulus |
| `fg.secondary` / kaca terburuk | 6.1 | 6.0 | lulus |
| `accent.text` / kaca terburuk | 5.3 | 5.9 | lulus |
| `status.success` / kaca terburuk | 5.6 | 6.2 | lulus |
| `status.warning` / kaca terburuk | 5.6 | 7.0 | lulus |
| `fg.disabled` / kaca terburuk | 2.4 | 2.2 | sengaja di bawah 4.5; selalu ada teks penjelas |
| `accent.on` / `accent.default` (ikon play) | 6.1 | 6.2 | lulus |
| `status.onDanger` / `status.danger` | 5.9 | 6.9 | lulus |
| `slider.fill` / kaca terburuk (non-teks, ≥3:1) | 14.0 | 8.8 | lulus |

**Catatan:**

- Versi awal glow (alpha 0.38 / 0.30) gagal untuk `accent.text` dan `status.success`. Glow diturunkan dan warna status digelapkan/dicerahkan sampai lulus.
- Teks di sheet dan overlay hitung mundur (tint 86–94%) lebih aman daripada kasus terburuk di atas.

### 2. tokens.json

- **Metode:** parse JSON + skrip: kumpulkan semua leaf (`type` + `value`), resolve setiap alias `{path}`, deteksi siklus, bandingkan key `semantic.light` vs `semantic.dark`, cek format hex.
- **Hasil:**
  - JSON valid;
  - 202 leaf;
  - 0 alias rusak, 0 siklus;
  - key light = dark;
  - semua warna primitif `#RRGGBB` (alpha di field `alpha`).

### 3. Target sentuh (dari spesifikasi)

| Elemen | Ukuran |
| --- | --- |
| Play | 96 / 88 dp |
| Media | 80 / 72 dp |
| Kontrol | 56 dp |
| Daya | 52 dp |
| Tahan | 72 dp |
| Batal | 80 dp |
| Segmen | ≥48 dp |
| Tombol ikon | 48 dp |

Tidak ada target < 48 dp. Ukuran diukur dari spesifikasi artboard, bukan di perangkat.

### 4. Uji satu tangan (berdasarkan layout)

- Play, prev/next, slider, mute, −/+ berada di ±50% bawah layar 412×915.
- Tombol daya ada di atas.
- Aksi utama pairing dan "Nggak jadi" / "Batal" ada di bawah.

### 5. Keamanan UX daya (berdasarkan desain + prototype)

- Shutdown/restart butuh: tap di area atas → tap "Lanjut" → tahan 1,2 detik → 5 detik tanpa batal.
- Satu ketukan tidak bisa mematikan laptop.
- Batal tersedia sepanjang hitung mundur; back sistem = batal.
- Di Prototype daya: lepas cepat mereset; Batal kembali ke Remote dengan toast.

### 6. Konten sulit

| Kasus | Representasi |
| --- | --- |
| Nama laptop panjang | S12, R03 |
| Teks 130% | S12, R03 |
| Volume 0 / 100 | S08, S09, artboard 360 |
| Offline saat slider ditarik | aturan C04 + catatan S10 (tanpa layar tersendiri) |

### 7. Logo

SVG dirender ke PNG (1024/512/192) dan dicek visual: terbaca di dua varian.

**Ukuran kecil 48 dp belum dicek.**

### 8. Manifest

Daftar file di README dicocokkan dengan isi folder (lihat bagian terakhir).

## Belum diverifikasi

- **Tampilan render canvas:** artboard tidak di-screenshot dan dicek ulang di sesi ini. Review visual dilakukan oleh pemilik produk di canvas.
- **Di perangkat nyata:**
  - kontras di atas viewfinder kamera;
  - rasa ukuran slider di 360 dp;
  - rasa tahan 1,2 detik di kasur;
  - performa `BackdropFilter` di Android kelas bawah.
- **TalkBack / VoiceOver:** urutan fokus, pengumuman liveRegion, custom action "Matikan sekarang", slider kustom (C03, C04, C07, C11, C12, C13, C16).
- **iOS 390 pt:** tidak ada artboard tersendiri; aturan diturunkan dari 412.
- **Lisensi:** Geist/Geist Mono (OFL 1.1), ikon gaya Lucide (ISC), paket scanner QR.
- **PNG per screen** belum diekspor (lihat README).

## Isu terbuka

1. Port agent & format QR (asumsi 8765, `remotto://…`).
2. API agent untuk jadwalkan/batal/konfirmasi perintah daya.
3. Retry volume diam-diam: perlu idempotensi di agent.
4. Ambang layar pendek <700 dp.
5. Ikon app di 48 dp: dua titik kecil mungkin hilang; pertimbangkan varian sederhana (kapsul + bola saja).

## Pengecualian yang disetujui

- Arah Liquid Glass (menyimpang dari anti-pattern awal brief), dengan syarat fallback solid.
- Restart masuk scope.
- Error form memakai oranye, bukan merah.
- SCR-010 satu-satunya screen dengan artboard 360 dp.
