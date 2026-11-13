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
- [x] `pairing_repository.dart` baris 4 dan `status_repository.dart` baris 3 masih menyebut "Mock". Di luar lingkup M2; ganti di fase yang menyentuh file tersebut. Diselesaikan di Integrasi M4 (komentar dikoreksi).
- [ ] Impor `../support/fake_media_repository.dart` di `media_flow_test`, `media_controller_test`, dan `media_dock_test` masih di blok package. Pindahkan ke blok relatif.
- [ ] Jeda 50 ms di helper `untilReplied` (`media_http_flow_test.dart`) berpotensi flaky. Ganti dengan sinyal dari sisi klien bila muncul.

## M3 Volume

- [ ] Tes volume hanya menguji server palsu di `test/integration/`, bukan agent Go asli. Pembuktian dengan agent asli ada di `waiting.md` M3 Integrasi.
- [ ] `Future.timeout` pada `putVolume` dan `postVolumeStep` tidak membatalkan request; up/down yang terlambat bisa tetap menaikkan volume setelah UI di-rollback. Dampak kecil. Sama dengan item M1 dan M2 di atas (`lib/core/network/agent_http_client.dart`).
- [x] `VolumeSender` retry juga untuk 400 dan 429, dan tidak menghormati `Retry-After`. Diselesaikan di Frontend M6: hanya timeout dan unreachable yang di-retry (`lib/features/remote/state/volume_sender.dart`). `Retry-After` masih tercatat di bagian M6.

## M4 Daya

- [ ] Tes daya hanya menguji server palsu di `test/integration/`, bukan agent Go asli. Pembuktian dengan agent asli ada di `waiting.md` M4 (Integrasi).
- [ ] `Future.timeout` pada schedule dan cancel tidak membatalkan request. Jadwal bisa tetap tercatat setelah timeout; aman karena controller membaca `/status` (`lib/features/remote/data/http_power_repository.dart`).
- [ ] `UnreachableFailure` belum membedakan gagal connect dari putus di tengah request. Untuk daya, putus di tengah request tampil P10 padahal mungkin sudah terjadwal. Pengaman: polling `/status` berikutnya memunculkan P13 atau P11 lewat `resumeFromStatus`. Juga tercatat di `backlog/frontend.md` M4.
- [ ] S02 maks 2 detik saat app dibuka dengan jadwal berjalan ditunda ke M6 (butuh alur startup). Juga tercatat di `backlog/frontend.md` M4.
- [ ] 403 dan 429 pada schedule tampil sebagai P10 tanpa copy khusus. Perlu keputusan copy dari desain, sama dengan item M1.
- [ ] Skenario timeout 100 ms memakai `server.hold` (test daya). Di mesin yang sangat lambat bisa menghasilkan P11, bukan P10. Belum pernah terlihat.
- [ ] `/status` dengan action tak dikenal kini menggagalkan seluruh parse. Ini perilaku sengaja (`[Integrasi M4] Pending.fromData memvalidasi action`); catat bila agent nanti menambah action.

## M5 Pengaturan & Tema

Belum ada temuan.

## M6 Ketahanan & Startup

- [x] Test `app/test/integration/volume_http_flow_test.dart` baris 179 memakai `failNextVolumeRequests = 2` padahal hanya satu request dikonsumsi. Sudah diubah ke 1; hasil tidak berubah (SARAN reviewer M6).
- [ ] Test `app/test/integration/volume_http_flow_test.dart` baris 301 tetap `failNextVolumeRequests = 2`. Tes mute gagal dua kali memang butuh dua kegagalan, jadi nilai 2 benar. SARAN reviewer M6 untuk baris ini tidak diterapkan.
- [ ] `Retry-After` pada 429 belum dihormati. Perlu desain copy untuk pesan tunggu (`lib/features/remote/state/volume_sender.dart`). SARAN reviewer M6.
- [ ] `Retry-After` dari 429 juga belum dipakai di `PowerFlowController` dan `ConnectionController`. Perlu desain copy yang sama dengan item di atas.
- [ ] Request yang kena `Future.timeout` belum dibatalkan, jadi perintah yang terlambat tetap bisa sampai ke agent. Sama dengan item M3 di atas (`lib/core/network/agent_http_client.dart`). SARAN reviewer M6.
- [ ] Mute dan retry 429: `volume_http_flow_test.dart` (sekitar 346–356, "429 pada mute: dua request") masih retry otomatis untuk mute pada 429. Bertentangan dengan keputusan 429 tidak di-retry. Perlu keputusan: ubah perilaku atau perbarui keputusan.
- [ ] Koneksi: kegagalan kedua saat server mati memakan sekitar 2 detik (`connection_resume_http_test.dart` tes C), bukan "connect cepat" seperti spec. Perlu diselidiki (dugaan: koneksi keep-alive).
- [ ] `POST /power/schedule` tidak ada di `docs/api-spec.md`; tes memakai `/power/shutdown`. Perlu klarifikasi spec.

## M7 Auto-Discovery Jaringan

- [ ] Peringatan build: plugin nsd_android masih memakai Kotlin Gradle Plugin; Flutter mendatang akan gagal build bila belum dimigrasi ke built-in Kotlin. Pantau pembaruan nsd (T2 M7).
- [ ] `endpoint_resolver.dart` jalur 401 ke `tokenRejected` belum meng-guard re-read pairing: user re-pair saat discovery berjalan bisa salah masuk tokenRejected. SARAN reviewer M7.
- [ ] `connection_controller.dart` `_onRediscovered` cabang tokenRejected belum memeriksa `_running`. SARAN reviewer M7.
- [ ] `storage_providers.dart` `updateEndpoint` dan `backfillAgentId` memakai read-await-write; reset atau re-pair yang masuk saat await bisa tertimpa. SARAN reviewer M7.

## Stretch

Hanya dikerjakan kalau pemilik menyebutnya.

- [x] mDNS discovery agar IP berubah tidak perlu pairing ulang (dikerjakan di M7)
