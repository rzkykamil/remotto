# API Spec — Remotto Agent

Status dokumen: **draft Gate 2**. Folder `postman/` adalah representasi executable dari spec ini dan wajib sinkron. Nama modul di dokumen ini (Status, Media, Volume, Daya) menjadi nama folder di `postman/`.

## Konvensi

- **Base URL:** `http://<host>:<port>/api/v1`, port default 8765.
- **Format:** JSON UTF-8. Request dengan body wajib `Content-Type: application/json`.
- **Auth:** header `Authorization: Bearer <token>` di semua endpoint, tanpa pengecualian (BR-1).
- **Sukses:** `{ "data": ... }`
- **Error:** `{ "error": { "code": "...", "message": "..." } }`
- `message` aman ditampilkan di log app, tapi teks UI tetap diambil dari string app berdasarkan `code`.
- Body maksimal 1 KiB. Field tak dikenal ditolak.

## Kode status

| Status | Arti |
|---|---|
| 200 | Berhasil |
| 202 | Perintah daya dijadwalkan |
| 400 | Input salah |
| 401 | Token tidak ada atau salah |
| 403 | Alamat sumber di luar LAN yang diizinkan |
| 404 | Rute tidak ada, setelah lolos auth |
| 405 | Method salah, setelah lolos auth |
| 409 | Konflik jadwal daya |
| 429 | Rate limit; ada header `Retry-After` |
| 500 | Gagal di OS atau error internal; pesan aman |

## Kode error

| `code` | Status | Kapan |
|---|---|---|
| `invalid_token` | 401 | Token tidak ada, salah format, atau salah |
| `forbidden_network` | 403 | IP sumber di luar rentang yang diizinkan |
| `invalid_request` | 400 | JSON rusak, field salah, Content-Type salah, body terlalu besar |
| `invalid_level` | 400 | Level bukan bilangan bulat 0–100 |
| `not_found` | 404 | Rute tidak ada |
| `method_not_allowed` | 405 | Method salah |
| `power_pending` | 409 | Sudah ada jadwal daya |
| `no_pending_power` | 409 | Tidak ada yang dibatalkan |
| `power_executing` | 409 | Perintah sudah dieksekusi, terlambat batal |
| `rate_limited` | 429 | Terlalu banyak request |
| `media_failed` | 500 | Media key gagal dikirim |
| `audio_failed` | 500 | Core Audio gagal |
| `power_failed` | 500 | Penjadwalan gagal |
| `internal` | 500 | Error tak terduga |

Middleware berjalan dulu, sehingga `403`, `429`, dan `401` bisa muncul di endpoint mana pun.

## Objek bersama

**`Volume`**

| Field | Tipe | Keterangan |
|---|---|---|
| `level` | int | 0–100 |
| `muted` | bool | |

**`Pending`**, jadwal daya aktif

| Field | Tipe | Keterangan |
|---|---|---|
| `action` | string | `sleep`, `restart`, `shutdown` |
| `remainingMs` | int | Sisa jeda. `0` berarti sedang dieksekusi |
| `delayMs` | int | Total jeda |
| `scheduledAt` | string | RFC 3339, jam laptop, hanya untuk informasi |

App wajib memakai `remainingMs` dan `delayMs`, bukan `scheduledAt`, karena jam laptop dan HP bisa berbeda (BR-20). Lama sejak dijadwalkan = `delayMs − remainingMs`.

---

## Status

### `GET /status`

Membaca keadaan agent. Dipakai polling dan tes koneksi. Idempoten.

Respons 200:

```json
{
  "data": {
    "agentId": "a3f1c9e0b72d4e85916f0c2d7b4e13a8",
    "name": "Laptop-Kamil",
    "version": "1.0.0",
    "uptimeSeconds": 11520,
    "volume": { "level": 35, "muted": false },
    "pending": null
  }
}
```

- `agentId` berisi 32 karakter hex huruf kecil (`^[0-9a-f]{32}$`). Nilainya publik, stabil, dan tidak berubah saat `reset-token`. Nilai yang sama ada di TXT mDNS (lihat bagian Discovery). Agent yang belum memuat field ini (sebelum M7) tetap valid; app memperlakukannya sebagai tidak ada.
- `volume` bernilai `null` kalau Core Audio sedang gagal. Status tetap 200 agar koneksi tidak dianggap putus; app mempertahankan nilai terakhir.
- `pending` berisi objek `Pending` atau `null`.

Error: hanya middleware.

---

## Media

Tidak idempoten. App tidak boleh mengulang otomatis. Efeknya mengenai sesi media aktif Windows.

### `POST /media/play-pause`

### `POST /media/next`

### `POST /media/prev`

Tanpa body. Respons 200:

```json
{ "data": { "action": "play-pause" } }
```

Nilai `action`: `play-pause`, `next`, `prev`.

Error: 500 `media_failed`, misalnya saat layar terkunci.

---

## Volume

Semua respons sukses di modul ini berisi objek `Volume` terbaru, supaya app tidak perlu membaca ulang.

### `GET /volume`

Membaca level dan mute. Idempoten.

Respons 200:

```json
{ "data": { "level": 35, "muted": false } }
```

Error: 500 `audio_failed`.

### `PUT /volume`

Mengubah level dan mematikan mute (BR-15). Idempoten, aman di-retry 1 kali.

Body:

```json
{ "level": 35 }
```

Respons 200: `Volume`.

Error: 400 `invalid_level`, 400 `invalid_request`, 500 `audio_failed`. Nilai di luar rentang ditolak, tidak di-clamp (BR-3).

### `POST /volume/up`

### `POST /volume/down`

Menaikkan atau menurunkan level 5 poin (BR-16) lewat Core Audio dan mematikan mute. Di batas 0 atau 100, nilai berhenti di batas dan tetap 200. Tanpa body. Tidak idempoten.

Respons 200: `Volume`.

Error: 500 `audio_failed`.

### `POST /volume/mute`

Mengatur mute secara eksplisit. Dipilih dibanding toggle agar idempoten: retry dan dua HP tidak saling membalik status.

Body:

```json
{ "muted": true }
```

Respons 200: `Volume`.

Error: 400 `invalid_request`, 500 `audio_failed`.

---

## Daya

**Peringatan:** endpoint ini benar-benar mengubah status laptop setelah jeda 5 detik. Perintah tidak boleh di-retry otomatis.

### `POST /power/sleep`

### `POST /power/restart`

### `POST /power/shutdown`

Menjadwalkan perintah daya. Tanpa body. Tidak idempoten.

Respons 202:

```json
{
  "data": {
    "pending": {
      "action": "shutdown",
      "remainingMs": 5000,
      "delayMs": 5000,
      "scheduledAt": "2026-01-01T23:41:00+07:00"
    }
  }
}
```

Error:

- 409 `power_pending`, jadwal lama tidak berubah (BR-5). Pada kasus ini app membaca `/status` dan masuk ke P13.
- 500 `power_failed`.

Kegagalan OS saat eksekusi, setelah jeda habis, tidak bisa dibalas lewat request ini. Kejadiannya masuk log, `pending` dibersihkan, dan app kembali online lewat polling.

### `POST /power/cancel`

Membatalkan jadwal aktif. Tanpa body. Idempoten dari sisi efek.

Respons 200:

```json
{ "data": { "cancelled": "shutdown", "pending": null } }
```

Error:

- 409 `no_pending_power`, tidak ada jadwal (BR-17). App menganggapnya P08.
- 409 `power_executing`, sudah terlambat. App menampilkan P14.

---

## Discovery (mDNS)

Agent mengiklankan dirinya di LAN lewat DNS-SD. Ini bukan endpoint HTTP: tidak ada route baru, dan iklan hanya membantu app menemukan alamat IP terbaru. Akses tetap lewat `GET /status` dengan Bearer token.

| Item | Nilai |
|---|---|
| Service | `_remotto._tcp` |
| Nama instance | `Remotto-<8 hex pertama agentId>` |
| Port | Sama dengan `port` di config |
| Alamat | IPv4 dari A record, hanya di interface privat yang aktif |
| TXT `v` | `1` (versi skema iklan) |
| TXT `id` | `agentId` |
| TXT `name` | `laptopName`, maksimal 32 karakter, hanya untuk informasi |

- **TXT tidak pernah berisi token atau hash token.** Ada test yang memastikan ini.
- Iklan dimatikan saat `discovery.enabled` bernilai `false` di config.
- Iklan hanya dikirim di interface yang aktif, multicast, dan memakai IPv4 privat. WSL, Hyper-V, dan Tailscale dikecualikan.
- Hasil discovery adalah kandidat. App hanya menyimpannya setelah `GET /status` dengan token tersimpan mengembalikan 200 dan `agentId` yang sama. Aturannya ada di `docs/prd.md` (BR-22) dan `docs/flows/discovery-flow.md`.

---

## Ringkasan endpoint

| Modul | Method | Path | Sukses | Idempoten |
|---|---|---|---|---|
| Status | GET | `/status` | 200 | Ya |
| Media | POST | `/media/play-pause` | 200 | Tidak |
| Media | POST | `/media/next` | 200 | Tidak |
| Media | POST | `/media/prev` | 200 | Tidak |
| Volume | GET | `/volume` | 200 | Ya |
| Volume | PUT | `/volume` | 200 | Ya |
| Volume | POST | `/volume/up` | 200 | Tidak |
| Volume | POST | `/volume/down` | 200 | Tidak |
| Volume | POST | `/volume/mute` | 200 | Ya |
| Daya | POST | `/power/sleep` | 202 | Tidak |
| Daya | POST | `/power/restart` | 202 | Tidak |
| Daya | POST | `/power/shutdown` | 202 | Tidak |
| Daya | POST | `/power/cancel` | 200 | Ya, efeknya |

`GET /ws` tidak dibuat. Polling dipilih, lihat `docs/decision-log.md`.
