# Komponen

Semua komponen kustom, bukan widget Material default. Token merujuk `tokens.json`.

⚠ = butuh a11y manual + pengujian lanjutan di perangkat.

## Ringkasan

| ID | Komponen | Dipakai di | ⚠ |
| --- | --- | --- | --- |
| C01 | GlassPanel | semua layar | |
| C02 | GlassKey | Remote, Pengaturan, Pairing | |
| C03 | PlayKey | Remote | ⚠ |
| C04 | VolumeSlider | Remote | ⚠ |
| C05 | VolumeReadout | Remote | |
| C06 | StatusPill | Remote | |
| C07 | GlassToast | Remote, setelah batal | ⚠ |
| C08 | OfflineContent | Remote | |
| C09 | PowerRow | Remote | |
| C10 | Layout Remote | Remote | |
| C11 | ConfirmSheet | Konfirmasi daya | ⚠ |
| C12 | HoldToConfirm | Konfirmasi daya | ⚠ |
| C13 | CountdownScreen | Konfirmasi daya | ⚠ |
| C14 | ResultScreen | Konfirmasi daya | |
| C15 | PairingScaffold | Pairing, error | |
| C16 | QrViewfinder | Pairing | ⚠ |
| C17 | GlassTextField | Pairing manual | |
| C18 | StepProgressList | Tes koneksi | |
| C19 | SettingsGroup + Row | Pengaturan | |
| C20 | ThemeSegmented | Pengaturan | |
| C21 | GlassSwitch | Pengaturan | |
| C22 | SimpleConfirmSheet | Pengaturan | |

---

## C01 GlassPanel

- **Tujuan:** permukaan kaca untuk panel volume, dock media, pill, toast.
- **Anatomi:** clip radius → blur latar → isi tint → garis tepi 1 dp → highlight dalam atas → bayangan lembut.
- **Variant:** panel (`radius.lg`), dock (`radius.full`), pill (`radius.full`, tinggi 28), toast (`radius.sm`, `glass.toast`).
- **State:** default · reduce transparency (`glass.solid`) · fallback perangkat lemah (solid, tanpa blur).
- **Token:** `glass.fill`, `glass.edge`, `glass.highlight`, `glass.lowlight`, `glass.shadow`, `component.glassPanel.*`.
- **Perilaku:** maksimal 1 lapis blur per area; isi panel memakai C02 chip.
- **Semantics:** container. Panel volume = grup "Volume", dock = grup "Media".
- **Flutter:** `ClipRRect` + `BackdropFilter(ImageFilter.blur)` + `DecoratedBox`. Token di `ThemeExtension<GlassTokens>`.

## C02 GlassKey

- **Tujuan:** tombol kapsul untuk daya, mute, −/+, pengaturan, prev/next, aksi sekunder.
- **Anatomi:** kapsul → ikon 17–22 dp → label opsional (`typography.label`).
- **Variant:** `glass` (berdiri sendiri, blur), `chip` (dalam panel), `ghost` (dalam dock), `strong` (isi `fg.primary`, untuk aksi utama non-aksen). Ukuran 48 / 52 / 56 / 64 / 80.
- **State:**
  - default;
  - pressed: skala `component.key.pressedScale`, `glass.chipPressed`;
  - disabled: `fg.disabled` + `glass.chipDisabled` + alasan tertulis di layar;
  - focus: ring 3 dp `accent.text`.
- **Perilaku:** haptic saat jari turun, aksi saat dilepas di dalam area. Label boleh 2 baris.
- **Semantics:** button + label aksi ("Volume naik 5"). Mute = toggle (`toggled`).
- **Flutter:** widget kustom: `GestureDetector` + `AnimatedScale` + `Semantics(button: true)`.

## C03 PlayKey ⚠

- **Tujuan:** satu-satunya elemen aksen penuh; toggle play/pause.
- **Anatomi:** lingkaran gradient `accent.highlight` → `accent.default`, ikon 36 dp `accent.on`, cincin proses opsional `accent.text` 3 dp.
- **Ukuran:** `size.play` (≥390 dp) / `size.playCompact` (360 dp).
- **State:** playing · paused · processing (cincin muncul setelah `duration.processingHint`) · disabled · focus.
- **Perilaku:**
  - Optimistic: ikon langsung berganti saat tap.
  - Tap ulang selama proses diabaikan sampai ada respons atau `duration.commandTimeout`.
  - Gagal → ikon kembali + C07.
- **Semantics:** "Putar" / "Jeda"; saat proses diberi hint "Ngirim ke laptop".
- **Catatan:** status play bukan status asli laptop (now playing di luar scope). Prev/next memberi umpan balik dengan kedip ikon 1× 240 ms + haptic.

## C04 VolumeSlider ⚠

- **Anatomi:** track kapsul `size.track` (menjadi `size.trackActive` saat ditarik) → isi `slider.fill` → handle 5×24 dp (disembunyikan di bawah 7%).
- **State:** idle · dragging · rollback · muted (isi `fg.disabled`) · disabled (offline).
- **Perilaku:**
  - Tap di track = loncat ke nilai. Drag horizontal; drag vertikal diabaikan.
  - Step `component.volumeSlider.step`.
  - Kirim nilai setiap `component.volumeSlider.sendThrottle` + nilai akhir saat dilepas.
  - Haptic `selectionClick` setiap 5%, `mediumImpact` di 0/100.
  - Menggeser saat mute = otomatis unmute.
  - Gagal → animasi kembali ke nilai laptop (`component.volumeSlider.rollback`).
  - Offline saat drag → gesture dibatalkan, slider kembali ke nilai terakhir.
- **Semantics:** slider dengan value "35 persen". `onIncrease`/`onDecrease` = ±5. Hanya nilai akhir yang diumumkan. Alternatif aksesibel: tombol −/+ (C02).
- **Flutter:** `GestureDetector`/`RenderBox` kustom + `Semantics(slider: true, value, increasedValue, decreasedValue)`. Bukan `Slider` default.

## C05 VolumeReadout

- Angka `typography.displayVolume` (108 sp di 360 dp, 96 sp di layar pendek), tabular, dengan "%" 0.32×. Hint `typography.label`.
- **State warna:**
  - normal: `fg.primary`;
  - dragging: `accent.text`;
  - muted/disabled: `fg.secondary`.
- **Hint:** "Geser atau ketuk − / +", "Paling pelan" (0), "Paling kencang" (100), "Suara laptop lagi dibisukan", "Nunggu jawaban dari laptop…".
- **Semantics:** `excludeSemantics` (nilai sudah dibacakan oleh slider).

## C06 StatusPill

| Variant | Indikator | Label |
| --- | --- | --- |
| online | titik `status.success` | "NYAMBUNG · 3J 12M" |
| back | centang `status.success` | "NYAMBUNG LAGI", tampil 2 detik |
| connecting | cincin `status.warning` | "MENYAMBUNG…" |
| offline | ikon wifi dicoret, warna `fg.secondary` | "NGGAK KEJANGKAU" |
| off | ikon power, warna `fg.secondary` | "LAGI MATI" (P15) |

- Crossfade `duration.status`. Uptime diperbarui setiap polling; menit dibulatkan ke bawah.
- **Semantics:** `liveRegion`, mengumumkan perubahan status (bukan uptime).

## C07 GlassToast ⚠

- **Anatomi:** kaca `radius.sm`, ikon 18 dp, teks `typography.label`, aksi teks opsional.
- **Variant:**
  - error + "Ulangi": `component.toast.durationError`;
  - info: `component.toast.durationInfo`.
- **Perilaku:**
  - Hanya satu toast sekaligus; yang baru mengganti yang lama.
  - Posisi 12 dp di atas dock.
  - Timer berhenti selama disentuh; swipe-down untuk tutup.
  - Masuk/keluar `duration.toast`.
- **Semantics:** `liveRegion` (polite). Fokus tidak dipindah otomatis.
- **Flutter:** overlay kustom, bukan `SnackBar`.

## C08 OfflineContent

- Isi panel volume saat offline: ikon wifi dicoret 40 dp → judul `titleMd` → body → "Coba lagi" (C02 chip) + "Pairing ulang" (link `accent.text`).
- "Coba lagi" = polling langsung; tombol berubah jadi "Nyoba…" selama proses.
- "Pairing ulang" → C22 → Q01.
- Untuk sleep/matikan yang baru terkirim, judul menjadi "Laptop lagi mati" dengan ikon power (P15). Berlaku < 10 menit sejak perintah lokal.

## C09 PowerRow

- 3 × C02 glass dengan tinggi `size.power`: Sleep · Restart · Matikan.
- Netral, di atas layar. Tap = buka C11 (tidak ada aksi langsung).
- **Semantics:** "Sleep laptop", "Restart laptop", "Matikan laptop".

## C10 Layout Remote

- `SafeArea` → `Column`: header (nama `titleMd` + C06 + tombol Pengaturan 48) → C09 → `Expanded(C01 panel volume)` → dock media (C01 dock: prev ghost `size.media`, C03, next ghost).
- Ukuran 360 dp: `screenMarginCompact`, `playCompact`, `mediaCompact`, angka 108.
- Layar pendek (<700 dp): hint disembunyikan, angka 96.
- **Urutan fokus:** nama → status → pengaturan → Sleep → Restart → Matikan → volume → mute → − → + → prev → play → next.

## C11 ConfirmSheet ⚠

- **Anatomi:** `glass.scrim` → sheet `radius.xl` (inset `component.sheet.inset`, blur `blur.sheet`) → handle → ikon 56 + label tahap → judul `titleLg` → body → aksi.
- **Aksi:**
  - Atas: "Lanjut" (garis `status.dangerText`) atau C12.
  - Bawah: "Nggak jadi", paling besar (64) dan paling dekat jempol.
- **Konfigurasi:**
  - Sleep: 1 tahap, ikon netral, aksi `strong` "Sleep-in".
  - Restart/Matikan: tahap 1 netral; tahap 2 ikon dan aksi merah.
- **Perilaku:** tap scrim / swipe-down / back = "Nggak jadi". Tahap 1→2 crossfade di sheet yang sama. Haptic light saat terbuka.
- **Semantics:** dialog modal. Fokus ke judul saat terbuka; kembali ke tombol pemicu saat ditutup.

## C12 HoldToConfirm ⚠

- **Anatomi:** kapsul `component.holdToConfirm.height`, garis `status.dangerText`, latar `status.dangerSoft`; isi `status.danger` maju dari kiri; ikon + label ("Tahan buat matiin" / "Tahan buat restart"); hint di bawah.
- **State:**
  - idle: "Tahan sampai penuh, sekitar 1 detik";
  - holding: "Terus tahan…" (label berubah ke `status.onDanger` setelah 55%);
  - released early: isi mundur `component.holdToConfirm.rewind`, hint tebal "Kelepasan. Tahan sampai penuh ya.";
  - complete: masuk C13.
- **Perilaku:** durasi `component.holdToConfirm.duration` linear. Jari keluar area = reset. Haptic selection di 50%, heavy di 100%.
- **Semantics:** label + "tahan". Double-tap-tahan TalkBack/VoiceOver didukung. Custom action "Matikan sekarang" / "Restart sekarang" langsung masuk C13, sehingga hitung mundur tetap jadi pengaman.

## C13 CountdownScreen ⚠

- **Anatomi:** overlay penuh → nama laptop (`caption`) → judul ("Laptop mati dalam" / "Laptop restart dalam" / "Laptop tidur dalam") → cincin `component.countdown.ring` dengan angka `displayCountdown` → teks bantu → "Batal" (`component.countdown.cancelHeight`, variant strong).
- **Warna cincin:** `status.danger` untuk restart/shutdown, `accent.text` untuk sleep.
- **State:**
  - berjalan;
  - batal terkirim → Remote + toast;
  - batal gagal → peringatan + "Batal lagi" (P11);
  - reduced motion → 5 segmen statis;
  - dibuka di tengah jalan (P13) → mulai dari sisa `remainingMs` dibulatkan ke atas, cincin langsung di posisinya, label "Dijadwalkan N detik lalu".
- **Perilaku:**
  - Saat mulai, app mengirim perintah "jadwalkan" ke agent; gagal → C14 gagal.
  - Back sistem = Batal.
  - Wakelock selama hitung mundur.
- **Semantics:** `alertdialog`. Umumkan di awal dan di 3 dan 1. Fokus langsung ke Batal.
- **Flutter:** route full-screen non-opaque, `PopScope` → batal.

## C14 ResultScreen

- Ikon 80 → judul `titleLg` → body → aksi utama 64 (+ "Tutup").
- Varian:
  - Terkirim matikan/sleep → "Oke" ke Remote (offline, "Laptop lagi mati").
  - Restart → Remote dengan polling cepat 2 detik.
  - Gagal dijadwalkan → "Coba lagi" (kembali ke tahap 2) + "Tutup".
  - Telat batal (P14) → "Udah telat buat batal" + "Oke", tanpa Batal.
- Judul diumumkan.

## C15 PairingScaffold

- Back opsional → ikon 80 / mark → kicker `caption` → judul `titleXl` → body → tips opsional (grup kaca bernomor) → aksi utama 64 (aksen) + link.
- Satu aksi aksen per layar, selalu di bawah. Judul diumumkan dan menjadi fokus awal.

## C16 QrViewfinder ⚠

- Preview kamera penuh (selalu gelap di dua tema).
- Bingkai 4 sudut 248 dp, warna `fg.primary` (gelap). Menjadi `accent.text` sesaat saat QR salah.
- Hint, banner C07, tombol back, senter, dan "Isi manual".
- Auto-detect tanpa tombol jepret. QR yang sama diabaikan selama 2 detik. Terbaca → haptic medium → Q08.
- **Flutter:** paket scanner (usulan `mobile_scanner`, lisensi belum diverifikasi) + `CustomPaint` untuk bingkai.

## C17 GlassTextField

- Label 14 di atas → field 56 dp `radius.sm`, teks mono → aksi kanan opsional (lihat token) → pesan bantuan/error.
- Field alamat memakai keyboard url. Field token tanpa autocorrect, huruf kapital otomatis, boleh tempel.
- **State:** kosong · fokus (garis `accent.text`) · terisi · error (garis + ikon + pesan `accent.text`) · nonaktif.
- Validasi saat field ditinggal atau saat submit. Format alamat: `IPv4[:port]`; port default diasumsikan 8765.
- **Semantics:** label terhubung ke field; error dibacakan bersama label.

## C18 StepProgressList

- Grup kaca; setiap baris 56 dp: ikon status + teks.

| State | Ikon | Warna |
| --- | --- | --- |
| done | centang | `status.success` |
| active | cincin | `status.warning` |
| todo | titik kosong | `fg.disabled` |

- Langkah: "Laptop ketemu" → "Cek token" → "Simpan sambungan". Maksimal 5 detik per langkah.
- **Semantics:** `liveRegion`, mengumumkan langkah aktif.

## C19 SettingsGroup + Row

- Caption kapital di atas → grup kaca `radius.md` → baris minimal 56 dp.
- Varian baris: info (nilai kanan), aksi (teks `accent.text`), navigasi (chevron), switch.
- Seluruh baris bisa ditekan. Satu node Semantics per baris.

## C20 ThemeSegmented

- Track kapsul `control.segTrack` → 3 segmen ≥ 48 dp: Terang / Gelap / Sistem.
- Segmen aktif: `control.segOn` + centang + semibold.
- Langsung berlaku (`ThemeMode`), crossfade 200 ms; reduced motion = instan.
- **Semantics:** radiogroup "Tema".

## C21 GlassSwitch

- Track 60×36 → thumb 28 dengan ikon centang (on) / strip (off).
- Warna: on `accent.default`, off `control.switchOff`.
- Tap seluruh baris = toggle.
- **Semantics:** switch "Getar saat ditekan".

## C22 SimpleConfirmSheet

- Konfigurasi C11 satu tahap tanpa ikon: "Pairing ulang?" → "Hapus & pairing ulang" (strong) + "Nggak jadi".
- Setelah hapus: token dihapus, stack navigasi diganti ke Q01.

---

## Pemetaan token ke Flutter (konseptual)

```dart
// Warna peran standar → ColorScheme
final light = ColorScheme(
  brightness: Brightness.light,
  primary: t.light.accent.default_,      // accent.default
  onPrimary: t.light.accent.on,          // accent.on
  secondary: t.light.accent.text,        // accent.text
  onSecondary: t.light.bg.base,
  error: t.light.status.danger,          // status.danger
  onError: t.light.status.onDanger,
  surface: t.light.bg.base,              // bg.base
  onSurface: t.light.fg.primary,         // fg.primary
  onSurfaceVariant: t.light.fg.secondary,
);

// Peran di luar ColorScheme → ThemeExtension (dua instance: light & dark)
@immutable
class GlassTokens extends ThemeExtension<GlassTokens> {
  final Color fill, edge, highlight, lowlight, shadow, chip, chipPressed,
      chipDisabled, solid, sheet, toast, scrim, glowA, glowB;
  final double blur, sheetBlur;
  // copyWith + lerp …
}

@immutable
class StatusTokens extends ThemeExtension<StatusTokens> {
  final Color success, warning, dangerText, dangerSoft;
  // copyWith + lerp …
}

MaterialApp(
  themeMode: settings.themeMode, // ThemeMode.system / light / dark
  theme: ThemeData(colorScheme: light, textTheme: remottoText, extensions: [glassLight, statusLight]),
  darkTheme: ThemeData(colorScheme: dark, textTheme: remottoText, extensions: [glassDark, statusDark]),
);
```

- Tipografi → `TextTheme`: `displayLarge` = displayVolume, `displayMedium` = displayCountdown, `headlineSmall` = titleXl, `titleLarge` = titleLg, `titleMedium` = titleMd, `bodyLarge` = body, `labelLarge` = label, `labelSmall` = caption.
- Spacing, radius, size, durasi, easing → konstanta (`abstract final class RSpace`, `RRadius`, `RSize`, `RMotion`) atau `ThemeExtension<LayoutTokens>`.
- Alpha: `Color(hex).withValues(alpha: alpha)`; blur: `ImageFilter.blur(sigmaX: blur / 2, sigmaY: blur / 2)` (perlu disetel di perangkat).
- **Potensi tabrakan nama:**
  - `error` di ColorScheme = `status.danger`, padahal error form memakai `accent.text`. Jangan pakai `colorScheme.error` untuk error form.
  - `surface` = `bg.base`, bukan kaca.
  - Hindari `primaryContainer`/`surfaceTint` bawaan (tint Material 3 dimatikan: `surfaceTintColor: Colors.transparent`).
