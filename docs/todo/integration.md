# Integrasi

Path disesuaikan dengan file sebenarnya saat fase Integrasi. Status: `Belum` / `Proses` / `Selesai`.

## M0 Fondasi Proyek

Tidak ada endpoint. Fase ini dicatat "tidak relevan" saat dijalankan.

## M1 Pairing & Koneksi

| Screen/Widget | Endpoint | Status | Catatan |
|---|---|---|---|
| `lib/features/pairing/` Q08 tes koneksi | `GET /status` | Selesai | 200 → Q09; 401 → Q11; tidak terjangkau → Q10. Tes loopback; HP di `waiting.md` |
| `lib/core/connection/` polling | `GET /status` | Selesai | Dua gagal → S10; 401 → Q12; satu polling berjalan. Tes loopback; HP di `waiting.md` |
| `lib/features/remote/` `StatusPill` | `GET /status` | Selesai | Uptime, nama laptop dari respons agent asli. Pembuktian di HP di `waiting.md` |

## M2 Kontrol Media

| Screen/Widget | Endpoint | Status | Catatan |
|---|---|---|---|
| `PlayKey` | `POST /media/play-pause` | Selesai | Tanpa retry; gagal → S04; 500 saat layar terkunci. Tes loopback; HP di `waiting.md` |
| Dock next | `POST /media/next` | Selesai | Tanpa retry. Tes loopback; HP di `waiting.md` |
| Dock prev | `POST /media/prev` | Selesai | Tanpa retry. Tes loopback; HP di `waiting.md` |

## M3 Volume

| Screen/Widget | Endpoint | Status | Catatan |
|---|---|---|---|
| `VolumeSlider` | `PUT /volume` | Selesai | Retry 1 kali oleh VolumeSender; 400/429 lewat toast S06 + rollback. Tes loopback; HP di `waiting.md` |
| Tombol + | `POST /volume/up` | Selesai | Tanpa retry. Tes loopback; HP di `waiting.md` |
| Tombol − | `POST /volume/down` | Selesai | Tanpa retry. Tes loopback; HP di `waiting.md` |
| Tombol mute | `POST /volume/mute` | Selesai | Retry 1 kali diam-diam oleh controller. Tes loopback; HP di `waiting.md` |
| Sinkron nilai | `GET /status` | Selesai | `volume: null` → pertahankan nilai terakhir. Tes loopback; HP di `waiting.md` |

## M4 Daya

| Screen/Widget | Endpoint | Status | Catatan |
|---|---|---|---|
| P01 Sleep | `POST /power/sleep` | Selesai | 202 → P07; gagal → P10; timeout → baca status. Tes loopback + kontrak; HP/laptop di `waiting.md` |
| P03 Restart | `POST /power/restart` | Selesai | Sama; setelah 0 polling cepat. Tes loopback + kontrak; HP/laptop di `waiting.md` |
| P03 Matikan | `POST /power/shutdown` | Selesai | Sama; 409 → P13. Tes loopback + kontrak; HP/laptop di `waiting.md` |
| `CountdownScreen` Batal | `POST /power/cancel` | Selesai | 200 → P08; 409 → P08 atau P14; timeout → P11. Tes loopback + kontrak; HP/laptop di `waiting.md` |
| P13, P14 saat resume | `GET /status` | Selesai | `pending`, `remainingMs`, `delayMs`. Tes loopback + kontrak (parse dan `resumeFromStatus` langsung, bukan lewat widget host); HP di `waiting.md` |
| P15 | `GET /status` gagal | Selesai | `lastPowerCommand` < 10 menit. Memakai `GET /status` yang sudah jalan sejak M1; tes di `power_http_flow_test.dart`; HP di `waiting.md` |

## M5 Pengaturan & Tema

| Screen/Widget | Endpoint | Status | Catatan |
|---|---|---|---|
| SCR-020 info laptop | `GET /status` | Belum | R05 pakai data terakhir |
| Q12 setelah `reset-token` | Semua endpoint | Selesai | 401 → pairing ulang. Sisi agent `TestServeAgentResetTokenRejectsAllRoutes`; sisi app tes 401 per endpoint. Pembuktian di HP di `waiting.md` |

## M6 Ketahanan & Startup

| Screen/Widget | Endpoint | Status | Catatan |
|---|---|---|---|
| Resume app | `GET /status` | Selesai | S02 maksimal 2 detik. `connection_resume_http_test.dart` (HTTP asli, scheduler asli, batas 2 detik sebagai asersi). Pembuktian nyata di HP di `waiting.md` |
| Semua repository | Semua endpoint | Selesai | 429 dan timeout konsisten. Tes 429 di media, volume, power, dan poll status; agent asli di `run_e2e_test.go` |
