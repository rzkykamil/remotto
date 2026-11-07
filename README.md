# Remotto

Remote pribadi untuk laptop Windows. App di HP mengirim perintah lewat WiFi yang sama ke agent kecil yang jalan di laptop: play/pause, volume, sleep, restart, dan shutdown.

## Cara kerja

- **Agent** (`agent/`, Go): satu binary `remotto-agent.exe` di laptop. Menerima perintah HTTP di LAN dan menjalankannya di level OS.
- **App** (`app/`, Flutter): remote di HP Android atau iOS.

Tidak ada server, akun, atau cloud. Satu laptop, satu pemilik.

## Fitur

- Pairing lewat QR, dengan input manual sebagai cadangan
- Play/pause, next, prev
- Volume lewat slider atau −/+, dan mute
- Sleep, restart, shutdown dengan konfirmasi berlapis dan hitung mundur 5 detik yang bisa dibatalkan
- Status koneksi selalu terlihat
- Tema terang, gelap, ikuti sistem

## Prasyarat

- Windows 10/11 untuk menjalankan agent
- Go 1.27
- Flutter stable (3.47 atau lebih baru)
- HP Android atau emulator. iOS butuh Mac untuk build.

## Setup & run lokal

Agent:

```powershell
cd agent
go run ./cmd/agent run
```

App:

```powershell
cd app
flutter pub get
flutter run
```

## Pairing

```powershell
cd agent
go run ./cmd/agent pair
```

Scan QR yang tampil dari layar pairing di app. Kalau kamera tidak tersedia, isi alamat dan token secara manual.

## Postman

Folder `postman/` berisi collection untuk semua endpoint. Buka lewat Postman, pilih environment `Remotto Agent`, lalu isi `baseUrl` dan `token`.

Request di folder `Daya` benar-benar men-sleep, me-restart, atau mematikan laptop setelah 5 detik.

## Keamanan

- Semua endpoint wajib token.
- Agent hanya untuk LAN. Aturan firewall hanya untuk profil Private.
- Jangan pernah port-forward port agent ke internet. Untuk akses dari luar rumah, pakai Tailscale.
- Lalu lintas LAN memakai HTTP tanpa enkripsi, jadi gunakan di jaringan yang dipercaya.
- Kalau HP hilang, jalankan `remotto-agent reset-token`.

## Dokumentasi

| File | Isi |
|---|---|
| `docs/prd.md` | Kebutuhan produk |
| `docs/technical-spec.md` | Desain teknis |
| `docs/api-spec.md` | Kontrak API |
| `docs/design-system.md` | Sistem desain di Flutter |
| `docs/release.md` | Build, instalasi, rilis, rollback |
| `docs/development-workflow.md` | Siklus pengembangan |
