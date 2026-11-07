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
- [ ] T15 OfflineContent: body untuk keadaan "Laptop lagi mati" belum ada di desain. Artboard hanya mengganti judul dan ikon, tetapi body "lagi nyala" bertentangan dengan keadaan itu. Perlu copy dari M4 (P15).
- [ ] T7 `_startTest` (Q08): cek `attempt` sebelum `save` supaya "Batal" saat penyimpanan berjalan tidak lanjut ke Q09. Ditemukan Reviewer.
- [ ] T7 PairingScaffold: margin Q08 24 dp, sedangkan PairingScaffold memakai 20 dp. Perlu keputusan nilai yang dipakai.
- [ ] T8 pesan error host di luar rentang (contoh 8.8.8.8, IP publik) masih memakai pesan Q07 yang sama. Perlu keputusan copy khusus dari desain.
- [ ] T8 Android `permission_handler` tidak mengembalikan permanentlyDenied lewat status: Q01 ke Q02, lalu Q05 setelah request. Perlu keputusan cara deteksi izin permanen di Android.
- [ ] T12 GlassTextField: ikon mata token memakai `eye`; ikon `eye-off` belum ada di artboard dan tidak dibuat. Perlu keputusan desain bila ingin ikon kedua.
- [ ] Komentar Indonesia tersisa di file M0: `lib/ui/r_haptics.dart`, `lib/core/storage/*`, `lib/core/theme/*`, `lib/ui/glass_panel.dart`, `lib/ui/light_backdrop.dart`, `lib/ui/pressable.dart`, `lib/core/router/route_transitions.dart`, `lib/app.dart`. Ditemukan Reviewer.

## M2 Kontrol Media

Belum ada temuan.

## M3 Volume

Belum ada temuan.

## M4 Daya

- [ ] Notifikasi lokal selama hitung mundur saat app di background (`docs/prd.md` bagian 6)

## M5 Pengaturan & Tema

Belum ada temuan.

## M6 Ketahanan & Startup

Belum ada temuan.

## Stretch

Hanya dikerjakan kalau pemilik menyebutnya.

- [ ] Now playing (judul lagu) di layar Remote
- [ ] Widget homescreen
- [ ] Multi-laptop di satu app
