# Screens

Representasi: **lengkap** = screen penuh statis, terang + gelap · **proto** = ada di prototype interaktif.
Semua screen 412 dp, kecuali yang disebut. Artefak berupa nama artboard di canvas (lihat README); PNG belum diekspor.

| Screen ID | Modul | Tujuan | Komponen | State | Representasi | Artefak | Ukuran | Status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| SCR-001 | Pairing | Hubungkan HP ke laptop lewat QR | C15, C16, C02, C07 | Q01 intro · Q02 izin kamera · Q03 scan · Q04 QR tidak valid · Q05 izin ditolak permanen | lengkap + proto | B3+B4 Pairing & error; Prototype pairing | 412 | disetujui |
| SCR-002 | Pairing | Fallback isi alamat + token | C15, C17, C02 | Q06 kosong · Q07 format salah · siap (proto) | lengkap + proto | B3+B4 Pairing & error; Prototype pairing | 412 | disetujui |
| SCR-003 | Pairing | Tes koneksi & hasil | C15, C18 | Q08 menyambung · Q09 berhasil · Q10 timeout · Q11 token ditolak | lengkap + proto | B3+B4 Pairing & error; Prototype pairing | 412 | disetujui |
| SCR-003 (B4) | Pairing | Token kedaluwarsa saat dipakai | C15 | Q12 | lengkap | B3+B4 Pairing & error | 412 | disetujui |
| SCR-010 | Remote | Kontrol harian | C01–C10 | S01 terhubung · S02 menyambung · S03 diproses · S04 gagal kirim · S05 slider ditarik · S06 slider gagal · S07 mute · S08 vol 0 · S09 vol 100 · S10 offline · S11 nyambung lagi · S12 teks 130% + nama panjang | lengkap + proto (default, tweak status) | SCR-010 Remote (4 artboard); B1 SCR-010 state | 412 + 360 (default) | disetujui |
| SCR-011 | Konfirmasi daya | Konfirmasi sleep | C11 | P01 | lengkap + proto | B2 Konfirmasi daya; Prototype daya | 412 | disetujui |
| SCR-012 | Konfirmasi daya | Konfirmasi restart/shutdown 2 tahap | C11, C12 | P02 tahap 1 · P03 tahap 2 · P04 ditahan · P05 lepas cepat · P06 restart | lengkap + proto | B2 Konfirmasi daya; Prototype daya | 412 | disetujui |
| SCR-013 | Konfirmasi daya | Hitung mundur & hasil | C13, C14, C07 | P07 berjalan · P08 dibatalkan · P09 terkirim · P10 gagal dijadwalkan · P11 batal gagal · P12 reduced motion | lengkap + proto (P07–P09) | B2 Konfirmasi daya; Prototype daya | 412 | disetujui |
| SCR-013 (revisi) | Konfirmasi daya | App dibuka saat perintah daya berjalan | C13, C14, C08 | P13 dibuka saat hitung mundur · P14 telat batal · P15 laptop udah mati | lengkap | B2 revisi · Buka app saat hitung mundur | 412 | disetujui |
| SCR-020 | Pengaturan | Info laptop, tema, haptic, versi | C19, C20, C21 | R01 default · R02 gelap + getar mati · R03 teks 130% · R05 offline · R06 reduce transparency | lengkap | B5 Pengaturan | 412 | disetujui |
| SCR-021 | Pengaturan | Konfirmasi pairing ulang | C22 | R04 | lengkap | B5 Pengaturan | 412 | disetujui |

## Di luar scope (sesuai brief)

Now playing, Wake-on-LAN, widget homescreen, multi-laptop, jadwal shutdown, akun/billing, onboarding panjang, tablet/landscape, tampilan agent di laptop, layar lisensi (baris "Lisensi open source" di artboard SCR-020 tidak diimplementasikan), notifikasi lokal selama hitung mundur.

## Perilaku lintas ukuran

- **360 dp:** margin 20, play 88, media 72, angka 108. Untuk layar selain SCR-010: sheet inset 8 dengan padding 20, cincin hitung mundur 220.
- **390 pt (iOS):** memakai aturan ≥390 (sama dengan 412) dengan safe area notch + home indicator. Belum dibuat sebagai artboard terpisah; tercatat di `review.md`.
- **Teks besar:** S12, R03.
