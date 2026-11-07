# Frontend (app Flutter)

Semua task memakai mock repository dengan bentuk respons persis `docs/api-spec.md`.

## M0 Fondasi Proyek

- [ ] Jalankan `flutter create` di `app/` dengan org dan nama Remotto, Android + iOS, portrait saja
- [ ] Tambah package dari `docs/technical-spec.md` bagian 4
- [ ] Buat `tool/generate_tokens.dart` dan hasilkan `lib/core/theme/tokens.g.dart`
- [ ] Bundel Geist dan Geist Mono beserta file lisensinya
- [ ] Render ikon app gelap dan terang dari SVG inline di `design/export/artboards/Logo.dc.html`
- [ ] Buat `ThemeData` terang/gelap: `ColorScheme`, `TextTheme`, semua `ThemeExtension`, `NoSplash`
- [ ] Buat `RSpace`, `RRadius`, `RSize`, `RMotion`, `RBehavior`
- [ ] Buat helper reduced motion dan `GlassMode`
- [ ] Buat `RHaptics` dan file string
- [ ] Buat provider storage dan preferences (tema, haptic)
- [ ] Buat `go_router` dengan rute Pairing, Remote, Pengaturan, dan rute awal berdasarkan data pairing
- [ ] Atur perilaku tombol back sesuai `design/scope-and-flows.md`
- [ ] Buat primitif `Pressable`, `GlassPanel`, `GlassKey` + widget test
- [ ] Buat latar cahaya statis

## M1 Pairing & Koneksi

- [ ] Buat validator payload QR dan input manual + unit test
- [ ] Buat `PairingRepository` dan mock
- [ ] Buat `ConnectionController` sesuai mesin status `docs/technical-spec.md` bagian 5 + unit test
- [ ] Buat `PairingScaffold`
- [ ] Layar Q01 intro dan Q02 izin kamera
- [ ] `QrViewfinder` dan Q03 scan, senter, Q04 QR tidak valid
- [ ] Q05 izin ditolak permanen
- [ ] `GlassTextField`, Q06, Q07 input manual
- [ ] `StepProgressList`, Q08, Q09, Q10, Q11
- [ ] Q12 token ditolak dari layar mana pun
- [ ] `StatusPill` semua variant
- [ ] Kerangka SCR-010 dengan header dan state S01, S02, S10, S11
- [ ] `OfflineContent` dengan "Coba lagi" dan "Pairing ulang"
- [ ] `GlassToast` dan `ToastHost`
- [ ] Widget test semua primitif baru, termasuk Semantics

## M2 Kontrol Media

- [ ] Buat `MediaRepository` dan mock (200, 401, 500, timeout)
- [ ] `PlayKey` dengan optimistic, cincin proses, tap ulang diabaikan
- [ ] Dock media dengan prev/next, kedip ikon 240 ms
- [ ] State S03 dan S04 dengan toast "Ulangi"
- [ ] Kontrol nonaktif saat offline dan menyambung
- [ ] Layout 360 dp dan 412 dp
- [ ] Widget test + Semantics

## M3 Volume

- [ ] Buat `VolumeRepository` dan mock
- [ ] `VolumeSlider` kustom: tap, drag, rollback, state muted dan disabled
- [ ] Pengirim nilai dengan throttle 100 ms dan satu request berjalan + unit test
- [ ] `VolumeReadout` dengan hint per state
- [ ] Tombol mute dan −/+
- [ ] State S05 sampai S09
- [ ] Offline saat drag: gesture dibatalkan
- [ ] Sinkron nilai dari polling kecuali saat ditarik
- [ ] Layar pendek dan S12
- [ ] Widget test + Semantics slider

## M4 Daya

- [ ] Buat `PowerRepository` dan mock (202, 200, 409, 500, timeout)
- [ ] `PowerRow`
- [ ] `ConfirmSheet` dengan route kustom: P01, P02, P06, tahap 1→2 crossfade
- [ ] `HoldToConfirm`: P03, P04, P05, custom action screen reader
- [ ] `CountdownScreen`: P07, P12 reduced motion, wakelock, back = Batal
- [ ] `ResultScreen`: P09, P10
- [ ] P08 dengan toast
- [ ] P11 batal gagal, termasuk kasus timeout ambigu
- [ ] P13 lanjut hitung mundur dan P14 telat batal
- [ ] P15 varian offline "Laptop lagi mati" dan `lastPowerCommand`
- [ ] Teks "dari HP ini" hanya bila `lastPowerCommand` ada
- [ ] Polling cepat setelah restart
- [ ] Unit test semua cabang hasil daya, widget test + Semantics

## M5 Pengaturan & Tema

- [ ] `SettingsGroup` dan `SettingsRow`
- [ ] `ThemeSegmented` dan `GlassSwitch`
- [ ] SCR-020 R01, R02, R03, R05, tanpa baris lisensi
- [ ] R06 fallback solid
- [ ] `SimpleConfirmSheet` dan R04, stack diganti ke Q01
- [ ] Platform channel iOS untuk reduce transparency
- [ ] Widget test + Semantics

## M6 Ketahanan & Startup

- [ ] Polling berhenti saat background dan langsung jalan saat resume
- [ ] S02 saat resume dengan batas 2 detik
- [ ] Konsistensi timeout semua repository
- [ ] Pemantauan waktu raster untuk `GlassMode`
- [ ] Unit test siklus hidup
