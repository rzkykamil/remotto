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

## [Backend M0] Go 1.27.3 dan module path

- **Konteks:** Spec menetapkan Go 1.27. Repo belum punya `go.mod`, dan module path tidak ditentukan dokumen.
- **Keputusan:** `agent/go.mod` memakai `go 1.27.3` tanpa baris `toolchain`. Module path `remotto/agent`. Hanya stdlib di M0. Toolchain 1.27.3 diunduh otomatis lewat `GOTOOLCHAIN=auto` dan terverifikasi; fallback ke Go 1.25.5 tidak dipakai.
- **Alasan:** Sesuai spec tanpa menurunkan versi. Module path tidak mengikat owner repo dan modul ini tidak di-`go get` orang lain. Tanpa dependency, M0 tidak butuh pihak ketiga.
- **Dampak:** Mengganti module path cukup dengan `go mod edit` dan penyesuaian impor. Dependency pertama masuk di M1 (`qrterminal`) dan M2 (`x/sys`).

## [Backend M0] Bentuk interface control dan error domain

- **Konteks:** `docs/technical-spec.md` bagian 7 meminta port OS tipis. Clamp, langkah volume, unmute, dan delay daya adalah aturan bisnis.
- **Keputusan:** `MediaController.Send(ctx, action)`, `AudioController` dengan `Volume`, `SetLevel`, `SetMuted`, dan `PowerController.Execute(ctx, action)`. Clamp, langkah, unmute, dan delay berada di domain M2 sampai M4. Error domain: sentinel `ErrUnsupported`, `ErrMedia`, `ErrAudio`, `ErrPower`. `control.Wrap` menyembunyikan cause dari `Error()`, tetapi `errors.Is` dan `errors.Unwrap` tetap bekerja.
- **Alasan:** Logika bisnis dites dengan fake tanpa OS. Pesan error yang dikirim ke klien tidak membawa detail OS (COM, HRESULT), sementara detail tetap ada untuk log.
- **Dampak:** Tanda tangan bisa disempurnakan di fase modulnya karena belum ada pemakai. Handler M2 sampai M4 memetakan sentinel ke kode `media_failed`, `audio_failed`, dan `power_failed`.

## [Backend M0] Fake OS

- **Konteks:** Domain harus dites tanpa efek OS nyata. Test tidak boleh menyentuh media, volume, atau daya laptop.
- **Keputusan:** Paket `internal/oscontrol/fake` punya tipe `Media`, `Audio`, dan `Power`, masing-masing aman konkurensi. Field error tidak diekspor dan diset lewat `SetErr`. Setiap panggilan dicatat, termasuk yang gagal. `Power` hanya mencatat dan tidak menjalankan apa pun.
- **Alasan:** Field error yang tidak diekspor mencegah test mengubah state tanpa lewat API. Pencatatan panggilan membuat urutan aksi bisa diassert.
- **Dampak:** Semua test domain M2 sampai M4 memakai fake ini. Tidak ada test yang menjalankan efek OS.

## [Backend M0] Logging

- **Konteks:** `docs/data-design.md` bagian 4 meminta log JSON ke file dan konsol, tanpa token atau header sensitif.
- **Keputusan:** Satu `slog.NewJSONHandler` dengan `io.MultiWriter` ke file dan konsol. `ReplaceAttr` mengganti nilai atribut `token`, `authorization`, dan `password` (tanpa membedakan huruf besar) menjadi `[redacted]`. Tanpa rotasi sampai M6.
- **Alasan:** Satu handler menjaga format sama di file dan konsol. Penyaring di handler adalah jaring pengaman; pencegahan utama tetap tidak mencatat secret di kode pemanggil.
- **Dampak:** Penyaring hanya berlaku untuk atribut bernama tersebut. Atribut bernama lain yang berisi secret tidak tertangkap, jadi pemanggil tetap bertanggung jawab.

## [Backend M0] Config: validasi dan tulis atomik

- **Konteks:** `docs/data-design.md` bagian 3 mengatur field, default, dan rentang. Token belum dibuat sebelum first run (M1).
- **Keputusan:** Token kosong diizinkan di M0. Token yang tidak kosong harus 64 hex huruf kecil. `configVersion` selain 1 ditolak dengan pesan yang menyebut field, tanpa menyentuh file. Tulis atomik lewat file temp lalu `Rename`. `run` tanpa `config.json` memakai default di memori dan tidak menulis file.
- **Alasan:** Token kosong adalah kondisi sebelum first run, dan middleware auth M1 wajib menolak semua request saat token kosong. Migrasi dan `.corrupt` ditunda ke M1 agar M0 tidak menulis config.
- **Dampak:** M1 harus menolak request saat token kosong (acceptance di task auth). Dengan `config.json` belum ada, agent tidak menulis apa pun di `%APPDATA%`.

## [Backend M0] Router, middleware, dan timeout server

- **Konteks:** `docs/api-spec.md` meminta envelope error untuk setiap respons, termasuk 404 dan 405. `http.ServeMux` tidak memakai envelope dan perilakunya berubah antar versi Go.
- **Keputusan:** Router buatan sendiri dengan pencocokan path persis. 404 `not_found`, 405 `method_not_allowed` dengan `Allow` terurut. Body maksimal 1 KiB dan field tak dikenal ditolak. Urutan middleware: Recover, lalu Logging, lalu router. Bila header sudah ditulis sebelum panic, log mencatat status yang sudah terkirim. Timeout 2s, 3s, 5s, 60s, header 8 KiB, shutdown 3 detik.
- **Alasan:** Router sendiri memberi bentuk error yang konsisten. Urutan Recover di luar menjamin panic tetap berubah jadi 500 envelope dan tercatat.
- **Dampak:** Route baru didaftarkan lewat `Handle`, dan pendaftaran ganda panic. Filter jaringan, rate limit, dan auth M1 masuk di antara Logging dan router.

## [Backend M0] Perilaku subcommand dan run

- **Konteks:** `run` membuka port dan menulis log. Subcommand `pair`, `reset-token`, `install-startup`, dan `uninstall-startup` belum ada.
- **Keputusan:** `run` menolak argumen posisi dengan exit 2. `run -h` exit 0. Error `Serve` dicatat ke log dan dicetak ke stderr. `--config` ada untuk dev dan test. `--background` diterima tanpa efek sampai M6. Subcommand yang belum ada keluar dengan exit 1 dan pesan "belum tersedia".
- **Alasan:** Exit code yang jelas membuat Task Scheduler dan skrip bisa membedakan salah pakai dari kegagalan. Flag `--background` diterima sejak awal supaya M6 tidak mengubah perintah startup.
- **Dampak:** Opsi `--config` belum tercantum di `docs/`. Dokumentasi menyusul di `docs/technical-spec.md` bagian 3 atau `docs/release.md`.

## [Backend M0] go.sum kosong dan postman tidak berubah

- **Konteks:** M0 tidak punya dependency, sehingga `go mod` tidak membuat `go.sum`. CI `agent-test` memakai `cache-dependency-path: agent/go.sum`. M0 belum punya endpoint.
- **Keputusan:** `agent/go.sum` kosong dibuat agar langkah cache `setup-go` tidak gagal. `postman/` tidak diubah di M0.
- **Alasan:** Langkah cache dicek saat push pertama. File kosong membuat langkah itu aman tanpa mengubah `ci.yml`. Tidak ada endpoint, jadi tidak ada request yang perlu disinkronkan.
- **Dampak:** Hasil job `agent-test` di GitHub Actions dicek lewat `docs/todo/waiting.md`. `postman/` disinkronkan mulai M1 bersama `GET /status`.

## [QA M0] Test kelengkapan token terhadap tokens.json

- **Konteks:** Spot check hanya memeriksa 2 dari 72 nilai warna. Pergeseran nilai di `design/tokens.json` bisa lolos tanpa terdeteksi.
- **Keputusan:** File test terpisah `app/test/core/theme/tokens_completeness_test.dart` membaca JSON dan meniru aturan alias serta alpha generator, tanpa mengimpor generator.
- **Alasan:** Tidak mengubah generator dan tidak membuka API privat.
- **Dampak:** Pergeseran token di JSON memutus build bila `tokens.g.dart` tidak di-generate ulang.

## [Frontend M1] Q12 mempertahankan sambungan lama dan pairing satu rute

- **Konteks:** Catatan artboard menulis "Pairing ulang" menghapus data lama. PRD BR-9 berbeda. Pairing ulang dari OfflineContent (S10) dan Q12 harus punya satu alur.
- **Keputusan:** Sambungan lama dipertahankan sampai pairing baru sukses. Data baru disimpan lewat `pairingProvider.save` hanya setelah `/status` sukses, dengan nama laptop dari respons. "Pairing ulang" langsung ke Q01 tanpa C22 (C22 milik M5). Pairing adalah satu rute `/pairing` dengan langkah internal di `pairingFlowProvider` (non-autoDispose; Pengaturan "Pairing ulang" wajib memanggil `reset()`), dibungkus `PopScope`. Back dari Scan/Manual ke Q01, dari Q08 "Batal" ke layar asal, dari Q10/Q11 ke layar asal tes, dari Q09 tidak berbuat apa-apa, dari Q01 keluar app. Q12 dipasang di `routerProvider` lewat `ref.listen`: `tokenRejected` menampilkan Q12 dan `redirectFor` tidak berubah.
- **Alasan:** PRD menang atas catatan artboard. Pairing yang gagal tidak boleh membuat app kehilangan sambungan yang masih bisa dipakai. Langkah internal menjaga alur linear tanpa rute tambahan.
- **Dampak:** Q12 belum menghapus sambungan lama dan butuh cek di HP (lihat `docs/todo/waiting.md`). Haptic kegagalan ada di Q10 dan Q11.

## [Frontend M1] Validasi QR dan input manual

- **Konteks:** `docs/data-design.md` bagian 5 dan BR-12 mengatur payload QR dan token. Artboard hanya punya satu pesan error alamat.
- **Keputusan:** QR maksimal 256 byte UTF-8, harus objek JSON dengan `v == 1`, `name`, `host` IPv4, `port`, dan `token` 64 hex huruf kecil. Field asing diabaikan, isi QR tidak di-log. Host hanya 10/8, 172.16/12, 192.168/16, 100.64/10. Oktet dengan nol di depan ditolak. Input manual di-trim, port default 8765, token di-trim dan dinormalisasi lowercase. Hasil validator berupa sealed `valid`/`invalid(reason)` tanpa throw. Alasan gagal dipisah `invalidAddress` dan `invalidHost`, tetapi semua alasan alamat memakai satu pesan Q07.
- **Alasan:** Input salah ditolak di app sebelum request. Pesan tunggal mengikuti artboard.
- **Dampak:** Pesan khusus untuk host di luar rentang dan IP publik butuh keputusan copy (backlog dan `docs/todo/waiting.md`).

## [Frontend M1] Mock pairing dan status

- **Konteks:** M1 frontend berjalan tanpa HTTP sungguhan. Semua respons mengikuti envelope `{data}` di `docs/api-spec.md`.
- **Keputusan:** Mock membangun JSON envelope lalu diparse lewat parser yang sama dengan HTTP nanti. Host `10.0.0.1` menghasilkan timeout, token 64 nol menghasilkan 401, selain itu sukses dengan nama "Laptop-Kamil". Mock status bisa diprogram urutan respons dan error. Jeda mock diinjeksi dan bernilai 0 di test. Provider default memakai mock.
- **Alasan:** Parser tunggal mencegah mock dan HTTP nyata berbeda bentuk.
- **Dampak:** Saat backend M1 masuk, provider diganti ke repository HTTP. Tes tidak menyentuh jaringan.

## [Frontend M1] Mesin koneksi

- **Konteks:** `docs/technical-spec.md` bagian 5, BR-8, BR-9, BR-21, FR-1.12.
- **Keputusan:** `ConnectionController` non-autoDispose. `start()` selalu ke connecting, termasuk dari poweredOff. `stop()` di dispose. Satu kegagalan tetap online. Dua kegagalan berturut ke offline. Fase back yang gagal tetap back sampai dua kegagalan berturut. Offline yang sukses ke back lalu online setelah 2 detik. 401 di fase mana pun ke tokenRejected. Timeout poll 3 detik sebagai konstanta privat. Timer lewat interface `PollScheduler`, `pollOnce()` publik, maksimal satu fetch berjalan. `volume: null` mempertahankan nilai terakhir. `LastPowerCommand` dan `lastPowerCommandProvider` (default null) disiapkan untuk M4 dengan `record` dan `clear`.
- **Alasan:** Mesin status bisa dites deterministik tanpa waktu nyata.
- **Dampak:** M4 mengisi `lastPowerCommand`. Timeout poll tidak berubah tanpa mengubah tes.

## [Frontend M1] Uptime, pill status, dan SCR-010

- **Konteks:** Pill artboard menulis `NYAMBUNG · 3J 12M`. Header SCR-010 harus muat di 360 dp dan teks 130%.
- **Keputusan:** Menit dibulatkan ke bawah. Uptime di bawah 1 jam tampil `12M`. Helper `formatUptime` ada di `core/strings/`. Label pill memakai Flexible dan ellipsis. Header memakai Align, bukan FittedBox. `connection.start()` dipanggil lewat post-frame callback karena Riverpod melarang mutasi saat mount. SCR-010 tidak punya kontrol palsu (tombol daya, slider, dock).
- **Alasan:** Riverpod melarang mutasi provider saat widget dimount. Ellipsis mencegah overflow.
- **Dampak:** Format `12M` di bawah 1 jam belum disetujui desain (lihat `docs/todo/waiting.md`).

## [Frontend M1] Toast, kamera, dan input

- **Konteks:** `docs/design-system.md` dan `design/export/artboards/` untuk Q03 sampai Q06 dan toast.
- **Keputusan:** Toast memakai overlay kustom, bukan SnackBar, 12 dp di atas dock. `toastBottomInsetProvider` default 0 dan M2 wajib menimpanya dengan tinggi dock. Banner Q04 memakai GlassToast, durasi 3 detik diatur ScanView. Label Semantics "Kembali" dan "Senter" ditambahkan karena tidak ada di artboard. `mobile_scanner` dan `permission_handler` hanya diimpor di satu wrapper, sisanya lewat interface. Test dan fake boleh mengimpor `mobile_scanner` untuk fake controller. Subtree scan dipaksa tema gelap. `GlassTextField` dibungkus `Material(transparency)` karena Q06 crash tanpa Material ancestor (ditemukan lewat tes alur penuh). Tombol mata token hanya ikon `eye` yang mengubah `obscureText`, tanpa `eye-off`. Izin Android: `permission_handler` tidak mengembalikan permanentlyDenied lewat status, jadi Q01 ke Q02 lalu Q05 setelah request.
- **Alasan:** Satu wrapper membuat plugin mudah diganti dan dites. Material transparan menghindari crash tanpa mengubah tampilan.
- **Dampak:** Izin Android yang permanen dan ikon eye-off masuk backlog.

## [Frontend M1] Token, ikon, dan layout

- **Konteks:** `design/tokens.json`, `docs/design-system.md` dan `design/export/artboards/`.
- **Keputusan:** Token `primitive.size.action` 64dp ditambahkan ke `design/tokens.json` lalu `tokens.g.dart` digenerate ulang. Parser path SVG sendiri di `lib/ui` tanpa `flutter_svg` atau `path_drawing`. Token manual 64 hex memakai placeholder "Tempel token dari laptop" dan pesan error "Tokennya 64 karakter, huruf a–f dan angka" dengan gaya error C17. Komentar file M1 ditulis dalam bahasa Inggris.
- **Alasan:** Parser sendiri menghindari dependensi baru. Token menjaga literal warna dan ukuran tetap di token.
- **Dampak:** Ikon dan ukuran lain yang belum ada token masuk backlog frontend.

## [Backend M1] Token, config lifecycle, dan DACL

- **Konteks:** `docs/technical-spec.md` bagian 8, `docs/data-design.md` bagian 3, BR-10, BR-11.
- **Keputusan:** Token dibuat di `LoadOrInit` lewat fungsi yang disuntikkan, agar tidak ada siklus impor config dan pairing. Auth fail-closed bila token sumber kosong atau tidak valid. Token awal yang tidak valid dianggap kosong lalu diisi ulang. Reload token yang gagal mempertahankan token valid terakhir dan mencatat warn tanpa nilai token. Versi config lebih baru memberi `ErrNewerVersion` dan file tidak disentuh. Versi 0 atau tanpa `configVersion` dianggap perlu migrasi. Pengecekan versi dipindah dari `Validate` ke `Load`/`LoadOrInit`. Salinan `.bak` dibuat sebelum migrasi. DACL Windows hanya mengizinkan SID user proses dengan `FILE_ALL_ACCESS`, dan pencocokan tidak bergantung pada flag PROTECTED. Folder diamankan sebelum tulis atomik pertama. Non-Windows memakai chmod 0700 dan 0600. Test DACL nyata memakai tag `manual`.
- **Alasan:** Siklus impor dihindari. Fail-closed mencegah token kosong menjadi akses terbuka. Versi baru dan file rusak tidak boleh menimpa data pengguna diam-diam.
- **Dampak:** `waiting.md` memuat pembuktian DACL di laptop. Rotasi `.bak` masuk M6.

## [Backend M1] Auth, filter jaringan, dan GET /status

- **Konteks:** `docs/api-spec.md` (403, 401, envelope `{data}`), BR-1, BR-2, BR-12.
- **Keputusan:** `NetworkFilter` mengizinkan 10/8, 172.16/12, 192.168/16, 127/8, dan 100.64/10 setelah `Unmap`. Selain itu 403 `forbidden_network`, dan 403 dicek sebelum 401. `NewHandler` lama dipertahankan. `NewAPIHandler(logger, tokens, status)` memakai urutan Recover, Logging, NetworkFilter, slot rate limit M6, lalu Auth. Auth memakai header Bearer dengan skema tidak peka huruf besar dan `subtle.ConstantTimeCompare` setelah cek panjang. Auth berada di luar router, jadi rute tak dikenal tanpa token mendapat 401. `GET /api/v1/status` membalas `{name, version, uptimeSeconds, volume, pending}`. `pending` selalu null di M1. Error volume menghasilkan `volume: null` dengan status 200. Timeout baca audio 2 detik.
- **Alasan:** Urutan ini menolak IP publik sebelum token diperiksa. Penolakan tidak membocorkan token ke log atau respons.
- **Dampak:** Rate limit dan slot untuknya masuk M6. Field `pending` diisi di M4.

## [Backend M1] Host LAN, QR, dan pair

- **Konteks:** `docs/data-design.md` bagian 5, BR-12, `docs/release.md` bagian B.
- **Keputusan:** `listAdapters` bersifat read-only dan berada di paket `pairing`, sebagai pengecualian aturan `os-integration`. `SelectHost` memilih adapter up dengan gateway dan IPv4 privat, dengan urutan stabil. Host divalidasi sebelum `LoadOrInit`, dan `BuildPayload` juga memvalidasi host. Event lifecycle dicetak ke stdout oleh `pair`, bukan ke logger. `run` dan `pair` berbagi `loadConfigFile`. `pair` ikut membuat config bila belum ada, dan token tetap sama pada panggilan berikutnya.
- **Alasan:** Pemilihan host hanya membaca status adapter, tanpa mengubah sistem. Validasi di depan mencegah config tertulis dengan host yang salah.
- **Dampak:** `listAdapters` dipindah atau dicatat sebagai pengecualian di M5 atau M6 (`docs/todo/backlog/backend.md`). Pembuktian `pair` dengan adapter nyata ada di `waiting.md`.

## [Integrasi M1] Klien HTTP, repository status, dan mock

- **Konteks:** `docs/api-spec.md` (`GET /api/v1/status`, envelope `{data}` dan `{error}`), `docs/technical-spec.md`, dan `ConnectionController` yang meng-cache repository sekali saat `build()`.
- **Keputusan:** Satu `AgentHttpClient` dipakai pairing dan polling. `HttpStatusRepository` membaca `pairingProvider` pada setiap panggilan, jadi pairing baru terbaca tanpa membangun ulang controller. Pairing null menghasilkan `UnreachableFailure`, bukan `UnauthorizedFailure`. Body non-UTF-8 menjadi `ServerFailure`. Timeout dua lapis: controller dan scheduler pairing di atas, klien di bawah. Mock dipindah ke `test/support/` sebagai fake, tidak dihapus. Tes integrasi memakai server loopback Dart, bukan agent Go. Konfigurasi platform tidak diubah. Tidak ada perubahan Go atau `postman/`.
- **Alasan:** Satu klien mengurangi duplikasi penanganan error dan token. Membaca pairing per panggilan menghindari status palsu setelah pairing ulang. Fake di `test/support/` tetap dipakai tes dan tidak masuk build. Loopback Dart membuktikan kontrak HTTP tanpa menyalakan agent sungguhan di tes otomatis.
- **Dampak:** Copy untuk 403 dan 429 saat pairing masih menunggu keputusan desain (`docs/todo/backlog/integration.md`). Pembuktian dengan agent dan HP sungguhan ada di `docs/todo/waiting.md`.

## [QA M1] QA otomatis lulus, Fixing tidak relevan

- **Konteks:** Sepuluh skenario [O] M1 di `docs/todo/qa.md` diperiksa terhadap tes yang sudah ada. Tidak ada bug produksi.
- **Keputusan:** Skenario dibuktikan tes yang ada, ditambah satu tes BR-9 (401 setelah sukses mempertahankan data status terakhir) di `app/test/core/connection/connection_controller_test.dart`. Fase Fixing ditandai tidak relevan. Modul ditutup dengan `Selesai`, sementara skenario [M] tetap di `docs/todo/waiting.md`.
- **Alasan:** Tidak ada bug yang perlu diperbaiki, sehingga Fixing tidak punya pekerjaan. Tes yang ada sudah menutup BR-1, BR-2, BR-8, BR-9, BR-11, dan BR-12.
- **Dampak:** `go test -race` dan sisi log app BR-11 masuk backlog QA (`docs/todo/backlog/qa.md`).

## [Frontend M2] Repository media mock sebagai default

- **Konteks:** `docs/api-spec.md` bagian Media (`{"data":{"action":...}}`, 401 `invalid_token`, 500 `media_failed`, timeout). Pola `StatusRepository` dan fake di `test/support/`.
- **Keputusan:** `MediaRepository.send(MediaAction)` melempar `ApiFailure`. `MockMediaRepository` di `lib/` menerima skrip langkah berurutan (langkah terakhir diulang), tiap langkah berupa balasan HTTP atau timeout. Balasan lewat `unwrapAgentResponse`, lalu `data['action']` harus cocok dengan aksi, selain itu `ServerFailure`. Default `mediaRepositoryProvider` memakai `MockMediaEcho` yang membalas sukses untuk aksi apa pun dengan delay 150 ms. Fase Integrasi menggantinya dengan HTTP.
- **Alasan:** Skrip membuat 200, 401, 500, timeout, dan mismatch bisa diuji tanpa agent. Echo menjaga default tetap sukses untuk semua aksi.
- **Dampak:** Tombol media di app selalu berhasil sampai Integrasi. Kegagalan nyata hanya diuji lewat tes dan `waiting.md`.

## [Frontend M2] Status play, optimistic, dan tap ulang

- **Konteks:** API Media tidak mengirim status play. Desain S01 memakai ikon jeda saat jalan. `docs/technical-spec.md` menyebut media tidak diulang otomatis dan timeout 3 dtk.
- **Keputusan:** `playing` awal `true`. Tap play membalik ikon langsung (optimistic), lalu mengirim permintaan. Cincin proses muncul 400 ms setelah tap bila belum ada jawaban. Satu permintaan per tombol: tap ulang play diabaikan lewat flag `playProcessing`. Prev/next dibatasi dengan guard `_busy` privat per tombol, tombol lain tetap aktif. Tidak ada retry otomatis. Gagal (non-401) mengembalikan status, memunculkan toast "Ulangi", dan "Ulangi" pada play memanggil `togglePlay()` lagi. `mediaControllerProvider` tidak autoDispose agar status play bertahan.
- **Alasan:** Optimistic membuat tombol terasa cepat. Satu permintaan per tombol mencegah aksi ganda ke laptop. Retry otomatis bisa memutar atau menghentikan lagu dua kali.
- **Dampak:** Status play di app bisa berbeda dari laptop sampai status play asli ada (`docs/todo/backlog/frontend.md` M2).

## [Frontend M2] Ikon media, ukuran key, dan konstanta lokal

- **Konteks:** `design/components.md` C02, C03, C10. `RSize.mediaCompact` (72 dp) sudah ada, tetapi `SizedBox` tidak memperbesar kapsul `GlassKey`. `lib/ui` tidak boleh tahu domain.
- **Keputusan:** `RIcon` punya opsi `filled`. Ikon prev, next, play, dan pause dipasang di `RIcons`. `GlassKeySize.play` (96 dp) dan `playCompact` (88 dp) ditambahkan. `PlayKey.processingHint` berupa String yang wajib dari pemanggil. Periode putar cincin 900 ms, inset cincin 7 dp, ukuran ikon 36 dp, dan opacity kedip 0,35 adalah konstanta privat bernama. Kedip 240 ms adalah satu siklus dan mati saat reduced motion. Ikon play digeser 4 dp ke kanan sesuai artboard.
- **Alasan:** Ukuran baru menggantikan `SizedBox` yang tidak efektif. Teks hint dari pemanggil menjaga `lib/ui` bebas domain. Nilai yang hanya ada di artboard belum ada di token, jadi tetap konstanta privat sampai dicatat di backlog.
- **Dampak:** Token ukuran ikon, periode cincin, dan inset masuk `design/tokens.json` nanti (`docs/todo/backlog/frontend.md` M2).

## [Frontend M2] Gagal, 401, dan sumber haptic

- **Konteks:** `docs/todo/frontend.md` M1 memakai `reportUnauthorized` untuk 401. `ToastController` punya satu toast aktif.
- **Keputusan:** Semua kegagalan non-401 (timeout, 500, unreachable, dan lainnya) memakai toast yang sama. 401 memanggil `reportUnauthorized` tanpa toast. Haptic press berasal dari `Pressable` (saat jari turun). Haptic gagal berasal dari `MediaController` lewat `RHaptics.failure`, termasuk 401. Controller tidak memicu press.
- **Alasan:** Satu sumber haptic mencegah getar ganda untuk satu tap. 401 ditangani di tingkat koneksi, jadi toast tidak perlu.
- **Dampak:** Tap yang diabaikan (play sedang diproses) tetap bergetar karena press dari `Pressable` (`docs/todo/backlog/frontend.md` M2, cek rasa di `docs/todo/waiting.md`).

## [Frontend M2] Dock nonaktif dan inset toast

- **Konteks:** `design/scope-and-flows.md` (b), (d). Toast 12 dp di atas dock (`design/components.md` C07). `ToastHost` mengukur inset dari dasar layar.
- **Keputusan:** Dock aktif hanya saat `online` dan `back`. Dinonaktifkan saat `connecting`, `offline`, `poweredOff`, dan `tokenRejected`, karena panel status sudah menjelaskan alasannya. `toastBottomInsetProvider` menjadi `NotifierProvider` (awal 0). Inset = `MediaDock.heightFor(compact)` + `RSpace.s6`. `RemoteScreen` mengisi inset setelah frame dan mengembalikan 0 saat layar ditutup, lewat `Future.microtask` dengan guard `ref.mounted`.
- **Alasan:** Dock nonaktif memberi tahu pengguna bahwa perintah tidak akan sampai. Inset dihitung dari ukuran dock agar toast tidak menutupi tombol.
- **Dampak:** Layout 360 dan 412 dp dan posisi toast perlu dicek di HP fisik (`docs/todo/waiting.md` M2).

## [Backend M2] Opsi variadic WithMedia

- **Konteks:** `docs/technical-spec.md` bagian 7, `NewAPIHandler` dipanggil di enam tempat test.
- **Keputusan:** `NewAPIHandler(logger, tokens, status, opts ...APIOption)` dengan `WithMedia(c control.MediaController)`. Pemanggil lama tidak berubah.
- **Alasan:** Signature tetap kompatibel. Pola opsi ini sama dengan `WithAudio` dan `WithPower` di M3 dan M4.
- **Dampak:** Dependensi baru cukup menambah satu `APIOption`.

## [Backend M2] Rute media selalu terdaftar, fail-closed

- **Konteks:** `docs/api-spec.md` Media. `TestBR1AllAPIRoutesRequireToken` memuat rute media. Dependensi bisa nil bila wiring terlewat.
- **Keputusan:** Tiga rute `POST /api/v1/media/*` selalu terdaftar. Bila controller nil, respons 500 `media_failed`.
- **Alasan:** Rute tanpa controller tidak boleh diam-diam dianggap sukses.
- **Dampak:** Tes BR-1 mencakup rute media sejak awal.

## [Backend M2] MediaService di internal/control

- **Konteks:** Validasi aksi, serialisasi, dan pembungkus error OS perlu satu tempat yang tidak bergantung pada OS.
- **Keputusan:** `MediaService` menolak aksi tak dikenal dengan `ErrInvalidAction`, mengunci mutex selama pemanggilan, dan membungkus error OS menjadi `ErrMedia`. Pesan ke klien tetap "media control failed". Cause hanya dibuka lewat Unwrap untuk log.
- **Alasan:** Detail OS tidak bocor ke respons. Mutex mencegah dua perintah media berjalan bersamaan.
- **Dampak:** Handler tidak menyentuh OS secara langsung.

## [Backend M2] Satu SendInput berisi tekan dan lepas

- **Konteks:** Media key dikirim sebagai tekan lalu lepas. `docs/technical-spec.md` bagian 7.
- **Keputusan:** Satu panggilan `SendInput` memuat key down dan key up, keduanya extended key. Jumlah event yang diterima selain 2 menghasilkan `media_failed`.
- **Alasan:** Satu panggilan atomik, sehingga tidak ada tombol yang tertinggal tertekan bila pelepasan gagal.
- **Dampak:** Event yang diblokir UIPI terdeteksi sebagai gagal. Catatan pesan log ada di `docs/todo/backlog/backend.md` M2.

## [Backend M2] Handler mengabaikan body

- **Konteks:** `docs/api-spec.md` Media tidak mendefinisikan body request.
- **Keputusan:** Body request tidak dibaca. `{"x":1}` tetap 200.
- **Alasan:** Sesuai spec, dan tidak ada validasi yang perlu dijaga.
- **Dampak:** Klien boleh mengirim body apa pun tanpa efek.

## [Backend M2] Tanpa timeout khusus di domain media

- **Konteks:** `SendInput` sinkron dan cepat. `WriteTimeout` server 5 detik sudah cukup.
- **Keputusan:** Tidak ada timeout tambahan di domain media. `ctx` tetap diteruskan. Tidak ada retry.
- **Alasan:** Timeout tambahan tidak mengubah panggilan sinkron. Retry bisa memutar lagu dua kali.
- **Dampak:** Bila `SendInput` macet, perlu ditinjau di M6.

## [Backend M2] oswin/doc.go tanpa build tag

- **Konteks:** CI menjalankan `go vet ./...` di Linux.
- **Keputusan:** `internal/oswin/doc.go` berisi komentar paket tanpa build tag. Implementasi Windows ada di `media_windows.go`.
- **Alasan:** Paket tetap ada di Linux, sehingga `go vet ./...` tidak gagal.
- **Dampak:** Vet lintas OS tetap bisa dijalankan dengan `GOOS=linux`.

## [Backend M2] Test SendInput tanpa menyentuh OS

- **Konteks:** Aturan Remotto melarang media key sungguhan di test otomatis.
- **Keputusan:** `Media` menerima `sendFunc` yang disuntik. Test memakai fake. `NewMedia()` hanya dipasang di `cmd/agent`.
- **Alasan:** Test aman, cepat, dan tidak memengaruhi laptop.
- **Dampak:** Pembuktian nyata hanya lewat `docs/todo/waiting.md`.

## [Integrasi M2] Mock media dipindah ke fake di test/support

- **Konteks:** `MockMediaRepository` di `lib/` menjadi default `mediaRepositoryProvider` sejak Frontend M2. Pola M1 memindahkan mock ke `test/support/` sebagai fake.
- **Keputusan:** `MockMediaRepository` keluar dari `lib/` dan menjadi `FakeMediaRepository` di `test/support/` (file dan test ikut dipindah). Simbol `MockMedia*` dan `mockMedia*` diganti `FakeMedia*` dan `fakeMedia*`.
- **Alasan:** Tidak ada mock di build produksi. Fake di `test/support/` tetap dipakai test yang butuh skrip balasan.
- **Dampak:** `grep` untuk `mock_media` dan `MockMedia` di `app/lib` dan `app/test` kosong.

## [Integrasi M2] Pairing null menghasilkan UnreachableFailure

- **Konteks:** `HttpStatusRepository` memakai pola ini di M1. Media butuh aturan yang sama.
- **Keputusan:** `HttpMediaRepository` membaca `pairingProvider` pada setiap `send`. Bila pairing null, hasilnya `UnreachableFailure` tanpa request.
- **Alasan:** Tanpa pairing, app tidak tahu alamat atau token. `UnauthorizedFailure` akan salah memicu alur token ditolak.
- **Dampak:** Tombol media tanpa pairing menampilkan toast "Ulangi", bukan layar token ditolak.

## [Integrasi M2] Timeout repository sama dengan controller

- **Konteks:** `docs/technical-spec.md` bagian 6 dan `RMotion.commandTimeout` dipakai `MediaController`.
- **Keputusan:** `HttpMediaRepository` memakai `RMotion.commandTimeout` (3 dtk) sebagai default. `AgentHttpClient.postMedia` menerima `timeout` dan memasang `Future.timeout`. Tidak ada retry otomatis.
- **Alasan:** Timeout repository dan controller sama, sehingga keduanya memberi hasil yang sama. Ulangi dilakukan pengguna secara manual.
- **Dampak:** `Future.timeout` tidak membatalkan request. Request yang sudah terkirim bisa tetap diproses setelah toast gagal muncul (lihat `docs/todo/backlog/integration.md` M2 dan M1).

## [Integrasi M2] Aksi di data tidak cocok menjadi ServerFailure

- **Konteks:** `docs/api-spec.md` Media mengembalikan `{"data":{"action":...}}`. Aturan ini sebelumnya ada di mock.
- **Keputusan:** Bila `data['action']` tidak sama dengan aksi yang dikirim, klien melempar `ServerFailure`.
- **Alasan:** Respons yang tidak cocok berarti agent atau jalur lain tidak menjalankan aksi yang diminta. Tidak boleh dianggap sukses.
- **Dampak:** Aturan ini dijaga di jalur HTTP asli, bukan lagi di mock.

## [Integrasi M2] Kegagalan media menjadi rollback dan toast Ulangi

- **Konteks:** `docs/api-spec.md` Media dan `MediaController` (rollback, toast "Ulangi", tanpa retry otomatis).
- **Keputusan:** 403, 429, dan 500 `media_failed` menjadi rollback dan toast "Ulangi". 401 menjadi `UnauthorizedFailure` dan mengikuti alur token ditolak. Endpoint media tidak mengirim 409, jadi 409 bila muncul jatuh ke `ServerFailure`.
- **Alasan:** Satu perilaku untuk semua kegagalan kirim mengurangi kasus khusus. Copy khusus 403 dan 429 tidak ada di desain, jadi tidak ditambahkan.
- **Dampak:** Copy khusus untuk 403 dan 429 ada di `docs/todo/backlog/integration.md` M2 bila pemilik mau.

## [Integrasi M2] Helper _guard di AgentHttpClient

- **Konteks:** `getStatus` di M1 sudah punya blok pemetaan exception (timeout, format, socket, client). `postMedia` memakai pemetaan yang sama.
- **Keputusan:** Pemetaan dipindah ke helper privat `_guard` yang dipakai `getStatus` dan `postMedia`. Test `getStatus` lama tidak diubah.
- **Alasan:** Menghindari duplikasi dan menjaga pemetaan error tetap satu sumber.
- **Dampak:** Token tidak masuk ke failure atau log. Perubahan pada pemetaan berlaku untuk dua endpoint sekaligus.

## [Frontend M3] Satu VolumeController dan VolumeSender terpisah

- **Konteks:** Slider butuh throttle, satu request berjalan, dan kirim nilai akhir. Aturan itu bercampur dengan state UI bila ada di satu kelas.
- **Keputusan:** `VolumeSender` kelas murni (tanpa Riverpod dan widget) yang mengurus throttle 100 ms, satu request berjalan, timeout, dan retry. `VolumeController` memegang state dan memanggil sender. Keduanya non-autoDispose seperti `MediaController`.
- **Alasan:** Sender bisa diuji dengan `FakePollScheduler` dan `Completer` tanpa widget. Aturan kirim ada di satu tempat.
- **Dampak:** Controller tidak perlu tahu jadwal throttle.

## [Frontend M3] Fake volume di test/support, provider tanpa default

- **Konteks:** `docs/todo/frontend.md` M3 dan pola `[Integrasi M2]` memindahkan mock media ke `test/support/`. Rencana awal menaruh mock volume di `lib/`.
- **Keputusan:** `FakeVolumeRepository` ada di `app/test/support/`. `volumeRepositoryProvider` tidak punya default. App asli melempar error di layar Remote sampai Integrasi M3 menyediakan `HttpVolumeRepository`.
- **Alasan:** Tanpa default, tidak ada angka tiruan yang bisa tampil sebagai volume laptop. Pola ini sama dengan `[Integrasi M2]`.
- **Dampak:** Layar Remote di app asli tidak bisa dibuka sampai Integrasi M3. Pembuktian visual di HP menunggu (`docs/todo/waiting.md` M3).

## [Frontend M3] Angka "—" saat nilai volume belum diketahui

- **Konteks:** Sebelum status pertama dari agent, nilai volume belum diketahui. `docs/api-spec.md` mengizinkan `volume` bernilai null bila Core Audio gagal (desain untuk kasus ini belum ada).
- **Keputusan:** `known=false` (connecting dan belum pernah sukses) menampilkan "—", hint `hintWaiting`, dan kontrol nonaktif. Setelah ada status, angka terakhir tetap tampil saat connecting atau offline, dengan kontrol nonaktif.
- **Alasan:** Angka 0 atau 35 palsu membuat pengguna mengira volume laptop sudah diketahui. Angka terakhir tetap berguna saat koneksi putus.
- **Dampak:** Hint `hintWaiting` juga tampil di fase online selama `known=false` (`docs/todo/backlog/frontend.md` M3).

## [Frontend M3] Sinkron polling hanya saat idle

- **Konteks:** FR-3.7 dan BR-14. Polling datang berkala. Bila menimpa saat jari masih di slider, nilai melompat.
- **Keputusan:** Nilai dari status hanya diterapkan saat tidak dragging, sender tidak busy, dan tidak ada tombol berjalan. Bila ditahan, `confirmed` terbaru diterapkan saat idle. Poll diproses hanya bila identitas objek status berubah, sehingga status lama tidak diterapkan ulang. `volume == null` tidak mengubah apa pun.
- **Alasan:** Slider yang melompat saat ditarik terasa rusak. Identitas objek mencegah nilai basi menimpa nilai baru.
- **Dampak:** Angka di HP bisa tertinggal sampai slider dilepas.

## [Frontend M3] −/+ tanpa retry, mute retry diam-diam sekali

- **Konteks:** `docs/technical-spec.md` bagian 6: perintah relatif (`up`, `down`) tidak idempoten. `PUT /volume` dan `POST /volume/mute` dengan nilai eksplisit idempoten.
- **Keputusan:** −/+ optimistic ±5 tanpa retry. Tap ulang saat request berjalan diabaikan. Gagal: rollback ke `confirmed` dan toast `toastCommandFailed` dengan "Ulangi". Mute optimistic dan retry diam-diam sekali. Gagal lagi: rollback dan toast yang sama. Slider gagal: rollback ke `confirmed` dan toast S06 dengan "Ulangi".
- **Alasan:** Retry perintah relatif bisa menaikkan atau menurunkan volume dua kali. Mute memakai nilai eksplisit, jadi retry aman.
- **Dampak:** Kegagalan −/+ selalu terlihat pengguna sebagai toast. Kegagalan mute terlihat hanya bila retry kedua juga gagal.

## [Frontend M3] Geser saat bisu membuka bisu secara lokal

- **Konteks:** BR-15. `setLevel` di agent juga mematikan bisu. Tampilan tidak boleh menunjukkan bisu saat slider sedang mengubah volume.
- **Keputusan:** `dragStart` langsung mengatur `muted=false` secara lokal. Badge BISU hilang dan label tombol berubah saat itu juga.
- **Alasan:** Tampilan dan perilaku agent harus sama. Pengguna yang menggeser ingin mendengar suara.
- **Dampak:** Semantics increase di 100 atau decrease di 0 saat bisu belum membuka mute. Keputusan produk ada di `docs/todo/backlog/frontend.md` M3.

## [Frontend M3] Offline atau tokenRejected saat drag membatalkan gesture tanpa toast

- **Konteks:** `docs/todo/frontend.md` FR-3.6 dan `design/components.md` C04: offline saat drag membatalkan gesture dan slider kembali ke nilai terakhir.
- **Keputusan:** Saat phase masuk offline, poweredOff, atau tokenRejected dan sedang dragging atau request berjalan: `dragCancel`, tertunda dibuang, level dan muted kembali ke `confirmed`. Request yang sudah berjalan tidak diputus. Balasannya dibuang lewat penanda epoch (generation). Tidak ada toast.
- **Alasan:** Panel status sudah menjelaskan koneksi putus, sehingga toast menumpuk. Balasan lama tidak boleh menimpa nilai setelah koneksi pulih.
- **Dampak:** Setelah pulih, nilai disinkron biasa lewat polling.

## [Frontend M3] Animasi rollback tetap saat reduced motion

- **Konteks:** `docs/design-system.md` §6 mencatat animasi rollback sebagai "Tetap" saat reduced motion.
- **Keputusan:** Animasi isi slider kembali (`RMotion.fast`) tetap jalan saat reduced motion. Animasi lain di slider dimatikan saat reduced motion.
- **Alasan:** Rollback adalah umpan balik bahwa nilai gagal. Tanpa animasi, pengguna tidak melihat perubahan nilai.
- **Dampak:** Rasa animasi rollback dicek di HP (`docs/todo/waiting.md` M3).

## [Frontend M3] VolumeSlider memakai Listener dan parameter increase/decrease wajib

- **Konteks:** `Slider`, `SliderTheme`, dan `InkWell` dilarang. Tap dan drag horizontal harus dibedakan dari drag vertikal.
- **Keputusan:** `VolumeSlider` memakai `Listener` dan `StatefulWidget` sendiri. Drag vertikal diabaikan. Parameter `increasedValue` dan `decreasedValue` wajib agar Semantics selalu lengkap. State animasi dan ukuran track saat dragging disimpan di widget.
- **Alasan:** `Listener` memberi kontrol penuh atas tap dan drag horizontal. Animasi rollback butuh state di widget.
- **Dampak:** Pemanggil wajib mengisi nilai increase dan decrease.

## [Frontend M3] Konstanta artboard tanpa token jadi konstanta privat bernama

- **Konteks:** Badge 28 dp, inset 18, handle 5×24, ambang 6%, ikon 14/20/22, dan tombol −/+ 72 dp belum ada di `design/tokens.json`.
- **Keputusan:** Nilai itu menjadi konstanta privat bernama dengan komentar sumber artboard. Daftarnya dicatat di backlog M3 untuk masuk token nanti.
- **Alasan:** Sama dengan `[Frontend M2] Ikon media, ukuran key, dan konstanta lokal`. Token menunggu keputusan desain.
- **Dampak:** Perubahan token nanti perlu menyentuh `volume_panel.dart` dan `volume_slider.dart`.

## [Frontend M3] Haptic dikelola controller

- **Konteks:** `[Frontend M2] Gagal, 401, dan sumber haptic` menetapkan satu sumber haptic per aksi. Slider tidak memakai `Pressable`.
- **Keputusan:** `VolumeController` memanggil `RHaptics`: detent tiap kelipatan 5 yang terlewati, limit saat menyentuh 0 atau 100, dan failure saat kirim gagal. `VolumeSlider` hanya menerima callback `onDetent` dan `onLimit`. Tap-lompat tidak memberi detent per 5%.
- **Alasan:** Controller tahu nilai lama dan baru. Widget tidak perlu tahu aturan haptic.
- **Dampak:** Rasa getar dicek di HP (`docs/todo/waiting.md` M3). Haptic tap-lompat ada di `docs/todo/backlog/frontend.md` M3.

## [Frontend M3] setConfirmed menyemai nilai terkonfirmasi di sender

- **Konteks:** Aturan `finish` tidak mengirim nilai yang sama dengan sukses terakhir. Saat bisu, nilai itu tidak berlaku.
- **Keputusan:** `VolumeSender.setConfirmed` disemai dari status sukses. Saat bisu, nilainya null.
- **Alasan:** `setLevel` juga mematikan bisu (BR-15). Saat bisu, nilai yang sama tetap harus dikirim.
- **Dampak:** Tidak ada perubahan perilaku di luar sender.

## [Backend M3] VolumeService bermutex dan unmute di domain

- **Konteks:** `docs/prd.md` BR-3, BR-15, BR-16. `MediaService` sudah memakai mutex. `Step` membaca lalu menulis, jadi perlu serialisasi.
- **Keputusan:** `VolumeService` memakai `sync.Mutex`. `SetLevel` dan `Step` selalu memanggil `SetMuted(false)`, termasuk saat level berada di batas 0 atau 100. `Step` di batas tetap sukses dan tetap unmute.
- **Alasan:** Aturan unmute ada di domain, jadi handler dan UI tidak perlu mengulangnya. Batas tetap sukses supaya tombol + dan − tidak terasa rusak.
- **Dampak:** Test `TestBR15_*` dan `TestBR16_*` di `internal/control/volume_test.go` mengunci perilaku ini.

## [Backend M3] Respons volume berisi hasil baca ulang OS

- **Konteks:** Setelah tulis, nilai yang dikirim klien bisa berbeda dengan nilai di perangkat (pembulatan scalar, perangkat lain).
- **Keputusan:** Setiap operasi volume (GET, PUT, up, down, mute) membaca ulang OS, lalu mengembalikan hasil bacaan itu.
- **Alasan:** Klien melihat nilai yang benar-benar berlaku, bukan nilai yang diminta.
- **Dampak:** Satu baca OS tambahan per operasi. Biaya ini diterima untuk layar kendali.

## [Backend M3] Validasi PUT dua tingkat: invalid_request dan invalid_level

- **Konteks:** `docs/api-spec.md` Volume. Ada dua jenis salah kirim: body rusak dan nilai level salah.
- **Keputusan:** `level` hilang atau struktur body salah berarti `invalid_request`. `level` ada tetapi bukan integer 0 sampai 100 berarti `invalid_level`. Contoh `invalid_level`: 35.5, `"35"`, null, `true`, `1e2`, nilai di luar rentang. Pengecekan memakai regex pada `json.RawMessage`, bukan tipe Go.
- **Alasan:** Tipe Go tidak membedakan `35` dari `35.0` atau `1e2`. Regex pada teks mentah menolak bentuk yang tidak tepat dan tetap bisa membedakan dua kelompok error.
- **Dampak:** Handler `PUT /volume` menjalankan dua pengecekan sebelum menyentuh OS.

## [Backend M3] Interface audioBackend agar COM dites tanpa COM

- **Konteks:** Pekerja COM butuh Windows dan perangkat audio. Test otomatis tidak boleh mengubah volume sungguhan.
- **Keputusan:** Interface internal `audioBackend` (`read`, `writeLevel`, `writeMuted`, `close`) dengan implementasi `comBackend` di `_windows.go`. Test memakai backend palsu lewat `newAudioWith`.
- **Alasan:** Pemetaan scalar, timeout, re-init, dan recover bisa dites di semua OS tanpa COM.
- **Dampak:** Tidak ada test COM asli. Pembuktian COM asli ada di `docs/todo/waiting.md` M3.

## [Backend M3] Endpoint render default diambil ulang tiap operasi

- **Konteks:** Pengguna bisa mencolok atau mencabut headset kapan saja. `go-wca` `GetDefaultAudioEndpoint` menerima `stateMask` sebagai argumen kedua, padahal argumen itu sebenarnya ERole.
- **Keputusan:** `comBackend` memanggil `GetDefaultAudioEndpoint(eRender, eConsole)` setiap operasi. Nilai `wca.EConsole` dikirim ke argumen kedua, sesuai ERole.
- **Alasan:** Endpoint yang disimpan bisa usang setelah headset berubah. Biaya pemanggilan ulang kecil dibanding risiko salah perangkat.
- **Dampak:** Perubahan headset langsung terlihat di operasi berikutnya. Nama argumen di go-wca tetap membingungkan dan tidak diubah.

## [Backend M3] Wiring /status cukup oswin.NewAudio

- **Konteks:** `GET /status` sudah punya field `volume` dan `null` saat gagal (`StatusDeps.Audio`). Di Windows `platform_windows.go` masih memakai `unsupported{}`.
- **Keputusan:** `platform_windows.go` memakai `oswin.NewAudio()`. `status.go` tidak diubah.
- **Alasan:** Field dan aturan null sudah ada dan sudah dites. Perubahan hanya di wiring.
- **Dampak:** `/status.volume` bernilai asli di Windows. `Audio.Close()` belum dipanggil saat shutdown, lihat `docs/todo/backlog/backend.md` M3.

## [Backend M3] Dependency go-wca dan go-ole hanya di file _windows

- **Konteks:** `agent/go.mod` belum punya `github.com/moutend/go-wca` dan `github.com/go-ole/go-ole`. Agent juga dibangun untuk non-Windows.
- **Keputusan:** Tambah `go-wca` v0.3.0 dan `go-ole` v1.3.0. Kedua import hanya di file `_windows.go`.
- **Alasan:** Build non-Windows tidak menarik COM. `GOOS=linux go build` tetap bersih.
- **Dampak:** Risiko library terakhir rilis 2023 dibatasi di balik `AudioController`, lihat backlog M3.

## [Backend M3] Tidak memakai VK_VOLUME_* (S-3)

- **Konteks:** Tombol volume bisa dikirim lewat `SendInput` dengan `VK_VOLUME_UP`, `VK_VOLUME_DOWN`, dan `VK_VOLUME_MUTE`. Temuan S-3 membahas jalur ini.
- **Keputusan:** Volume memakai Core Audio lewat COM, bukan tombol virtual.
- **Alasan:** Tombol virtual tidak memberi nilai absolut dan tidak bisa membaca status. Endpoint `PUT /volume` butuh level pasti.
- **Dampak:** Kode M2 `SendInput` tidak berubah. Jalur tombol virtual tidak dipakai di M3.

## [Integrasi M3] Retry tetap di VolumeSender dan VolumeController

- **Konteks:** Frontend M3 menaruh retry di `VolumeSender` (PUT) dan `VolumeController` (mute). Repository bisa ikut retry bila tidak dibatasi.
- **Keputusan:** `HttpVolumeRepository` tidak retry. Retry hanya di sender dan controller sesuai aturan per endpoint.
- **Alasan:** Retry ganda di tiga lapis bisa menghasilkan sampai 4 request untuk satu aksi.
- **Dampak:** Repository murni satu request per panggilan. Tes retry ada di level sender dan controller.

## [Integrasi M3] Satu AgentHttpClient dengan metode volume baru

- **Konteks:** M1 dan M2 memakai satu `AgentHttpClient` untuk semua endpoint agent.
- **Keputusan:** Volume memakai `putVolume`, `postVolumeStep`, dan `postVolumeMute` di klien yang sama.
- **Alasan:** Header token, timeout, dan pemetaan error tetap di satu tempat.
- **Dampak:** Tidak ada klien HTTP kedua. Penambahan endpoint berikutnya cukup satu metode.

## [Integrasi M3] Kegagalan 400 dan 500 menjadi ServerFailure(code)

- **Konteks:** Agent mengirim kode error seperti `invalid_level` lewat body JSON pada 400.
- **Keputusan:** Status 400 dan 500 menjadi `ServerFailure` dengan field `code`. Tidak ada tipe failure baru.
- **Alasan:** Pemanggil cukup membedakan kode bila perlu. Tipe baru hanya menambah cabang yang tidak dipakai UI.
- **Dampak:** UI memperlakukan semua `ServerFailure` sebagai gagal kirim (toast S06 dan rollback).

## [Integrasi M3] Pairing null menghasilkan UnreachableFailure

- **Konteks:** `[Integrasi M2] Pairing null menghasilkan UnreachableFailure` berlaku untuk media. Volume memakai pola yang sama.
- **Keputusan:** `HttpVolumeRepository` membaca `pairingProvider` pada setiap panggilan. Bila null, hasilnya `UnreachableFailure` tanpa request.
- **Alasan:** Tanpa pairing, `UnauthorizedFailure` akan salah memicu alur token ditolak.
- **Dampak:** Slider tanpa pairing rollback dan menampilkan toast, bukan layar Q12.

## [Integrasi M3] VolumeStatus.fromData publik sebagai satu sumber parser

- **Konteks:** Respons `GET /status` dan respons volume punya bentuk field yang sama.
- **Keputusan:** `VolumeStatus.fromData` dibuat publik dan dipakai oleh parser status serta parser respons volume.
- **Alasan:** Satu parser mencegah aturan `null` dan rentang level berbeda di dua tempat.
- **Dampak:** Perubahan bentuk volume cukup disentuh di satu fungsi.

## [Integrasi M3] Respons volume dibaca dari data langsung

- **Konteks:** Respons `up`, `down`, dan `mute` berisi hasil baca ulang OS (`[Backend M3] Respons volume berisi hasil baca ulang OS`).
- **Keputusan:** Parser membaca field volume dari body langsung. Field `action` tidak dipakai.
- **Alasan:** Field `action` tidak ada di kontrak `docs/api-spec.md` untuk volume. Membacanya akan menambah ketergantungan yang tidak perlu.
- **Dampak:** Penambahan field `action` di agent tidak merusak parser app.

## [Integrasi M3] Tes invalid_level di level repository

- **Konteks:** Slider sudah meng-clamp nilai ke 0 sampai 100 sebelum kirim, jadi UI tidak pernah mengirim `invalid_level`.
- **Keputusan:** Tes 400 `invalid_level` ditulis di level repository, bukan di UI.
- **Alasan:** Jalur error tetap terbukti bila clamp di UI dilonggarkan kelak.
- **Dampak:** Kasus ini tidak muncul di tes widget. Pembuktian nyata ada di Postman (`waiting.md` M3 Backend).

## [Fixing M3] Unmute hanya saat perangkat bisu, dan kegagalan unmute tetap 500

- **Konteks:** Geser slider dan tombol −/+ (`PUT /volume`, `POST /volume/up`, `POST /volume/down`) menjawab 500 `audio_failed` di laptop user, padahal volume Windows sudah berubah. App menampilkan toast gagal lalu angka loncat balik. Log agent mencatat `set mute: Incorrect function.`. `SetMute` gagal dengan ERROR_INVALID_FUNCTION di endpoint audio laptop itu, sedangkan `POST /volume/mute` tetap berhasil. `VolumeService.setLevelLocked` selalu memanggil `SetMuted(false)` setelah `SetLevel` (lihat `[Backend M3] VolumeService bermutex dan unmute di domain`).
- **Keputusan:**
  - D1: `setLevelLocked` membaca `Volume()` untuk cek mute sebelum menulis mute. `SetMuted(false)` hanya dipanggil bila perangkat bisu, lalu hasil dibaca ulang. Hasil baca setelah `SetLevel` dipakai sebagai respons. Jalur umum menambah satu baca OS dan tidak menulis mute.
  - D2: Unmute yang gagal pada perangkat bisu tetap 500 `audio_failed`. Level yang sudah tertulis tidak di-rollback. Respons 200 palsu ditolak, karena app membaca 200 sebagai sukses.
  - D3: Perbaikan di satu titik, yaitu `setLevelLocked`, sehingga `SetLevel`, `Up`, dan `Down` ikut. `POST /volume/mute` dan `VolumeService.SetMuted` publik tidak berubah.
  - D4: Warning `status audio read failed` di `GET /status` tidak dibatasi rate limit, sehingga bisa berulang tiap poll. Dedupe dicatat di backlog bila warning ini berisik.
  - D5: Logger untuk `/status` masuk lewat parameter `newStatusHandler`, bukan field `StatusDeps` yang dipakai di banyak tempat.
- **Alasan:** BR-15 tetap berlaku: laptop yang bisu kembali bersuara saat slider digeser atau tombol + ditekan. Perangkat yang tidak bisu tidak perlu menulis mute, sehingga kegagalan `SetMute` tidak lagi memutus slider. Respons 500 saat unmute gagal tetap jujur, karena klien tidak boleh menganggap sukses bila laptop masih bisu.
- **Dampak:** Tidak ada perubahan API, `docs/api-spec.md`, atau Postman. Fake `internal/oscontrol/fake` mendapat `SetMuteErr` dan `SetMutedCalls`. Test regresi ada di `internal/control` dan `internal/server`. Pembuktian di laptop ada di `docs/todo/waiting.md` bagian M3.

## [Frontend M4] Fake power di test/support, provider tanpa default

- **Konteks:** Pola `[Frontend M3] Fake volume di test/support, provider tanpa default` dan `[Integrasi M2]`.
- **Keputusan:** `FakePowerRepository` ada di `app/test/support/`. `powerRepositoryProvider` tidak punya default. `HttpPowerRepository` dibuat di fase Integrasi M4.
- **Alasan:** Tanpa default, tidak ada kondisi laptop tiruan yang bisa tampil sebagai kenyataan. Dari app asli belum ada perintah daya yang bisa terkirim sebelum Integrasi.
- **Dampak:** Layar daya di app asli belum bisa dipakai sampai Integrasi M4. Pembuktian nyata ada di `docs/todo/waiting.md` bagian M4.

## [Frontend M4] 409 daya tetap ServerFailure dengan code

- **Konteks:** `power_pending`, `no_pending_power`, dan `power_executing` datang sebagai 409. Test `agent_http_client_test` menegaskan 409 tidak dipetakan khusus.
- **Keputusan:** Ketiganya tetap `ServerFailure` dengan field `code`. Tidak ada tipe `ConflictFailure` baru.
- **Alasan:** Sama dengan `[Integrasi M3] Kegagalan 400 dan 500 menjadi ServerFailure(code)`. Tipe baru hanya menambah cabang yang dipakai satu tempat.
- **Dampak:** Alur daya membaca `code` bila perlu, misalnya untuk memilih P11 atau P14.

## [Frontend M4] PowerFlowController sebagai sumber state, route sebagai cermin

- **Konteks:** Alur daya punya sheet, tahan, hitung mundur, hasil, dan pemulihan. State yang tersebar di beberapa route bisa berbeda satu sama lain.
- **Keputusan:** `PowerFlowController` adalah satu-satunya sumber state. `PowerFlowHost` hanya mencerminkan state ke route. Route memakai Navigator non-opaque, bukan go_router.
- **Alasan:** State bisa dites tanpa widget. Alur daya tidak perlu URL sendiri, dan Remote tetap terlihat di belakang.
- **Dampak:** Logika baru masuk controller. Route cukup menampilkan state yang diberikan.

## [Frontend M4] Hitung mundur dari remainingMs

- **Konteks:** `[Gate 1] Pemulihan saat app dibuka di tengah perintah daya` memakai sisa waktu, bukan jam, karena jam dua perangkat bisa berbeda (BR-20).
- **Keputusan:** Hitung mundur memakai `remainingMs` dari `/status` dengan timer lokal. Angkanya dibulatkan ke atas. Jam HP tidak dibandingkan dengan jam laptop.
- **Alasan:** Pembulatan ke atas mencegah angka 0 tampil sebelum waktunya.
- **Dampak:** Angka di app bisa sedikit berbeda dari jam laptop. Yang dipakai adalah sisa waktu, bukan jam.

## [Frontend M4] Timeout dan ambigu membaca /status, tidak pernah P10

- **Konteks:** `[Gate 2] Timeout penjadwalan daya tidak menampilkan P10`. Frontend punya kasus tambahan: 409 `power_pending` dan `ServerFailure` tak terduga saat schedule.
- **Keputusan:** Timeout atau error tak terduga saat schedule membaca `/status`. Bila `/status` gagal, tampil P11 dan `lastPowerCommand` tetap tercatat. 409 `power_pending` dengan `/status` yang tak terbaca juga P11, bukan P10. P10 tidak pernah tampil bila laptop mungkin akan mati.
- **Alasan:** Pesan "laptop masih nyala" yang salah lebih berbahaya daripada peringatan yang berlebihan.
- **Dampak:** P11 dipakai untuk lebih banyak kasus daripada rancangan awal.

## [Frontend M4] Penjaga _dismissedKey dan P11 yang habis

- **Konteks:** Poll yang sudah berjalan saat Batal dikirim bisa membawa `pending` lama. Tanpa penanda, P13 muncul lagi setelah laptop membatalkan (temuan Reviewer).
- **Keputusan:** `_dismissedKey` diisi saat P09 atau P14 ditutup dan saat batal berhasil. P11 yang masih berjalan sampai 0 menjadi P09 (sent), dan `lastPowerCommand` tetap tercatat.
- **Alasan:** Jadwal yang sudah selesai atau dibatalkan tidak dianggap berjalan lagi. P11 yang habis berarti perintah sudah diminta ke laptop, jadi P09 paling jujur.
- **Dampak:** Respons status yang telat tidak lagi memunculkan P13 setelah batal.

## [Frontend M4] lastPowerCommand disimpan di SharedPreferences

- **Konteks:** `[Frontend M1] Mesin koneksi` menyiapkan `LastPowerCommand` untuk M4. P15 dan teks "dari HP ini" butuh tahu aksi terakhir setelah app ditutup.
- **Keputusan:** Disimpan sebagai `{action, sentAt}` dengan `sentAt` dalam UTC ISO 8601. Dibuang bila lebih tua dari TTL atau `sentAt` ada di masa depan. Dihapus saat pairing disimpan atau dihapus.
- **Alasan:** Isinya hanya aksi dan waktu, tidak ada token, jadi tidak perlu secure storage. TTL dan pengecekan masa depan mencegah data basi atau jam salah dipakai.
- **Dampak:** Teks "dari HP ini" hanya tampil bila data ini ada.

## [Frontend M4] Restart tidak masuk P15

- **Konteks:** `[Gate 1] Restart masuk scope` dan `[Gate 1] Pemulihan saat app dibuka di tengah perintah daya` menyebut P15 untuk laptop mati. Restart menyalakan laptop lagi setelah login.
- **Keputusan:** P15 "Laptop lagi mati" hanya untuk sleep dan shutdown (FR-4.11). Restart tidak masuk `poweredOff`.
- **Alasan:** Teks "lagi mati" akan menyesatkan setelah restart, karena laptop nyala lagi tanpa intervensi.
- **Dampak:** Cabang `restart` di `OfflineContent` tidak tercapai lagi (`docs/todo/backlog/frontend.md` M4).

## [Frontend M4] Copy varian turunan dari artboard

- **Konteks:** Artboard tidak punya copy untuk toast P08 per aksi, P09 sleep dan restart, P14 per aksi, dan P15 sleep.
- **Keputusan:** Copy diturunkan dari kalimat artboard yang paling dekat dan dikumpulkan di `app/lib/core/strings/power_strings.dart`. Gaya tetap bahasa Indonesia santai.
- **Alasan:** Layar tidak tampil kosong, dan copy terpusat mudah direvisi saat desain bertambah.
- **Dampak:** Copy turunan perlu dicek terhadap desain (`docs/todo/waiting.md` bagian M4).

## [Frontend M4] Warna bahaya dari ColorScheme dan status tokens

- **Konteks:** `StatusTokens` tidak punya `danger` atau `onDanger`, sedangkan tombol dan cincin countdown butuh warna bahaya.
- **Keputusan:** Warna diambil dari `colorScheme.error` dan `onError`, serta `status.dangerText` dan `status.dangerSoft`. Cincin countdown memakai `status.dangerText`.
- **Alasan:** Token yang sudah ada dipakai dulu, tanpa menambah nilai di luar `tokens.json`.
- **Dampak:** Token `danger` di `StatusTokens` masuk backlog M4 (`docs/todo/backlog/frontend.md`).

## [Frontend M4] Padding label tombol daya 4 dp

- **Konteks:** `GlassKey` memberi padding horizontal 20 dp (`RSpace.s5`). Dengan itu label tombol daya pecah di 360 dp.
- **Keputusan:** `GlassKeySize.power` memakai padding label horizontal 4 dp.
- **Alasan:** Hitungan di backlog M4 menunjukkan area teks 20 dp tidak cukup untuk "Matikan" di 360 dp.
- **Dampak:** Hasil di HP fisik perlu dicek (`docs/todo/waiting.md` bagian M4).

## [Frontend M4] Haptic gagal-batal dari controller

- **Konteks:** `[Frontend M2] Gagal, 401, dan sumber haptic` dan `[Frontend M3] Haptic dikelola controller` menetapkan satu sumber haptic per aksi.
- **Keputusan:** Haptic saat batal gagal dipanggil dari `PowerFlowController`, bukan dari `CountdownScreen`.
- **Alasan:** Mencegah getar ganda untuk satu tap.
- **Dampak:** Haptic tekan tombol Batal tetap berasal dari `Pressable` seperti tombol lain.

## [Frontend M4] Test wajib meng-override sharedPreferencesProvider

- **Konteks:** `lastPowerCommandProvider` membaca prefs. Test yang membangun container tanpa override gagal dengan `UnimplementedError: override in bootstrap`.
- **Keputusan:** Setiap test yang membangun container meng-override `sharedPreferencesProvider`.
- **Alasan:** Provider prefs sengaja tidak punya default, sama dengan pola storage M0.
- **Dampak:** Test baru yang lupa override akan gagal dengan pesan yang sama.

## [Backend M4] Jeda 5 detik sebagai konstanta

- **Konteks:** `docs/prd.md` BR-4 mewajibkan jeda 5 detik sebelum perintah daya dijalankan. Test tidak boleh menunggu waktu nyata.
- **Keputusan:** Jeda adalah konstanta `PowerDelay` tanpa opsi konfigurasi. Test memakai clock palsu (`internal/oscontrol/fake/clock.go`).
- **Alasan:** Jeda adalah pengaman, bukan preferensi. Opsi konfigurasi bisa membuatnya nol tanpa sengaja.
- **Dampak:** Mengubah jeda berarti mengubah kode dan test. Efek nyata hanya bisa dicek di laptop (`docs/todo/waiting.md` M4).

## [Backend M4] Jadwal saat executing dijawab 409 power_pending

- **Konteks:** `docs/api-spec.md` memakai `power_executing` untuk Cancel saat perintah berjalan.
- **Keputusan:** Schedule saat state `executing` dijawab 409 `power_pending`. `power_executing` hanya untuk Cancel.
- **Alasan:** Sesuai kontrak api-spec. Klien tidak boleh menjadwal ulang saat perintah sudah berjalan.
- **Dampak:** App harus membaca `pending` dari `/status` sebelum menjadwal.

## [Backend M4] Cancel dan eksekusi diselesaikan lewat nomor generasi

- **Konteks:** Timer bisa sudah menembak saat Cancel datang. Hasil `Timer.Stop()` bisa basi, jadi tidak bisa jadi penentu.
- **Keputusan:** Setiap jadwal punya nomor generasi `gen`. Cancel dan eksekusi memeriksa `gen` di bawah mutex. `Execute` dipanggil di luar lock dengan timeout 15 detik. `recover` mengembalikan state ke idle.
- **Alasan:** Satu pemeriksaan di bawah lock mencegah Cancel dan eksekusi sama-sama menang. Timeout mencegah state macet bila panggilan OS tidak kembali.
- **Dampak:** Test race Cancel vs fire baru terbukti penuh dengan `-race` di CI (`docs/todo/backlog/backend.md` M4).

## [Backend M4] Close membuang jadwal, eksekusi yang berjalan dibiarkan

- **Konteks:** Jadwal hanya ada di memori (`[Gate 1] Jadwal daya hanya di memori`). Agent yang berhenti tidak boleh menjalankan perintah daya yang sudah tidak diminta.
- **Keputusan:** `Close` membuang jadwal yang belum berjalan. Eksekusi yang sudah dimulai dibiarkan selesai.
- **Alasan:** Menunggu eksekusi di Close bisa menggantung. Graceful shutdown penuh ditunda ke M6.
- **Dampak:** `Close()` belum menunggu eksekusi (`docs/todo/backlog/backend.md` M4).

## [Backend M4] Controller nil berarti fail-closed

- **Konteks:** Jalur daya OS bisa tidak tersedia, misalnya saat build non-Windows.
- **Keputusan:** Schedule dengan controller nil dijawab 500 `power_failed` dengan pesan generik. Rute tetap terdaftar, sama seperti pola media dan volume. Kegagalan `Execute` setelah jeda hanya masuk log, karena respons 200 sudah dikirim.
- **Alasan:** Gagal tertutup, sehingga tidak ada perintah daya yang diam-diam dianggap berhasil.
- **Dampak:** Klien tidak melihat kegagalan setelah jeda kecuali lewat `/status` dan log.

## [Backend M4] Shutdown dan restart lewat shutdown.exe tanpa /f

- **Konteks:** R-15 meminta Windows tetap menahan shutdown bila ada pekerjaan belum tersimpan.
- **Keputusan:** Memanggil `shutdown.exe /s /t 0` dan `/r /t 0` dengan path System32 penuh, tanpa shell. Flag `/f` tidak pernah dipakai.
- **Alasan:** `/f` memaksa aplikasi tertutup dan bisa menghilangkan pekerjaan yang belum tersimpan. Path penuh mencegah pencarian PATH yang bisa disisipi.
- **Dampak:** Shutdown bisa ditahan Windows. Perilaku `pending` saat itu ada di `docs/todo/waiting.md` M4.

## [Backend M4] Sleep memilih jalur saat runtime lewat GetPwrCapabilities

- **Konteks:** `[Gate 2] Sleep memilih jalur saat runtime`. Di laptop pengembangan, `SetSuspendState` pada S0 bisa menjadi hibernate atau gagal.
- **Keputusan:** AoAc dicek lebih dulu: `PostMessageW(SC_MONITORPOWER)`. Bila tidak ada, S3 memakai `SetSuspendState` dengan `SeShutdownPrivilege`. Bila keduanya tidak tersedia, error.
- **Alasan:** AoAc didahulukan karena itu jalur yang benar di laptop S0. `PostMessageW` dipakai, bukan `SendMessage`, agar tidak menggantung. Hasil dinilai dari nilai kembalian, bukan `GetLastError` yang bisa basi.
- **Dampak:** `SeShutdownPrivilege` dibiarkan aktif setelah dipakai. Jalur S3 belum terbukti (`docs/todo/waiting.md` M4).

## [Backend M4] Offset struct SYSTEM_POWER_CAPABILITIES

- **Konteks:** Struct 76 byte dibaca dari urutan field `winnt.h`. Header SDK di mesin ini belum dicek.
- **Keputusan:** `SystemS3` di offset 5 dan `AoAc` di offset 20. Offset AoAc dikoreksi dari 19.
- **Alasan:** Koreksi berdasarkan urutan field dan pembacaan read-only di laptop ini. Pengecekan ke header SDK menunggu sumbernya tersedia.
- **Dampak:** Offset 20 perlu dicocokkan dengan SDK (`docs/todo/backlog/backend.md` M4, `docs/todo/waiting.md` M4).

## [Backend M4] cmdRun memasang slog default

- **Konteks:** Log `sleep path chosen` dari `oswin` harus masuk file log agent agar bisa didiagnosis.
- **Keputusan:** `cmdRun` memanggil `slog.SetDefault(logger)`. Default lama dikembalikan lewat defer.
- **Alasan:** Log jalur sleep ikut tercatat di `agent.log` tanpa meneruskan logger ke setiap paket.
- **Dampak:** Paket lain di proses yang sama ikut memakai logger ini selama `cmdRun` berjalan.

## [Backend M4] serveAgent menerima PowerController

- **Konteks:** Scheduler daya perlu satu pemilik lifecycle, sama seperti volume dan media.
- **Keputusan:** `serveAgent` menerima `PowerController`, membangun scheduler sendiri, dan memasang Close di satu tempat.
- **Alasan:** Penutupan jadwal saat agent berhenti tidak tersebar di banyak tempat.
- **Dampak:** Perakitan di `cmd/agent` menjadi satu titik untuk memeriksa lifecycle daya.

## [Backend M4] Test wiring sleep hanya memeriksa field

- **Konteks:** `TestNewPowerSleepNotImplemented` memanggil jalur OS produksi.
- **Keputusan:** Diganti `TestNewPowerWiresSleep`, yang hanya memeriksa field.
- **Alasan:** Test otomatis tidak boleh menjalankan efek daya sungguhan (aturan proyek: tanpa perintah daya sungguhan di test otomatis).
- **Dampak:** Efek sleep hanya bisa dibuktikan di laptop (`docs/todo/waiting.md` M4).

## [Integrasi M4] Satu AgentHttpClient dengan metode daya mentah

- **Konteks:** Schedule dan cancel daya memakai header token, timeout, dan pemetaan error yang sama dengan endpoint lain.
- **Keputusan:** `AgentHttpClient.postPowerSchedule` dan `postPowerCancel` mengembalikan data mentah. Parser tetap di `features/remote/data/power_repository.dart`.
- **Alasan:** Satu klien mengurangi duplikasi. `core` tidak boleh mengimpor `features`, jadi parser tidak dipindah ke `core`.
- **Dampak:** Penambahan endpoint daya berikutnya cukup satu metode mentah dan satu parser di `features`.

## [Integrasi M4] HttpPowerRepository tanpa retry dan timeout 3 detik

- **Konteks:** Retry daya bisa menjadwalkan dua kali atau membatalkan jadwal yang sudah berjalan. Timeout bisa terjadi setelah agent sudah menerima perintah.
- **Keputusan:** `HttpPowerRepository` tidak retry. Timeout schedule dan cancel tetap 3 detik. Timeout menjadi `TimeoutFailure`, lalu controller membaca `/status`.
- **Alasan:** Satu request per aksi menjaga aturan tanpa retry otomatis untuk perintah daya. Pembacaan `/status` memberi kebenaran dari agent (lihat `[Frontend M4] Timeout dan ambigu membaca /status, tidak pernah P10`).
- **Dampak:** Jadwal bisa tetap tercatat setelah timeout. Lihat backlog integrasi M4.

## [Integrasi M4] Pairing null menghasilkan UnreachableFailure

- **Konteks:** Pola yang sama dengan `[Integrasi M2]` dan `[Integrasi M3]`.
- **Keputusan:** `HttpPowerRepository` membaca `pairingProvider` pada setiap panggilan. Bila null, hasilnya `UnreachableFailure` tanpa request.
- **Alasan:** Tanpa pairing, `UnauthorizedFailure` akan salah memicu alur token ditolak.
- **Dampak:** Aksi daya tanpa pairing menampilkan P10 dan tidak mengirim apa pun.

## [Integrasi M4] 409 daya tetap ServerFailure dengan code

- **Konteks:** Agent membalas 409 `power_pending` atau `power_executing` saat jadwal bentrok atau batal saat eksekusi.
- **Keputusan:** 409 menjadi `ServerFailure(code)`, tanpa tipe baru.
- **Alasan:** Sama dengan `[Integrasi M3] Kegagalan 400 dan 500 menjadi ServerFailure(code)`.
- **Dampak:** Controller memetakan kode 409 ke P08, P14, atau P13 sesuai alur.

## [Integrasi M4] Pending.fromData memvalidasi action

- **Konteks:** Test kontrak menemukan `Pending.fromData` menerima action yang tidak dikenal, sehingga jadwal rusak bisa lolos sebagai jadwal valid.
- **Keputusan:** `Pending.fromData` hanya menerima action dari konstanta `{sleep, restart, shutdown}` di `core/network/agent_status.dart`. Action lain membuat parse 202 dan `/status` gagal sebagai `ServerFailure`.
- **Alasan:** Jadwal tak dikenal tidak boleh ditampilkan sebagai hitung mundur yang bisa dibatalkan.
- **Dampak:** Seluruh `/status` dengan action tak dikenal ditolak, bukan hanya field `pending`. Perilaku ini disengaja.

## [Integrasi M4] Bukti integrasi lewat loopback dan kontrak

- **Konteks:** Agent Go asli tidak boleh menjalankan sleep, restart, atau shutdown di test otomatis.
- **Keputusan:** Bukti berupa `FakeAgentServer` loopback dengan rute `/power/*` (`app/test/integration/power_http_flow_test.dart`) dan test kontrak dengan payload persis keluaran Go (`app/test/core/network/power_contract_test.dart`). Tidak ada agent asli atau efek OS di test otomatis.
- **Alasan:** Aturan efek OS di `docs/development-workflow.md`. Kontrak dengan payload Go menangkap perbedaan bentuk JSON.
- **Dampak:** Pembuktian dengan agent dan HP sungguhan ada di `docs/todo/waiting.md` M4 (Integrasi).
