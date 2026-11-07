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
