# Scope & flows

## Tujuan

Remote pribadi untuk satu laptop Windows, dipakai satu tangan sambil rebahan, sering di ruangan gelap.

Indikator UX:

- Media dan volume bisa dikendalikan satu tangan, satu ketukan, tanpa membaca.
- Shutdown/restart tidak mungkin terjadi tanpa disengaja.
- Status online/offline selalu jelas.

Tiga tugas utama: (1) play/pause + prev/next, (2) volume + mute, (3) sleep / restart / shutdown yang aman.

## Navigasi

```text
Pairing (first-run) ──berhasil──▶ Remote (home) ⇄ Pengaturan
                                     │
                                     ├─ sheet Sleep ─────────────▶ Hitung mundur ─▶ Hasil
                                     ├─ sheet Restart (1→2 tahan) ▶ Hitung mundur ─▶ Hasil
                                     └─ sheet Matikan (1→2 tahan) ▶ Hitung mundur ─▶ Hasil
Token ditolak (401) dari mana pun ─▶ Pairing (Q12)
Pengaturan ▸ Pairing ulang ─▶ konfirmasi ─▶ Pairing (Q01), stack lama dibuang
```

Tombol back sistem:

- Di Remote: keluar dari app.
- Di Pengaturan: kembali ke Remote.
- Di sheet: menutup sheet (sama dengan "Nggak jadi").
- Di hitung mundur: sama dengan **Batal**.
- Di pairing: kembali satu langkah.

## Flow utama + pemulihan

### (a) Pairing pertama kali

Q01 intro → "Scan QR" → Q02 penjelasan izin → dialog izin OS → Q03 scan → QR terbaca → Q08 tes koneksi (Laptop ketemu → Cek token → Simpan) → Q09 berhasil → "Mulai pakai" → Remote S01.

Pemulihan:

- QR bukan Remotto → Q04 (banner, kamera tetap jalan).
- Izin ditolak permanen → Q05 → "Buka pengaturan HP" / "Isi manual".
- "Isi manual" (selalu tersedia) → Q06/Q07 → Q08.
- Laptop tidak ditemukan → Q10 (tips) → "Coba lagi" / "Ubah alamat".
- Token ditolak → Q11 → "Scan ulang QR".

### (b) Pakai harian

Buka app → S02 menyambung (maksimal 2 polling) → S01 terhubung → tap play/pause (optimistic + haptic), geser slider (kirim setiap 100 ms + nilai akhir), mute, −/+.

Pemulihan:

- Perintah gagal (timeout 3 detik) → ikon kembali + toast "Ulangi" (S04).
- Volume gagal → nilai kembali ke nilai laptop + toast (S06).

### (c) Sleep / restart / shutdown

- Sleep: tap Sleep → P01 konfirmasi → hitung mundur 5 detik → terkirim.
- Restart/Matikan: tap tombol → P02 tahap 1 "Yakin?" → "Lanjut" → P03 tahap 2, tahan 1,2 detik → P07 hitung mundur 5 detik → P09 terkirim.

Pemulihan:

- Batal kapan pun selama hitung mundur → P08 + toast "Nggak jadi dimatiin".
- Gagal menjadwalkan → P10 (laptop dipastikan tidak mati).
- Batal tidak sampai → P11 (peringatan + "Batal lagi").
- Dilepas terlalu cepat saat tahan → P05 (reset, tanpa error).
- Setelah matikan/sleep terkirim → "Oke" → Remote dalam status offline dengan judul "Laptop lagi mati".
- App dibuka saat jadwal berjalan: S02 selama polling pertama (maks 2 detik), lalu `pending` dengan sisa ≥ 1 detik → P13; sisa < 1 detik atau sedang eksekusi → P14, tanpa Batal.
- App dibuka, laptop tidak terjangkau, dan ada perintah matikan/sleep lokal < 10 menit → P15. Lewat 10 menit → S10 biasa.

### (d) Offline → online

2 polling gagal → S10: semua kontrol nonaktif, panel berisi penjelasan + "Coba lagi" / "Pairing ulang". Polling tetap jalan. Begitu berhasil → S11: pill "Nyambung lagi" selama 2 detik + toast, volume disinkronkan.

Jika offline terjadi saat slider sedang ditarik, gesture dibatalkan dan slider kembali ke nilai terakhir.

## Batas scope

| Modul | Dalam scope | Di luar scope |
| --- | --- | --- |
| Pairing | Scan QR, izin kamera, tes koneksi, simpan, error jelas, input manual alamat + token | Multi-laptop |
| Remote | Play/pause, prev/next, slider volume + persen, mute, −/+, Sleep, Restart, Matikan, status online/offline, nama laptop, uptime | Now playing, Wake-on-LAN, widget homescreen |
| Konfirmasi daya | Sleep 1 konfirmasi; restart/shutdown 2 tahap (tahan); hitung mundur 5 detik bisa batal | Jadwal / timer shutdown |
| Pengaturan | Info laptop, pairing ulang, tema Terang/Gelap/Sistem, haptic on/off, versi | Akun, billing, onboarding panjang |

Non-goal lain: tablet/landscape, akses dari luar rumah, tampilan agent di laptop.

## Aturan bisnis yang berdampak ke UI

- Semua request membawa token. 401 → Q12.
- Sleep/restart/shutdown tidak langsung jalan: delay 5 detik dipegang agent, bisa dibatalkan.
- Volume 0–100, step slider 1, tombol −/+ step 5.
- Semua kontrol nonaktif saat offline atau menyambung.
- Polling status setiap 5 detik; offline setelah 2 kali gagal; timeout perintah 3 detik.

## Keputusan yang masih perlu konfirmasi saat scaffold

1. Port default agent 8765. Format QR berupa JSON, lihat `docs/data-design.md`.
2. API agent untuk jadwalkan dan batal perintah daya: status membawa `pending {action, remainingMs, scheduledAt}` atau null; rincian di `docs/api-spec.md`.
3. Retry volume diam-diam 1 kali: aman atau tidak di sisi agent (idempotensi).
4. Ambang "layar pendek" (<700 dp tinggi) untuk mode ringkas Remote: perlu dicek di HP nyata.
