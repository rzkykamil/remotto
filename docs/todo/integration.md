# Integrasi

Path disesuaikan dengan file sebenarnya saat fase Integrasi. Status: `Belum` / `Proses` / `Selesai`.

## M0 Fondasi Proyek

Tidak ada endpoint. Fase ini dicatat "tidak relevan" saat dijalankan.

## M1 Pairing & Koneksi

| Screen/Widget | Endpoint | Status | Catatan |
|---|---|---|---|
| `lib/features/pairing/` Q08 tes koneksi | `GET /status` | Belum | 200 → Q09; 401 → Q11; tidak terjangkau → Q10 |
| `lib/core/connection/` polling | `GET /status` | Belum | Dua gagal → S10; 401 → Q12; satu polling berjalan |
| `lib/features/remote/` `StatusPill` | `GET /status` | Belum | Uptime, nama laptop |

## M2 Kontrol Media

| Screen/Widget | Endpoint | Status | Catatan |
|---|---|---|---|
| `PlayKey` | `POST /media/play-pause` | Belum | Tanpa retry; gagal → S04; 500 saat layar terkunci |
| Dock next | `POST /media/next` | Belum | Tanpa retry |
| Dock prev | `POST /media/prev` | Belum | Tanpa retry |

## M3 Volume

| Screen/Widget | Endpoint | Status | Catatan |
|---|---|---|---|
| `VolumeSlider` | `PUT /volume` | Belum | Throttle, retry 1 kali, rollback S06, 400, 429 |
| Tombol + | `POST /volume/up` | Belum | Tanpa retry |
| Tombol − | `POST /volume/down` | Belum | Tanpa retry |
| Tombol mute | `POST /volume/mute` | Belum | Retry 1 kali |
| Sinkron nilai | `GET /status` | Belum | `volume: null` → pertahankan nilai terakhir |

## M4 Daya

| Screen/Widget | Endpoint | Status | Catatan |
|---|---|---|---|
| P01 Sleep | `POST /power/sleep` | Belum | 202 → P07; gagal → P10; timeout → baca status |
| P03 Restart | `POST /power/restart` | Belum | Sama; setelah 0 polling cepat |
| P03 Matikan | `POST /power/shutdown` | Belum | Sama; 409 → P13 |
| `CountdownScreen` Batal | `POST /power/cancel` | Belum | 200 → P08; 409 → P08 atau P14; timeout → P11 |
| P13, P14 saat resume | `GET /status` | Belum | `pending`, `remainingMs`, `delayMs` |
| P15 | `GET /status` gagal | Belum | `lastPowerCommand` < 10 menit |

## M5 Pengaturan & Tema

| Screen/Widget | Endpoint | Status | Catatan |
|---|---|---|---|
| SCR-020 info laptop | `GET /status` | Belum | R05 pakai data terakhir |
| Q12 setelah `reset-token` | Semua endpoint | Belum | 401 → pairing ulang |

## M6 Ketahanan & Startup

| Screen/Widget | Endpoint | Status | Catatan |
|---|---|---|---|
| Resume app | `GET /status` | Belum | S02 maksimal 2 detik |
| Semua repository | Semua endpoint | Belum | 429 dan timeout konsisten |
