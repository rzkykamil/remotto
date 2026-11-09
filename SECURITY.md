# Kebijakan Keamanan

Remotto bisa mematikan, me-restart, dan men-sleep laptop, jadi keamanan adalah
inti proyek ini. Semua endpoint agent wajib token dan agent hanya untuk LAN.

## Versi yang didukung

Perbaikan keamanan hanya diberikan untuk rilis terbaru dan branch `main`.

## Melaporkan celah keamanan

**Jangan membuka issue publik untuk celah keamanan.**

Laporkan secara privat lewat
[GitHub Private Vulnerability Reporting](../../security/advisories/new)
(tab **Security** → **Report a vulnerability**).

Sertakan sebisanya:

- Deskripsi celah dan dampaknya.
- Langkah untuk mereproduksi, termasuk versi agent dan app.
- Saran perbaikan, kalau ada.

Proyek ini dikelola secara pribadi, jadi laporan ditargetkan dibalas dalam
beberapa hari. Setelah celah diperbaiki, pelapor akan dikreditkan kalau
bersedia.

## Yang termasuk cakupan

- Melewati autentikasi token atau mengakses endpoint tanpa token.
- Kebocoran token, misalnya lewat log, QR, atau penyimpanan.
- Eksekusi perintah daya (sleep, restart, shutdown) tanpa izin.
- Agent terjangkau dari luar LAN pada konfigurasi bawaan.

## Batasan yang sudah diketahui

- Lalu lintas LAN memakai HTTP tanpa enkripsi. Gunakan di jaringan yang dipercaya.
- Jangan pernah port-forward port agent ke internet. Untuk akses dari luar rumah, pakai Tailscale.
- Kalau HP hilang, jalankan `remotto-agent reset-token` untuk mencabut token lama.
