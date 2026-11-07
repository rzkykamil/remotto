# User Flow

Screen dan state merujuk `design/screens.md`.

## Pairing pertama

```mermaid
flowchart TD
  A([Buka app, belum ada data]) --> Q01[Q01 Intro]
  Q01 -->|Scan QR| Q02[Q02 Penjelasan izin]
  Q01 -->|Isi manual| Q06[Q06 Form manual]
  Q02 --> IZ{Izin kamera}
  IZ -->|Diizinkan| Q03[Q03 Scan]
  IZ -->|Ditolak permanen| Q05[Q05 Izin ditolak]
  Q05 -->|Buka pengaturan HP| IZ
  Q05 -->|Isi manual| Q06
  Q03 --> V{QR valid}
  V -->|Tidak| Q04[Q04 Banner, kamera tetap jalan]
  Q04 --> Q03
  V -->|Ya| Q08[Q08 Tes koneksi]
  Q03 -->|Isi manual| Q06
  Q06 --> F{Format valid}
  F -->|Tidak| Q07[Q07 Format salah]
  Q07 --> Q06
  F -->|Ya| Q08
  Q08 --> T{Hasil GET status}
  T -->|200| Q09[Q09 Berhasil]
  T -->|Tidak terjangkau| Q10[Q10 Timeout dan tips]
  T -->|401| Q11[Q11 Token ditolak]
  Q10 -->|Coba lagi| Q08
  Q10 -->|Ubah alamat| Q06
  Q11 -->|Scan ulang QR| Q03
  Q09 -->|Mulai pakai| S01[S01 Terhubung]
```

## Pakai harian

```mermaid
flowchart TD
  A([Buka app]) --> S02[S02 Menyambung]
  S02 --> K{Polling pertama}
  K -->|Ada pending| PW[Lihat alur daya]
  K -->|Berhasil| S01[S01 Terhubung]
  K -->|2 kali gagal| S10[S10 Offline]
  S01 -->|Play, prev, next| CMD{Hasil perintah}
  CMD -->|Berhasil| S01
  CMD -->|Lebih dari 400 ms| S03[S03 Diproses]
  S03 --> CMD
  CMD -->|Gagal atau timeout| S04[S04 Toast Ulangi]
  S04 -->|Ulangi| CMD
  S01 -->|Geser slider| S05[S05 Ditarik]
  S05 --> VOL{Hasil PUT volume}
  VOL -->|Berhasil| S01
  VOL -->|Gagal| S06[S06 Rollback + toast]
  S06 --> S01
  S01 -->|Mute| S07[S07 Mute]
  S01 -->|401| Q12[Q12 Pairing ulang]
```

## Daya, dengan batal

```mermaid
flowchart TD
  S01[S01 Terhubung] -->|Sleep| P01[P01 Konfirmasi]
  S01 -->|Matikan| P02[P02 Tahap 1]
  S01 -->|Restart| P06[P06 Tahap 1 restart]
  P01 -->|Nggak jadi| S01
  P02 -->|Nggak jadi| S01
  P06 -->|Nggak jadi| S01
  P02 -->|Lanjut| P03[P03 Tahap 2]
  P06 -->|Lanjut| P03
  P03 --> P04[P04 Ditahan]
  P04 -->|Lepas cepat| P05[P05 Reset]
  P05 --> P03
  P04 -->|Penuh| SC{Jadwalkan ke agent}
  P01 -->|Sleep-in| SC
  SC -->|202| P07[P07 Hitung mundur]
  SC -->|Gagal| P10[P10 Gagal dijadwalkan]
  P10 -->|Coba lagi| P03
  P10 -->|Tutup| S01
  P07 -->|Batal atau back| CN{Batal ke agent}
  CN -->|200 atau tidak ada jadwal| P08[P08 Dibatalkan + toast]
  P08 --> S01
  CN -->|Timeout| P11[P11 Batal gagal]
  P11 -->|Batal lagi| CN
  CN -->|Sudah dieksekusi| P14[P14 Telat batal]
  P07 -->|Waktu habis| P09[P09 Terkirim]
  P09 -->|Sleep atau shutdown| P15[P15 Laptop lagi mati]
  P09 -->|Restart| FAST[Remote, polling 2 detik]
```

## App dibuka saat perintah daya berjalan

```mermaid
flowchart TD
  A([App dibuka atau resume]) --> S02[S02 Maks 2 detik]
  S02 --> K{Status}
  K -->|pending, sisa minimal 1 detik| P13[P13 Lanjut hitung mundur]
  K -->|pending, sisa kurang dari 1 detik| P14[P14 Telat batal]
  K -->|Tidak terjangkau, ada lastPowerCommand kurang dari 10 menit| P15[P15 Laptop lagi mati]
  K -->|Tidak terjangkau, tanpa perintah terakhir| S10[S10 Offline]
  K -->|Tanpa pending| S01[S01 Terhubung]
  P13 --> P07[Lanjut seperti P07]
  P14 -->|Oke| REM[Remote]
  P15 -->|Lewat 10 menit| S10
```

## Offline ke online

```mermaid
flowchart TD
  S01[S01 Terhubung] -->|2 polling gagal| S10[S10 Offline]
  S10 -->|Coba lagi| P{Polling langsung}
  P -->|Gagal| S10
  P -->|Berhasil| S11[S11 Nyambung lagi]
  S10 -->|Polling berhasil| S11
  S11 -->|2 detik| S01
  S10 -->|Pairing ulang| R04[R04 Konfirmasi]
  R04 -->|Hapus dan pairing ulang| Q01[Q01 Intro]
  R04 -->|Nggak jadi| S10
```

## Pairing ulang

```mermaid
flowchart TD
  S01[S01 Terhubung] -->|Tombol pengaturan| R01[R01 Pengaturan]
  R01 -->|Pairing ulang| R04[R04 Konfirmasi]
  R04 -->|Nggak jadi| R01
  R04 -->|Hapus dan pairing ulang| Q01[Q01 Intro, stack lama dibuang]
  ANY([401 dari layar mana pun]) --> Q12[Q12 Token ditolak]
  Q12 -->|Scan ulang QR| Q03[Q03 Scan]
```
