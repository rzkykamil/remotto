# Decision Log — Remotto

Keputusan dicatat per gate atau fase, tanpa tanggal.

## [Gate 1] Monorepo agent + app

- **Konteks:** Remotto terdiri dari agent Go dan app Flutter yang berbagi kontrak API.
- **Keputusan:** Satu repo dengan folder `agent/` dan `app/`.
- **Alasan:** Perubahan kontrak bisa masuk dalam satu commit, bersama `docs/` dan `postman/`. Dua repo ditolak karena menambah sinkronisasi tanpa manfaat bagi satu pemilik.
- **Dampak:** CI harus memisahkan job per bagian, dengan runner berbeda.

## [Gate 1] Agent native di sesi user, bukan Windows Service

- **Konteks:** Agent harus mengirim media key dan menjalankan perintah daya.
- **Keputusan:** Agent berupa satu binary yang dijalankan Task Scheduler "At log on" di sesi user.
- **Alasan:** Service jalan di session 0 dan tidak bisa mengirim input ke sesi user. Docker dan server tidak relevan untuk integrasi OS.
- **Dampak:** Agent hanya hidup selama user login. Sebelum login, app menampilkan offline.

## [Gate 1] Media key global, bukan kontrol per aplikasi

- **Konteks:** Pemilik memakai Brave dan Spotify.
- **Keputusan:** Play/pause, next, prev memakai media key virtual.
- **Alasan:** Sederhana dan bekerja untuk semua aplikasi media. Kontrol per aplikasi lewat API sesi media ditolak karena di luar scope.
- **Dampak:** Yang kena adalah sesi media aktif Windows, dan agent tidak tahu status putar sebenarnya. Ikon play di app hanya perkiraan.

## [Gate 1] Polling status, sementara

- **Konteks:** App perlu mengetahui koneksi, volume, dan jadwal daya.
- **Keputusan:** Sementara memakai polling `GET /status` setiap 5 detik; final di Gate 2.
- **Alasan:** Polling lebih sederhana dan sekaligus menjadi deteksi offline. WebSocket masih opsi stretch.
- **Dampak:** Perubahan dari laptop terlihat di app dengan jeda sampai 5 detik.

## [Gate 1] Tanpa database

- **Konteks:** Data hanya config, token, log, dan preferensi.
- **Keputusan:** Agent memakai file JSON + log; app memakai secure storage + preferences.
- **Alasan:** Tidak ada relasi, riwayat, maupun query. SQLite ditolak karena menambah dependency tanpa manfaat.
- **Dampak:** Migrasi cukup lewat `configVersion`.

## [Gate 1] Token disimpan apa adanya dengan izin file ketat

- **Konteks:** Brief membuka opsi menyimpan token atau hash-nya.
- **Keputusan:** Token disimpan apa adanya di `config.json`, dengan DACL khusus user pemilik.
- **Alasan:** `pair` harus bisa menampilkan QR yang sama untuk HP kedua. Hash ditolak karena setiap pairing akan membatalkan pairing lain, padahal pembaca file sudah berada di akun yang mengendalikan laptop. DPAPI ditolak untuk versi ini karena menambah kerumitan tanpa mengubah model ancaman itu.
- **Dampak:** Izin file menjadi pelindung utama dan diperiksa saat start.

## [Gate 1] Reset token berlaku lewat cek waktu modifikasi config

- **Konteks:** `reset-token` adalah proses terpisah, sementara BR-10 meminta token lama mati seketika.
- **Keputusan:** Middleware auth memeriksa waktu modifikasi `config.json` di setiap request.
- **Alasan:** Sederhana dan seketika. IPC ditolak karena menambah kanal kontrol lokal, dan restart manual melanggar BR-10.
- **Dampak:** Ada satu stat file per request, dan biayanya kecil dibanding target 100 ms.

## [Gate 1] Format QR memakai JSON

- **Konteks:** Desain mengasumsikan `remotto://…`, brief memberi contoh JSON.
- **Keputusan:** JSON dengan field `v`, `name`, `host`, `port`, `token`, dan token 64 karakter hex.
- **Alasan:** Punya versi eksplisit dan mudah divalidasi. Skema URI ditolak karena bisa memicu aplikasi lain saat dipindai dengan kamera biasa. Hex dipilih dibanding base64 karena lebih aman saat diketik manual.
- **Dampak:** Asumsi di `design/scope-and-flows.md` tidak lagi berlaku.

## [Gate 1] App menolak alamat di luar rentang privat dan Tailscale

- **Konteks:** Token dikirim lewat HTTP tanpa enkripsi, dan agent tidak boleh dipakai lewat internet publik.
- **Keputusan:** Validasi host di app hanya menerima rentang privat IPv4 dan `100.64.0.0/10`.
- **Alasan:** Mencegah pairing tidak sengaja ke alamat publik yang akan mengirim token di internet.
- **Dampak:** Hostname dan IPv6 tidak didukung di input pairing.

## [Gate 1] Jadwal daya hanya di memori

- **Konteks:** Jadwal daya bisa hilang saat agent restart.
- **Keputusan:** Jadwal tidak dipersistenkan. Selama perintah OS dieksekusi, jadwal tetap terlihat di `/status` dengan sisa 0, lalu dibersihkan saat pemanggilan OS kembali.
- **Alasan:** Arah gagal yang aman adalah laptop tetap nyala. Jadwal persisten ditolak karena bisa mengeksekusi perintah daya tanpa diminta setelah restart.
- **Dampak:** App harus menangani jadwal yang hilang di tengah hitung mundur. Cancel saat eksekusi ditolak 409, sesuai P14.

## [Gate 1] Lokasi config dan log

- **Konteks:** Brief menyerahkan path final ke tahap data design.
- **Keputusan:** Config di `%APPDATA%\Remotto\config.json`, log di `%APPDATA%\Remotto\logs\`.
- **Alasan:** Folder per user tidak butuh hak admin, dan satu folder memudahkan diagnosis.
- **Dampak:** Config bersifat per user Windows.

## [Gate 1] Restart masuk scope

- **Konteks:** Desain memuat restart (SCR-012, P06), brief M4 hanya menyebut sleep dan shutdown.
- **Keputusan:** Restart masuk scope dengan perlakuan sama seperti shutdown.
- **Alasan:** Keputusan pemilik; aturan konfirmasi dan jeda bisa dipakai ulang.
- **Dampak:** Tambah `POST /power/restart` di Gate 2 dan integrasi OS untuk restart.

## [Gate 1] Arah visual Warm Liquid Glass

- **Konteks:** Brief menghindari glassmorphism berlebihan dan glow, sedangkan desain memakai kaca dan cahaya latar.
- **Keputusan:** Ikuti desain, dengan fallback solid wajib.
- **Alasan:** Keputusan pemilik; kontras sudah dihitung di `design/review.md`.
- **Dampak:** Performa `BackdropFilter` dan sinyal reduce transparency harus ditangani di Gate 2.

## [Gate 1] Volume naik/turun dan mute lewat Core Audio

- **Konteks:** Desain meminta langkah 5 poin, sedangkan media key Windows punya langkah sendiri dan tidak mengembalikan nilai baru.
- **Keputusan:** Naik/turun dan mute memakai Core Audio. `VK_VOLUME_*` tidak dipakai; media key hanya untuk M2.
- **Alasan:** Nilai akurat dan respons bisa berisi level terbaru. Media key ditolak karena tidak bisa memenuhi BR-16.
- **Dampak:** Menyimpang dari brief M3. Semua fitur volume bergantung pada pekerja COM audio.

## [Gate 1] Lisensi keluar dari scope UI

- **Konteks:** Lisensi tertulis di scope Pengaturan dan tampil di artboard SCR-020, tapi tidak punya layar.
- **Keputusan:** Baris "Lisensi open source" tidak diimplementasikan.
- **Alasan:** Keputusan pemilik; halaman lisensi bawaan akan terlihat default Material.
- **Dampak:** File lisensi font tetap ikut dibundel sebagai aset untuk memenuhi OFL.

## [Gate 1] Pemulihan saat app dibuka di tengah perintah daya

- **Konteks:** Jeda 5 detik dipegang agent, sehingga hitung mundur tetap jalan walau app ditutup.
- **Keputusan:** Desain direvisi dengan P13 (lanjut hitung mundur), P14 (terlambat batal), P15 (laptop sudah mati). `/status` membawa `pending`, app menyimpan `lastPowerCommand`.
- **Alasan:** Menawarkan Batal yang sudah tidak bisa berhasil lebih berbahaya daripada tidak menampilkannya. Sisa waktu memakai `remainingMs` karena jam dua perangkat bisa berbeda.
- **Dampak:** Notifikasi lokal saat background tetap di luar scope. Teks "dari HP ini" hanya tampil bila `lastPowerCommand` ada, karena agent tidak membedakan HP.

## [Gate 1] Acuan visual dari sumber artboard

- **Konteks:** PNG per screen belum diekspor, padahal tim pengembangan butuh acuan.
- **Keputusan:** Sumber artboard disalin ke `design/export/artboards/`.
- **Alasan:** Nilai dan copy bisa dibaca persis tanpa ekspor manual. PNG ditolak sebagai syarat karena butuh puluhan langkah manual.
- **Dampak:** Artboard tidak bisa dipratinjau tanpa runtime canvas. Perbandingan visual tetap dicek di HP. Kalau desain berubah, salinan harus diperbarui.

## [Gate 2] Polling status final

- **Konteks:** Keputusan sementara dari Gate 1.
- **Keputusan:** Polling `GET /status`. `GET /ws` tidak dibuat.
- **Alasan:** Polling sekaligus deteksi offline, dan hitung mundur cukup memakai `remainingMs`. WebSocket ditolak karena menambah manajemen sambungan tanpa manfaat nyata.
- **Dampak:** Perubahan dari laptop terlihat dengan jeda sampai 5 detik. WebSocket tetap di backlog.

## [Gate 2] Riverpod, http, go_router

- **Konteks:** Brief meminta rekomendasi state management dan klien HTTP.
- **Keputusan:** `flutter_riverpod` tanpa codegen, `http`, dan `go_router`. Ditambah `permission_handler`, `wakelock_plus`, dan `package_info_plus`.
- **Alasan:** Override provider memudahkan peralihan mock ke HTTP. `dio` ditolak karena fiturnya tidak terpakai. Semua package non-visual, sesuai §11.
- **Dampak:** Dart minimal mengikuti Riverpod dan go_router versi terbaru.

## [Gate 2] Bind 0.0.0.0 dengan filter jaringan

- **Konteks:** Agent harus terjangkau dari LAN dan Tailscale, sementara IP bisa berubah.
- **Keputusan:** Bind `0.0.0.0`, ditambah firewall profil Private dan middleware yang menolak IP sumber di luar rentang privat dengan 403.
- **Alasan:** Bind ke satu IP rusak saat DHCP berubah. Filter menjadi pertahanan kedua kalau firewall salah konfigurasi.
- **Dampak:** Kode status 403 ditambahkan ke kontrak.

## [Gate 2] Sleep memilih jalur saat runtime

- **Konteks:** `powercfg /a` menunjukkan laptop pengembangan hanya punya S0 Low Power Idle, tanpa S3. Brief mengasumsikan `SetSuspendState`.
- **Keputusan:** Laptop S0 memakai `SC_MONITORPOWER` untuk masuk Modern Standby. Laptop S3 memakai `SetSuspendState`. Pilihan lewat `GetPwrCapabilities`.
- **Alasan:** `SetSuspendState` di perangkat S0 bisa menjadi hibernate atau gagal. `powercfg -h off` ditolak sebagai solusi umum karena ikut mematikan Fast Startup.
- **Dampak:** Sleep di laptop S0 tidak seketika dan lagu bisa tetap jalan. Harus dicek manual.

## [Gate 2] Shutdown tanpa paksa

- **Konteks:** `shutdown` dengan `/f` menutup aplikasi tanpa peringatan.
- **Keputusan:** `shutdown /s /t 0` dan `shutdown /r /t 0` tanpa `/f`. Batal cukup menghentikan timer agent, jadi `shutdown /a` tidak dipakai.
- **Alasan:** Melindungi pekerjaan yang belum tersimpan.
- **Dampak:** Windows bisa berhenti di layar "app menghalangi shutdown".

## [Gate 2] Mute eksplisit dan perubahan level mematikan mute

- **Konteks:** Brief membuka pilihan toggle atau body eksplisit.
- **Keputusan:** `POST /volume/mute` wajib body `{ "muted": bool }`. `PUT`, naik, dan turun selalu mematikan mute.
- **Alasan:** Eksplisit membuat retry aman dan dua HP tidak saling membalik. Toggle ditolak karena retry akan membatalkan dirinya sendiri.
- **Dampak:** App harus tahu status mute terakhir, yang sudah tersedia dari polling.

## [Gate 2] Uptime memakai umur proses agent

- **Konteks:** "Nyala sejak" di Pengaturan dan pill di Remote membutuhkan angka yang masuk akal.
- **Keputusan:** `uptimeSeconds` adalah lama proses agent berjalan.
- **Alasan:** Fast Startup membuat uptime sistem tidak ter-reset saat laptop dimatikan.
- **Dampak:** Angka ter-reset saat agent di-restart atau diperbarui.

## [Gate 2] Timeout penjadwalan daya tidak menampilkan P10

- **Konteks:** P10 menyatakan "Laptop masih nyala", padahal timeout bisa terjadi setelah perintah sampai ke agent.
- **Keputusan:** Timeout memicu pembacaan `/status`. Kalau tetap ambigu, app menampilkan P11, bukan P10.
- **Alasan:** Pesan palsu bahwa laptop aman lebih berbahaya daripada peringatan yang berlebihan.
- **Dampak:** Tidak butuh layar baru. Perilaku ini memperluas pemakaian P11 di luar kasus aslinya.

## [Gate 2] Konsol dilepas saat startup

- **Konteks:** Binary konsol memunculkan jendela saat login, sedangkan `pair` butuh terminal.
- **Keputusan:** Tetap binary konsol; `run --background` memanggil `FreeConsole`.
- **Alasan:** Build `-H=windowsgui` ditolak karena merusak output `pair`. Dua binary ditolak karena brief meminta satu binary.
- **Dampak:** Jendela bisa berkedip sekali saat login.

## [Gate 2] Pemetaan token lewat generator

- **Konteks:** Nilai token harus sama dengan `design/tokens.json` tanpa disalin manual.
- **Keputusan:** `app/tool/generate_tokens.dart` menghasilkan `tokens.g.dart` yang ikut di-commit. Warna standar ke `ColorScheme`, sisanya ke `ThemeExtension`.
- **Alasan:** Mencegah token menyimpang. Package generator ditolak karena skemanya sederhana.
- **Dampak:** Perubahan token butuh menjalankan generator.

## [Gate 2] Fallback solid tanpa sinyal Flutter

- **Konteks:** `AccessibilityFeatures` di Flutter 3.47 tidak punya reduce transparency.
- **Keputusan:** `GlassMode` memakai high contrast, platform channel iOS, dan pemantauan waktu raster.
- **Alasan:** Desain mewajibkan fallback. Toggle di Pengaturan ditolak karena tidak ada di desain.
- **Dampak:** Ada sedikit kode native iOS. Android hanya memicu lewat high contrast dan performa.

## [Gate 3] Ekspor logo tidak masuk repo

- **Konteks:** Seluruh PNG dan SVG di `design/export/logo/` membawa metadata asal-usul alat pembuatnya.
- **Keputusan:** Folder tersebut tetap ada di disk, tapi diabaikan `.gitignore`. Ikon app dirender dari SVG inline di `design/export/artboards/Logo.dc.html`.
- **Alasan:** Artboard memuat bentuk logo yang sama tanpa metadata tersebut. Menghapus metadata dari file ekspor ditolak karena mengubah catatan asal-usul file.
- **Dampak:** Clone baru tidak punya folder ekspor logo. Render ikon menjadi task M0.

## [Gate 3] Penyesuaian ci.yml

- **Konteks:** Template CI menulis artefak ke `dist/`, dan repo dikembangkan di Windows.
- **Keputusan:** Langkah build agent membuat `dist/` lebih dulu, dan `.gitattributes` memakai `eol=lf`.
- **Alasan:** Build butuh folder tujuan yang pasti ada. CRLF di runner Windows membuat cek `gofmt` gagal.
- **Dampak:** Tidak ada secret atau langkah CGO tambahan.

## [Frontend M0] Identitas app dan izin dasar

- **Konteks:** `flutter create` butuh org dan nama app. App dipakai di HP pribadi lewat LAN dan punya layar pairing yang memakai kamera.
- **Keputusan:** App ID `com.remotto.remotto` (org `com.remotto`). Izin INTERNET dan CAMERA di Android, network security config, dan key privasi iOS (`NSCameraUsageDescription`, `NSLocalNetworkUsageDescription`, `NSAllowsLocalNetworking`) dikerjakan di M0. `allowBackup=false`.
- **Alasan:** Izin dan konfigurasi platform harus ada sejak awal supaya M1 tidak mengubahnya lagi. Backup dimatikan agar data pairing (token) tidak ikut ter-backup oleh OS. Agent memakai HTTP di LAN, jadi cleartext diizinkan di network security config; pembatasan ke alamat LAN dilakukan validasi app (BR-12).
- **Dampak:** Konfigurasi iOS belum bisa diverifikasi di Windows; ada di `docs/todo/waiting.md`.

## [Frontend M0] Dependensi dan UI kit

- **Konteks:** `pubspec.yaml` harus bebas UI kit (technical-spec §11). Template Flutter membawa `cupertino_icons`.
- **Keputusan:** `cupertino_icons` dihapus. Library Material dan Cupertino yang ikut sebagai dependensi transitif dari framework Flutter 3.47 diterima; bukan UI kit yang dipasang langsung. `minSdk` memakai default Flutter (24).
- **Alasan:** Ikon digambar sendiri, jadi `cupertino_icons` tidak dipakai. Library transitif tidak bisa dihindari tanpa mengganti framework.
- **Dampak:** Pemeriksaan DoD cukup melihat `pubspec.yaml` dan import langsung, bukan dependensi transitif.

## [Frontend M0] Penamaan hasil generator token

- **Konteks:** Kelas warna hasil generator dan `ThemeExtension` memakai nama dasar yang sama (`Bg`, `Glass`), sehingga bentrok.
- **Keputusan:** Kelas warna hasil generator berakhiran `Set` (`BgSet`, `GlassSet`, dan seterusnya). Path sumber `../../design/tokens.json` relatif dari `app/tool/`. Generator menjalankan `dart format` lewat `Platform.resolvedExecutable`. Konstanta `RBehavior` ditulis tangan, tidak dihasilkan generator.
- **Alasan:** Akhiran `Set` membedakan data token dari `ThemeExtension` `*Tokens`. `Platform.resolvedExecutable` tidak bergantung pada `dart` di PATH. `RBehavior` tidak punya padanan di `tokens.json`.
- **Dampak:** Perubahan token tetap butuh menjalankan generator; nama di atas harus dipakai saat menambah kode.

## [Frontend M0] Ikon app dari SVG inline

- **Konteks:** Ikon app ada sebagai SVG inline di `design/export/artboards/Logo.dc.html`. Folder `design/export/logo/` tidak masuk repo (Gate 3).
- **Keputusan:** Ikon dirender dari SVG inline lewat Edge headless (`app/tool/render_icons.ps1`) menjadi PNG. Hanya ikon gelap yang dipasang di launcher; ikon terang diarsipkan di `app/assets/icon/`. Adaptive icon ditunda.
- **Alasan:** Sumber yang sama dengan artboard tanpa metadata asal-usul alat. Launcher default gelap (design-system §9), jadi ikon terang tidak perlu dipasang. Adaptive icon butuh pemeriksaan visual di HP dulu.
- **Dampak:** Ikon launcher perlu dicek di HP (`docs/todo/waiting.md`); adaptive icon ada di `docs/todo/backlog/frontend.md`.

## [Frontend M0] Font Geist

- **Konteks:** File Geist tidak ada di disk. App butuh bobot sans dan mono sesuai tipografi desain.
- **Keputusan:** Geist v1.9.2 TTF statis (SIL OFL 1.1) dari rilis resmi `vercel/geist-font`. Lisensi di `app/assets/fonts/OFL-Geist.txt`.
- **Alasan:** Rilis resmi dengan TTF statis memberi bobot yang pasti, tanpa bergantung pada variable font. Font tidak diunduh saat runtime dan tidak memakai `google_fonts`.
- **Dampak:** Bobot yang benar-benar terlihat dicek di HP (`docs/todo/waiting.md`).

## [Frontend M0] Podfile iOS tidak dibuat di M0

- **Konteks:** `Podfile` dihasilkan `flutter build ios` di macOS. Repo ini dikembangkan di Windows.
- **Keputusan:** Podfile tidak dibuat di M0. Macro `PERMISSION_CAMERA=1` ditambahkan di Mac setelah `flutter build ios`.
- **Alasan:** Podfile hasil tulis tangan di Windows bisa salah dan tidak bisa diuji.
- **Dampak:** Build iOS belum terbukti sampai ada Mac; ada di `docs/todo/waiting.md`.

## [Frontend M0] Tombol kaca dan ukuran

- **Konteks:** `design/components.md` C02 menyebut ukuran 48, 52, 56, 64, dan 80, tapi token hanya punya `touch`, `power`, `control`, dan `media`.
- **Keputusan:** `GlassKey` tanpa ukuran 64 dp. Empat ukuran: touch 48, power 52, control 56, media 80. Tombol `strong` yang disabled memakai `fg.disabled`. Tint tekan memakai `glass.chipPressed` di semua varian. Ukuran ikon tidak diatur `GlassKey`.
- **Alasan:** Tidak ada token 64, dan menulis angka sendiri melanggar aturan token. Ukuran ikon ditentukan pemanggil karena ikon belum ada di M0.
- **Dampak:** Ukuran ikon dan kebutuhan 64 dp dicek saat M1 (`docs/todo/backlog/frontend.md`).

## [Frontend M0] GlassPanel: blur tanpa saturasi

- **Konteks:** Desain memakai `blur(28px) saturate(170%)`. Rencana awal memakai `ImageFilter.compose` dengan color matrix untuk saturasi.
- **Keputusan:** `GlassPanel` hanya memakai blur. Saturasi (token 1.7) tidak diterapkan. Mode solid memakai `glass.solid` untuk semua varian termasuk toast, tanpa bayangan blur. Bayangan luar 0/12 blur 32 dari artboard disimpan sebagai konstanta privat. Test memakai `glassForcedSolidProvider`.
- **Alasan:** API `ImageFilter` Flutter 3.47 tidak mendukung color matrix pada backdrop (diverifikasi Reviewer).
- **Dampak:** Warna kaca bisa sedikit berbeda dari artboard; tercatat di `docs/todo/backlog/frontend.md`.

## [Frontend M0] Transisi layar dan router

- **Konteks:** `design-system.md` §6 menyebut geser 24 dp + fade untuk transisi layar, tanpa menyebut arah. `design/scope-and-flows.md` mengatur tombol back.
- **Keputusan:** Transisi geser vertikal naik 24 dp + fade. Reduced motion tanpa geser, durasi `fast`. Router: `/` redirect ke `/remote` atau `/pairing` sesuai data pairing; `/remote` jadi akar stack; `/settings` dibuka lewat push.
- **Alasan:** Arah geser tidak ada di dokumen, jadi diambil dari keputusan developer. Akar `/remote` membuat back sistem keluar app, dan Pengaturan kembali ke Remote.
- **Dampak:** Arah transisi ditinjau lagi di M2 saat ada layar nyata. Transisi dan back di HP ada di `docs/todo/waiting.md`.

## [Frontend M0] Storage dan perilaku haptic

- **Konteks:** `data-design.md` §6 mengatur perilaku saat data hilang atau rusak.
- **Keputusan:** `read()` menganggap host atau token kosong, atau port di luar 1–65535, sebagai data hilang (`null`). Setter haptic memakai parameter bernama `enabled`. Harness test ada di `app/test/support/`, bukan `test/helpers`.
- **Alasan:** Data rusak tidak boleh membuat app crash atau memakai port yang salah. Nama parameter eksplisit mencegah tertukar dengan nilai lain.
- **Dampak:** Konsumen storage tidak perlu menangani nilai rusak sendiri.

## [Frontend M0] Test guard aturan UI

- **Konteks:** Aturan UI (rule frontend-ui, lokal) dan DoD melarang pola Material default, UI kit, dan nilai hardcode. Aturan yang hanya ada di dokumen mudah terlewat.
- **Keputusan:** `app/test/guards/ui_rules_test.dart` melarang pola Material default, UI kit, `Color(0x`, dan literal `EdgeInsets` di `lib/features/`.
- **Alasan:** Test berjalan lewat `flutter test` dan CI, jadi pelanggaran tertangkap otomatis.
- **Dampak:** Kode fitur yang memakai literal akan gagal test dan harus memakai token.
