# Backlog Frontend

Satu baris per temuan, dengan referensi inline. Heading modul tidak boleh dihapus.

## M0 Fondasi Proyek

- [ ] Ikon launcher Android masih PNG legacy (`mipmap-*/ic_launcher.png`, dari SVG gelap). Catatan teknis `design/export/artboards/Logo.dc.html` meminta adaptive icon (layer background + foreground di zona 66%). Belum dikerjakan di T5.
- [ ] Ikon 48 dp: catatan Logo.dc.html menyebut dua titik kecil mungkin perlu dihapus di varian kecil. Belum diputuskan; cek visual di HP fisik.
- [ ] Saturasi `GlassPanel` belum diterapkan, token `component.glassPanel.saturation` (1.7) tidak dipakai; lihat `[Frontend M0] GlassPanel: blur tanpa saturasi` di `docs/decision-log.md`. Tinjau lagi bila Flutter/Impeller menyediakan color filter untuk backdrop.
- [ ] Nilai yang hanya ada di artboard (bayangan kaca 0/12/32, posisi dan radius glow latar di `LightBackdrop`, ring fokus) masih konstanta privat di kode; angkat ke `design/tokens.json`.
- [ ] Ikon dan ukuran ikon `GlassKey` (17–22 dp) belum ada, dan ukuran 64 dp belum punya token; periksa saat M1 mulai memakainya. Lihat `[Frontend M0] Tombol kaca dan ukuran` di `docs/decision-log.md`.
- [ ] `app/lib/ui/glass_panel.dart` baris 129 ("Lihat laporan") mengacu laporan yang tidak ter-commit; ganti dengan rujukan ke backlog ini dan decision-log.
- [ ] Verifikasi `app/android/.gitignore` meng-ignore `gradle-wrapper.jar` dan `gradlew`. Aman untuk `flutter build`; un-ignore bila CI memanggil `./gradlew`.
- [ ] Izin dan konfigurasi iOS (Info.plist, AppIcon, Podfile `PERMISSION_CAMERA=1`) belum terverifikasi; butuh Mac, lihat `docs/todo/waiting.md`.

## M1 Pairing & Koneksi

- [ ] T7 PairingScaffold: tombol aksi utama tidak selebar 100% seperti artboard (C15 "100%"). `GlassKey` membungkus `Pressable` yang memusatkan isinya, jadi lebar penuh butuh opsi `fill`/`expand` di `GlassKey` (file T2). Sementara kapsul memakai lebar konten dan berada di tengah.
- [ ] T7 PairingScaffold: tips memakai `bodyLarge` (16 dp), artboard 15 dp. Tidak ada token 15 dp di `RType`.
- [ ] T7 PairingScaffold: belum diverifikasi visual (layout 412/360 dp dan teks 130% hanya lewat widget test).
- [ ] T15 StatusPill + OfflineContent: ukuran ikon dan tinggi pill (28 dp pill, 14 dp indikator, 40 dp ikon keadaan) belum ada token di `design/tokens.json`; sementara konstanta privat bernama di `status_pill.dart` dan `offline_content.dart`.
- [ ] T15 StatusPill: label Semantics statis per varian (`NYAMBUNG`, `NYAMBUNG LAGI`, `MENYAMBUNG`, `NGGAK KEJANGKAU`, `LAGI MATI`) belum ada di `core/strings/remote_strings.dart` (T6). `StatusPill` menerima `semanticsLabel` dari pemanggil; T16 perlu menyediakannya.
- [ ] T11 QrViewfinder: error kamera selain izin (`MobileScannerException` bukan `permissionDenied`) belum punya copy di artboard. Saat ini pratinjau tetap gelap dan "Isi manual" tetap tersedia. Perlu copy dari desain.
- [ ] T11 QrViewfinder: ukuran ikon back dan senter (20 dp) memakai `RSpace.s5` karena tidak ada token ikon. Perlu token ikon di `design/tokens.json`.
- [ ] T11 QrViewfinder: banner Q04 memakai `GlassToast` (durasi internal 6 dtk), sedangkan `ScanView` menghapusnya setelah 3 dtk. Keluar banner tanpa animasi. Perlu parameter durasi di `GlassToast` atau animasi keluar khusus banner.
- [ ] T11 QrViewfinder: belum diverifikasi visual (bingkai 248 dp, banner, senter di kamera nyata).
- [x] T15 OfflineContent: body untuk keadaan "Laptop lagi mati" belum ada di desain. Diselesaikan di Frontend M4 (P15, lihat `[Frontend M4] Copy varian turunan dari artboard`).
- [ ] T7 `_startTest` (Q08): cek `attempt` sebelum `save` supaya "Batal" saat penyimpanan berjalan tidak lanjut ke Q09. Ditemukan Reviewer.
- [ ] T7 PairingScaffold: margin Q08 24 dp, sedangkan PairingScaffold memakai 20 dp. Perlu keputusan nilai yang dipakai.
- [ ] T8 pesan error host di luar rentang (contoh 8.8.8.8, IP publik) masih memakai pesan Q07 yang sama. Perlu keputusan copy khusus dari desain.
- [ ] T8 Android `permission_handler` tidak mengembalikan permanentlyDenied lewat status: Q01 ke Q02, lalu Q05 setelah request. Perlu keputusan cara deteksi izin permanen di Android.
- [ ] T12 GlassTextField: ikon mata token memakai `eye`; ikon `eye-off` belum ada di artboard dan tidak dibuat. Perlu keputusan desain bila ingin ikon kedua.
- [ ] Komentar Indonesia tersisa di file M0: `lib/ui/r_haptics.dart`, `lib/core/storage/*`, `lib/core/theme/*`, `lib/ui/glass_panel.dart`, `lib/ui/light_backdrop.dart`, `lib/ui/pressable.dart`, `lib/core/router/route_transitions.dart`, `lib/app.dart`. Ditemukan Reviewer.

## M2 Kontrol Media

- [ ] Token ukuran ikon media 28 dp dan 36 dp belum ada di `design/tokens.json`; saat ini konstanta privat di `lib/ui/play_key.dart`. Lihat `[Frontend M2] Ikon media, ukuran key, dan konstanta lokal` di `docs/decision-log.md`.
- [ ] Periode putar cincin proses (900 ms), inset cincin (7 dp), dan opacity kedip (0,35) masih konstanta privat; angkat ke `design/tokens.json`.
- [x] `HttpMediaRepository` dan `postMedia` ke `POST /api/v1/media/{action}` selesai di Integrasi M2 (endpoint sebenarnya `/media/play-pause|next|prev`). Lihat `[Frontend M2] Repository media mock sebagai default` dan `[Integrasi M2]` di decision-log.
- [ ] Now playing (judul lagu) di layar Remote; masuk stretch.
- [ ] Status play asli dari laptop belum ada di API; app menganggap lagu sedang jalan saat dibuka. Lihat `[Frontend M2] Status play, optimistic, dan tap ulang`.
- [x] Polling dan lifecycle app untuk dock media (berhenti saat background) dikerjakan di M6. Diselesaikan di Frontend M6: pause dan resume di `RemoteScreen`.
- [ ] Haptic press tetap berbunyi saat tap diabaikan karena play sedang diproses (perilaku `Pressable` semua tombol). Cek rasanya di `docs/todo/waiting.md` M2; ubah bila terasa mengganggu.

## M3 Volume

- [ ] Konstanta artboard tanpa token di `volume_panel.dart` dan `volume_slider.dart` (badge 28 dp, inset 18, handle 5×24, ambang 6%, ikon 14/20/22, gap 10/6, lebar tombol −/+ 72) perlu token di `design/tokens.json`.
- [ ] `GlassKey` tidak mengisi lebar slot flex (`Pressable` membungkus `Center`), jadi tombol Mute tidak selebar slot dan tombol −/+ jadi 56 dp, bukan kapsul 72×56 dari artboard. Perlu parameter lebar di primitif.
- [ ] Hint `hintWaiting` juga tampil saat `known=false` di fase online (keputusan sementara T5; desain untuk volume `null` belum ada).
- [ ] Hint saat `tokenRejected` mengikuti prioritas state; layar sudah diarahkan ke Q12, jadi tidak tampil lama.
- [ ] Komentar dokumentasi `pause` di `app/lib/ui/r_icons_data.dart` (~76–78) tertukar tempat setelah ikon volume disisipkan; pindahkan ke ikon `pause`. SARAN reviewer M3.
- [ ] Literal `strokeWidth: 2.4` di `app/lib/features/remote/widgets/volume_panel.dart` (~187, ~205) belum jadi konstanta atau token. SARAN reviewer M3.
- [ ] Balasan telat setelah timeout 3 dtk bisa menimpa `confirmed` (`volume_controller.dart` ~260–271, `volume_sender.dart` ~145). Perlu token per percobaan. SARAN reviewer M3.
- [ ] Semantics increase di 100 atau decrease di 0 tidak membuka mute walau laptop sedang bisu (`volume_controller.dart` `_step` ~333–340). Perlu keputusan produk. SARAN reviewer M3.
- [ ] `_retrySlider` di `volume_controller.dart` (~288) tidak mengecek dragging dan fase koneksi. SARAN reviewer M3.
- [ ] Haptic detent untuk tap-lompat slider belum ada (sengaja, tap hanya memindah nilai). Lihat `[Frontend M3] Haptic dikelola controller` di `docs/decision-log.md`. Di luar lingkup M3.
- [x] Polling dan lifecycle app (berhenti saat background, lanjut saat kembali) masuk M6. Di luar lingkup M3. Diselesaikan di Frontend M6.
- [ ] `HttpVolumeRepository` dan `volumeRepositoryProvider` asli masuk Integrasi M3. Lihat `[Frontend M3] Fake volume di test/support, provider tanpa default`.
- [ ] Golden test panel volume belum dibuat; pengecekan terang dan gelap memakai widget test. Di luar lingkup M3.
- [ ] Ambang layar pendek 700 dp dan `_shortHeight` perlu dicek di HP nyata.

## M4 Daya

- [ ] Notifikasi lokal selama hitung mundur saat app di background (`docs/prd.md` bagian 6)
- [x] T3/T10 PowerRow di 360 dp: label tombol daya pecah di tengah kata. Diperbaiki di Frontend M4 dengan padding label 4 dp untuk `GlassKeySize.power` (lihat `[Frontend M4] Padding label tombol daya 4 dp`). Ukuran nyata di HP dicek di `docs/todo/waiting.md` bagian M4.
- [x] T11 SARAN: poll yang sudah berjalan saat Batal dikirim bisa membawa `pending` lama. Diperbaiki di Frontend M4: batal yang berhasil mengisi `_dismissedKey` (lihat `[Frontend M4] Penjaga _dismissedKey dan P11 yang habis`).
- [ ] T10 Scheduling: tidak ada copy atau tampilan untuk status "mengirim perintah" (3 dtk). Route hitung mundur terbuka tetapi kosong (`CountdownScreen` tidak menggambar apa pun saat `PowerFlowScheduling`), jadi Remote tetap terlihat di belakang dan `PowerRow` nonaktif. Perlu keputusan desain.
- [ ] S02 saat app dibuka dengan jadwal berjalan: Remote tampil dulu sebelum P13 terpasang, sampai sekitar 2 dtk. Terkait `docs/todo/frontend.md` M6 (S02 dengan batas 2 dtk). SARAN Reviewer M4. Tampilan S02 selama polling pertama sesuai `design/scope-and-flows.md` baris 51 dan 70, tetapi batas 2 dtk untuk startup belum dibuktikan (M6 hanya menguji resume).
- [ ] Token ukuran dan warna daya belum ada di `design/tokens.json`: tombol "Nggak jadi" 64 dp, Batal 80 dp, ikon 56 dan 80 dp, handle, `neutralIcon`, `countBg`, `status.danger` dan `onDanger` di `StatusTokens`, `_keyGap` 10, dan `_powerIconSize` 17. Lihat `[Frontend M4] Warna bahaya dari ColorScheme dan status tokens`. SARAN Reviewer M4.
- [ ] `Pressable` belum punya `focusNode` dan `autofocus`, jadi tombol Batal di hitung mundur belum bisa dipilih dengan keyboard (Enter). SARAN Reviewer M4.
- [ ] Tombol full-width bersama di `lib/ui/` belum ada: `_SheetButton`, `_ResultButton`, dan tombol countdown masih privat dan mirip satu sama lain. SARAN Reviewer M4.
- [ ] `UnreachableFailure` belum membedakan gagal connect dari putus di tengah request (`lib/core/network/agent_http_client.dart`). Berlaku juga untuk daya. SARAN Reviewer M4.
- [ ] `_startTest` di pairing (`catch (_)`) memetakan semua error ke timeout Q10, sehingga kegagalan setup tersamar. SARAN Reviewer M4.
- [ ] Sebagian (Integrasi M4): komentar di `OfflineContent._poweredOffBody` sudah dikoreksi, tetapi cabang `restart` belum dihapus karena restart tidak masuk P15. Hapus cabang atau tandai nanti (lihat `[Frontend M4] Restart tidak masuk P15`). SARAN Reviewer M4.
- [x] `Duration(seconds: 1)` di tick controller hitung mundur belum punya komentar sumber sesuai aturan. SARAN Reviewer M4. Diselesaikan di Integrasi M4 (komentar sumber ditambahkan).

## M5 Pengaturan & Tema

- [ ] Token pemisah baris grup belum ada di `design/tokens.json`. `SettingsGroup` memakai `glass.lowlight` (ink 6%), sedangkan artboard `Settings-light` memakai `line` 1px ink 8%. Tambah token `divider` di desain lalu regenerasi.
- [ ] `Pressable` selalu memberi `button: true` ke Semantics. Baris info di `SettingsRow` karena itu memakai Semantics biasa. Pertimbangkan parameter `isButton` di `Pressable` agar satu jalur saja.
- [ ] `ThemeSegmented` memakai `Row` dengan `crossAxisAlignment: stretch` dan gagal layout (tinggi tak terbatas) bila diletakkan langsung di `Column` dalam scroll. Saat ini pemanggil (`SettingsScreen`) membungkusnya dengan `IntrinsicHeight`. Perbaiki di komponen agar aman di layout apa pun. Sampai diperbaiki, pemanggil baru wajib membungkus dengan `IntrinsicHeight` (lihat `docs/todo/modules/M5-pengaturan-tema.md`).
- [ ] Token `RMotion` khusus crossfade tema belum ada. Crossfade 200 ms saat ini memakai `RMotion.toast`. Tambah token di desain lalu regenerasi.
- [ ] Toast gagal hapus pairing memakai `RemoteStrings.toastCommandFailed` sementara. Desain belum punya copy untuk kasus ini. Tambah copy khusus di `app/lib/core/strings/`.
- [ ] `ThemeSegmented` masih memakai warna literal `strokeWidth 2.5` dan fallback `Colors.black`. Ganti dengan konstanta bernama. SARAN Reviewer M5.
- [ ] Versi app belum ditampilkan di Pengaturan karena desain R01 belum punya baris versi. Tambah bila desain menambahkannya.
- [ ] Status "NYAMBUNG" dan "NGGAK KEJANGKAU" ada di `SettingsStrings` dan `RemoteStrings`. Gabungkan jadi satu sumber.
- [ ] `flutter analyze` belum diuji di mesin lain untuk kode Swift iOS (`app/ios/Runner/AppDelegate.swift`). Lihat `docs/todo/waiting.md` M5.

## M6 Ketahanan & Startup

Belum ada temuan.

## Stretch

Hanya dikerjakan kalau pemilik menyebutnya.

- [ ] Now playing (judul lagu) di layar Remote
- [ ] Widget homescreen
- [ ] Multi-laptop di satu app
