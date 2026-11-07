# Backlog Integrasi

Satu baris per temuan, dengan referensi inline. Heading modul tidak boleh dihapus.

## M0 Fondasi Proyek

Belum ada temuan.

## M1 Pairing & Koneksi

- [ ] 403 dan 429 saat pairing masih tampil sebagai Q10 "tidak terjangkau". Perlu keputusan copy dari desain (`PairingFlowController`).
- [ ] `Future.timeout` tidak membatalkan request atau socket; poll yang sedang berjalan maksimal satu, dampak kecil (`lib/core/network/agent_http_client.dart`).
- [ ] iOS `NSAllowsLocalNetworking` dengan IP Tailscale (100.64/10) belum terbukti di iPhone sungguhan; lihat `waiting.md`.
- [ ] Tidak ada logging request di app. Ditunda ke M6; token tidak boleh masuk log.
- [ ] Polling tetap jalan di jaringan seluler saat laptop di luar LAN. Ditunda ke M6.
- [ ] IPv6 literal tidak didukung di input host (`lib/features/pairing/`).
- [ ] Komentar dan nama tes dalam bahasa Indonesia di `test/integration/*`, `test/support/fake_poll_scheduler.dart`, `fake_agent_server.dart`, dan `fake_pairing_repository_test.dart`. Aturan bahasa: kode dan komentar Inggris.
- [ ] Ada dua fake poll scheduler: `connection_controller_test.dart` dan `test/support/fake_poll_scheduler.dart`. Satukan.
- [ ] Tes "path lain 404" hanya menguji server palsu di `test/integration/`, bukan agent Go asli.

## M2 Kontrol Media

- [ ] Tes media hanya menguji server palsu di `test/integration/`, bukan agent Go asli. Pembuktian dengan agent asli ada di `waiting.md` M2 Integrasi.
- [ ] `Future.timeout` pada `postMedia` tidak membatalkan request; request yang sudah terkirim bisa tetap diproses setelah timeout. Sama dengan item M1 di atas. Tanpa retry otomatis, jadi tidak ada perintah ganda.
- [ ] `pairing_repository.dart` baris 4 dan `status_repository.dart` baris 3 masih menyebut "Mock". Di luar lingkup M2; ganti di fase yang menyentuh file tersebut.
- [ ] Impor `../support/fake_media_repository.dart` di `media_flow_test`, `media_controller_test`, dan `media_dock_test` masih di blok package. Pindahkan ke blok relatif.
- [ ] Jeda 50 ms di helper `untilReplied` (`media_http_flow_test.dart`) berpotensi flaky. Ganti dengan sinyal dari sisi klien bila muncul.

## M3 Volume

Belum ada temuan.

## M4 Daya

Belum ada temuan.

## M5 Pengaturan & Tema

Belum ada temuan.

## M6 Ketahanan & Startup

Belum ada temuan.

## Stretch

Hanya dikerjakan kalau pemilik menyebutnya.

- [ ] mDNS discovery agar IP berubah tidak perlu pairing ulang
