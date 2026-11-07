# Frontend (app Flutter)

Semua task memakai mock repository dengan bentuk respons persis `docs/api-spec.md`.

## M0 Fondasi Proyek

- [x] Jalankan `flutter create` di `app/` dengan org dan nama Remotto, Android + iOS, portrait saja
- [x] Tambah package dari `docs/technical-spec.md` bagian 4
- [x] Buat `tool/generate_tokens.dart` dan hasilkan `lib/core/theme/tokens.g.dart`
- [x] Bundel Geist dan Geist Mono beserta file lisensinya
- [x] Render ikon app gelap dan terang dari SVG inline di `design/export/artboards/Logo.dc.html`
- [x] Buat `ThemeData` terang/gelap: `ColorScheme`, `TextTheme`, semua `ThemeExtension`, `NoSplash`
- [x] Buat `RSpace`, `RRadius`, `RSize`, `RMotion`, `RBehavior`
- [x] Buat helper reduced motion dan `GlassMode`
- [x] Buat `RHaptics` dan file string
- [x] Buat provider storage dan preferences (tema, haptic)
- [x] Buat `go_router` dengan rute Pairing, Remote, Pengaturan, dan rute awal berdasarkan data pairing
- [x] Atur perilaku tombol back sesuai `design/scope-and-flows.md`
- [x] Buat primitif `Pressable`, `GlassPanel`, `GlassKey` + widget test
- [x] Buat latar cahaya statis

## M1 Pairing & Koneksi

- [x] Buat validator payload QR dan input manual + unit test
- [x] Buat `PairingRepository` dan mock
- [x] Buat `ConnectionController` sesuai mesin status `docs/technical-spec.md` bagian 5 + unit test
- [x] Buat `PairingScaffold`
- [x] Layar Q01 intro dan Q02 izin kamera
- [x] `QrViewfinder` dan Q03 scan, senter, Q04 QR tidak valid
- [x] Q05 izin ditolak permanen
- [x] `GlassTextField`, Q06, Q07 input manual
- [x] `StepProgressList`, Q08, Q09, Q10, Q11
- [x] Q12 token ditolak dari layar mana pun
- [x] `StatusPill` semua variant
- [x] Kerangka SCR-010 dengan header dan state S01, S02, S10, S11
- [x] `OfflineContent` dengan "Coba lagi" dan "Pairing ulang"
- [x] `GlassToast` dan `ToastHost`
- [x] Widget test semua primitif baru, termasuk Semantics

## M2 Kontrol Media

- [x] Buat `MediaRepository` dan mock (200, 401, 500, timeout)
- [x] `PlayKey` dengan optimistic, cincin proses, tap ulang diabaikan
- [x] Dock media dengan prev/next, kedip ikon 240 ms
- [x] State S03 dan S04 dengan toast "Ulangi"
- [x] Kontrol nonaktif saat offline dan menyambung
- [x] Layout 360 dp dan 412 dp
- [x] Widget test + Semantics

## M3 Volume

- [x] Buat `VolumeRepository` dan mock
- [x] `VolumeSlider` kustom: tap, drag, rollback, state muted dan disabled
- [x] Pengirim nilai dengan throttle 100 ms dan satu request berjalan + unit test
- [x] `VolumeReadout` dengan hint per state
- [x] Tombol mute dan −/+
- [x] State S05 sampai S09
- [x] Offline saat drag: gesture dibatalkan
- [x] Sinkron nilai dari polling kecuali saat ditarik
- [x] Layar pendek dan S12
- [x] Widget test + Semantics slider

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
