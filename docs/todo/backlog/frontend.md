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

Belum ada temuan.

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
