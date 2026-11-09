# Aksesibilitas

Remotto dipakai sebagai remote, sering sambil jalan atau dari seberang ruangan,
jadi kemudahan pakai penting. Dokumen ini menjelaskan komitmen, lingkungan yang
didukung, batasan, dan cara melapor.

## Komitmen

- Target sentuh cukup besar untuk tombol utama (play/pause, volume, daya).
- Kontras warna memadai di tema terang dan gelap, dan tema bisa mengikuti sistem.
- Status koneksi selalu terlihat dan tidak hanya dibedakan lewat warna.
- Aksi daya (sleep, restart, shutdown) memakai konfirmasi berlapis dan hitung mundur 5 detik yang bisa dibatalkan, supaya tidak terpicu tidak sengaja.
- Teks UI singkat dan memakai bahasa sehari-hari.

## Lingkungan yang didukung

- App: Android dan iOS (Flutter stable).
- Agent: Windows 10/11.
- Pembaca layar bawaan platform (TalkBack dan VoiceOver) dan pengaturan ukuran font sistem.

## Batasan yang diketahui

- Pairing lewat QR membutuhkan kamera. Input alamat dan token manual tersedia sebagai cadangan.
- Dukungan pembaca layar belum diuji menyeluruh di semua layar.
- Agent berjalan di terminal dan tidak punya antarmuka grafis.

## Melaporkan hambatan

Kalau menemukan hambatan aksesibilitas, buka
[issue](../../issues/new/choose) dengan template **Bug report** dan sebutkan:

- Layar atau fitur yang bermasalah.
- Teknologi bantu yang dipakai, perangkat, dan versi OS.
- Apa yang diharapkan dan apa yang terjadi.

Laporan aksesibilitas ditangani sama seriusnya dengan bug lain.
