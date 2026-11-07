# Design System — Implementasi Flutter

Status dokumen: **draft Gate 2**. Dokumen ini menerjemahkan `design/` ke Flutter dan tidak menduplikasi nilai token.

Urutan sumber kebenaran kalau ada perbedaan:

1. `design/tokens.json` untuk nilai.
2. `design/components.md` dan `design/screens.md` untuk perilaku.
3. `design/export/artboards/` untuk susunan dan copy persis.

Artboard kadang memakai nilai lokal yang sedikit berbeda dari token, misalnya radius toast dan warna dalam cincin hitung mundur. Nilai token yang dipakai.

## 1. Principles & personality

Warm Liquid Glass: kaca hangat di atas cahaya lampu kamar, dengan satu bola oranye yang menandai hal terpenting. Terasa solid dan bisa ditebak.

| Prinsip | Bentuk di kode |
|---|---|
| Satu ketukan, satu hasil | Media dan volume tanpa dialog dan tanpa scroll |
| Jempol dulu | Aksi tersering di 45% bawah; daya di atas |
| Oranye cuma satu tempat | Maksimal satu elemen beraksen penuh per layar |
| Bahaya muncul saat perlu | Warna `status.danger*` hanya di tahap 2, hitung mundur, dan hasil gagal daya |
| Status tidak cuma warna | Setiap state punya ikon + teks; disabled punya penjelasan |
| Kaca tidak mengorbankan keterbacaan | Teks lulus 4.5:1 di titik terang; ada fallback solid |
| Terasa ditekan | Kapsul mengecil, makin opak, haptic < 100 ms |

### Anti-pattern

1. Tampilan default Material: FAB, ripple, `AppBar`, `Slider`, `SnackBar`, `SegmentedButton`, `Switch`, `AlertDialog`.
2. Package UI kit dalam bentuk apa pun (§11).
3. Kaca bertumpuk: lebih dari satu lapis blur per area.
4. Gradient ungu-biru, neon, blob warna-warni.
5. Hardcode warna atau ukuran di widget fitur.
6. Tombol shutdown di zona jempol, atau merah di layar utama.
7. Skeuomorph 2010.
8. Copy kaku, atau spinner tanpa teks.
9. Putih murni di atas hitam murni pada mode gelap.
10. Error form memakai merah; error form memakai `accent.text`.

## 2. Color tokens

Key terang dan gelap identik, jadi setiap nama selalu punya dua nilai.

### Pemetaan ke `ColorScheme`

| `ColorScheme` | Token |
|---|---|
| `primary` / `onPrimary` | `accent.default` / `accent.on` |
| `secondary` | `accent.text` |
| `onSecondary` | `bg.base` |
| `error` / `onError` | `status.danger` / `status.onDanger` |
| `surface` / `onSurface` | `bg.base` / `fg.primary` |
| `onSurfaceVariant` | `fg.secondary` |

Peringatan:

- `colorScheme.error` bukan untuk error form.
- `surface` adalah latar, bukan kaca.
- `surfaceTint` dimatikan.

### `ThemeExtension`

| Extension | Isi |
|---|---|
| `GlassTokens` | `glass.*` |
| `AccentTokens` | `accent.highlight`, `accent.shadow`, `accent.text` |
| `StatusTokens` | `status.success`, `status.warning`, `status.dangerText`, `status.dangerSoft` |
| `ControlTokens` | `slider.*`, `control.*`, `fg.disabled` |
| `BackdropTokens` | `bg.glowA`, `bg.glowB` |

Warna status: online `status.success`, menyambung `status.warning`, offline dan "lagi mati" `fg.secondary`. Bahaya memakai `status.danger`, `status.dangerText`, dan `status.dangerSoft`.

Setiap extension mengimplementasikan `copyWith` dan `lerp` agar pergantian tema bisa crossfade.

## 3. Typography

- Font dibundel di `app/assets/fonts`: Geist dan Geist Mono, bobot sesuai `primitive.fontWeight`. Berkas lisensi OFL ikut dibundel.
- Geist untuk UI, Geist Mono untuk semua angka, alamat, dan token.
- Angka memakai `FontFeature.tabularFigures()`.

| Token | `TextTheme` |
|---|---|
| `displayVolume` | `displayLarge` |
| `displayCountdown` | `displayMedium` |
| `titleXl` | `headlineSmall` |
| `titleLg` | `titleLarge` |
| `titleMd` | `titleMedium` |
| `body` | `bodyLarge` |
| `label` | `labelLarge` |
| `caption` | `labelSmall` |

Konversi: `height = lineHeight / fontSize`; `letterSpacing = em × fontSize`.

Teks besar:

- Semua teks mengikuti `textScaler`.
- `displayVolume` dan `displayCountdown` dikunci maksimal 1.3×.
- Label tombol boleh dua baris dan tinggi tombol ikut bertambah.
- Nama laptop di Remote ellipsis satu baris; di Pengaturan dibungkus penuh.

## 4. Spacing, radius, elevation, layout

Konstanta `RSpace`, `RRadius`, `RSize` dihasilkan dari `primitive.spacing`, `primitive.radius`, dan `primitive.size`. Nilai di luar skala dilarang.

### Lapisan

| Level | Wujud | Widget |
|---|---|---|
| g0 | Track cekung | `VolumeSlider`, track segmented |
| g1 | Chip dalam panel, tanpa blur | `GlassKey.chip` |
| g2 | Panel kaca dengan blur | `GlassPanel` |
| g3 | Tint aksen | `PlayKey` |
| g4 | Sheet dan overlay | `ConfirmSheet`, `CountdownScreen` |

### Layout

| Lebar | Margin | Play | Media | Angka |
|---|---|---|---|---|
| ≥ 390 dp, termasuk 412 | `screenMargin` | `play` | `media` | 128 sp |
| ≤ 360 dp | `screenMarginCompact` | `playCompact` | `mediaCompact` | 108 sp |

- Lebar di antara 360 dan 390 dp memakai aturan compact.
- Tinggi < 700 dp: hint volume disembunyikan, angka 96 sp. Ambang dicek di HP nyata.
- Konten di dalam safe area. Dock berada 16 dp di atas home indicator.
- Target minimal `touchMin`. Kontrol utama `play`, `media`, `control`, `hold`, `cancel`.
- Portrait saja.

## 5. Widget conventions

Semua primitif ada di `lib/ui/` dan tidak mengetahui domain.

| ID | Widget | Lokasi | ⚠ |
|---|---|---|---|
| C01 | `GlassPanel` | `ui` | |
| C02 | `GlassKey` | `ui` | |
| C03 | `PlayKey` | `ui` | ⚠ |
| C04 | `VolumeSlider` | `ui` | ⚠ |
| C05 | `VolumeReadout` | `ui` | |
| C06 | `StatusPill` | `ui` | |
| C07 | `GlassToast` + `ToastHost` | `ui` | ⚠ |
| C08 | `OfflineContent` | `features/remote` | |
| C09 | `PowerRow` | `features/remote` | |
| C10 | `RemoteScreen` | `features/remote` | |
| C11 | `ConfirmSheet` | `ui` | ⚠ |
| C12 | `HoldToConfirm` | `ui` | ⚠ |
| C13 | `CountdownScreen` | `features/power` | ⚠ |
| C14 | `ResultScreen` | `features/power` | |
| C15 | `PairingScaffold` | `features/pairing` | |
| C16 | `QrViewfinder` | `features/pairing` | ⚠ |
| C17 | `GlassTextField` | `ui` | |
| C18 | `StepProgressList` | `ui` | |
| C19 | `SettingsGroup`, `SettingsRow` | `ui` | |
| C20 | `ThemeSegmented` | `ui` | |
| C21 | `GlassSwitch` | `ui` | |
| C22 | `SimpleConfirmSheet` | `ui` | |

Pola:

- **Variant lewat enum**, mis. `GlassKeyVariant { glass, chip, ghost, strong }`. Bukan subclass, bukan package.
- **Semua interaktif dibangun di atas satu `Pressable`:** `GestureDetector` + `AnimatedScale` + `Semantics`, sehingga press, haptic, dan focus konsisten.
- **Tanpa `InkWell`.** `splashFactory` diset `NoSplash` di `ThemeData`.
- **Sheet** memakai route kustom, bukan tampilan default.
- **Toast** memakai overlay kustom, bukan `SnackBar`.
- **Baris lisensi** di artboard SCR-020 tidak dibuat (keputusan S-4).

### Semantics

- Setiap kontrol punya label aksi, mis. "Volume naik 5".
- Toggle memakai `toggled`, slider memakai `slider` + `value` + `onIncrease` + `onDecrease`.
- `liveRegion` untuk `StatusPill`, toast, dan `StepProgressList`.
- `VolumeReadout` memakai `excludeSemantics`.
- `HoldToConfirm` punya custom action "Matikan sekarang" / "Restart sekarang" yang langsung ke hitung mundur.

### Haptic

Lewat `RHaptics`, yang membaca preferensi "Getar saat ditekan". Pemetaan momen ada di `design/design-system.md`. Widget dilarang memanggil `HapticFeedback` langsung.

### Pengujian manual a11y di perangkat

Widget bertanda ⚠: C03, C04, C07, C11, C12, C13, C16. Item ini masuk `waiting.md`.

## 6. Motion

Konstanta `RMotion` dihasilkan dari `primitive.duration` dan `primitive.easing`.

| Momen | Token | Reduced motion |
|---|---|---|
| Press | `pressDown`, lepas `pressUp` + `spring` | Tanpa skala |
| Slider | Mengikuti jari; rollback `fast` | Tetap |
| Sheet | `sheetOpen` + `decelerate`, `sheetClose` + `accelerate` | Fade `fast` |
| Layar | `screen`, geser 24 dp + fade | Fade `fast` |
| Status | `status`, crossfade | Tetap |
| Tahan | `hold` linear, mundur `holdRewind` | Tetap, karena fungsional |
| Hitung mundur | `countdown`, angka tiap 1000 ms | Cincin diganti 5 segmen statis |
| Toast | `toast` | Fade tanpa geser |

Reduced motion dibaca dari `MediaQuery.disableAnimations`. Satu helper di `core/theme` memilih durasi dan kurva, sehingga widget tidak mengecek sendiri.

Konstanta perilaku yang belum ada di `tokens.json` ditaruh di `RBehavior`: kedip prev/next 240 ms, pill "nyambung lagi" 2 detik, polling cepat 2 detik, batas `lastPowerCommand` 10 menit, batas tunggu resume 2 detik.

## 7. State

| State | Layar | Bentuk |
|---|---|---|
| Menyambung | S02, Q08 | Cincin + teks, kontrol nonaktif |
| Offline | S10, R05 | Ikon wifi coret + penjelasan + "Coba lagi" |
| Laptop mati | P15 | Ikon power + "Laptop lagi mati" |
| Nyambung lagi | S11 | Centang + toast, 2 detik |
| Gagal kirim | S04, S06 | Nilai kembali + toast "Ulangi" |
| Token ditolak | Q11, Q12 | Layar pairing + pesan |
| Izin kamera ditolak | Q05 | "Buka pengaturan HP" + "Isi manual" |
| Berhasil | Q09, P09 | Layar hasil dengan aksi |
| Gagal daya | P10, P11 | Peringatan + aksi ulang |
| Telat batal | P14 | Tanpa tombol Batal |
| Fallback solid | R06 | `glass.solid`, cahaya latar mati |

### Fallback solid

Flutter tidak mengekspos reduce transparency, jadi sumbernya dibuat eksplisit di `GlassMode`:

| Sumber | Platform |
|---|---|
| `MediaQuery.highContrast` | Android, iOS |
| Platform channel `UIAccessibility.isReduceTransparencyEnabled` | iOS |
| Waktu raster lewat `SchedulerBinding.addTimingsCallback` terlalu lambat secara konsisten | Android, iOS, berlaku selama sesi |

`GlassPanel` dan sheet hanya membaca `GlassMode`.

## 8. Accessibility baseline

- Kontras ≥ 4.5:1 terhadap komposit kaca terburuk (`design/review.md`).
- Target ≥ 48 dp.
- Urutan fokus Remote: nama → status → pengaturan → Sleep → Restart → Matikan → volume → mute → − → + → prev → play → next.
- Sheet: fokus ke judul saat buka, kembali ke pemicu saat tutup.
- Hitung mundur: fokus ke Batal; umumkan di awal, lalu di 3 dan 1. P13 mengumumkan sisa waktu.
- Tombol back: Remote keluar app; Pengaturan ke Remote; sheet menutup; hitung mundur = Batal; pairing mundur satu langkah.
- Kepatuhan belum diklaim sampai diuji dengan TalkBack/VoiceOver.

## 9. Implementation notes

- Token: `app/lib/core/theme/tokens.g.dart`, dihasilkan oleh `app/tool/generate_tokens.dart` dari `design/tokens.json`. Jangan diedit manual.
- Tema: `app/lib/core/theme/`.
- Teks: `app/lib/core/strings/`.
- Cara memastikan widget baru memakai token: review memakai checklist pre-commit, dan grep `Color(0x` serta literal padding di `lib/features/` harus kosong.
- Blur: `ImageFilter.blur` dengan sigma ≈ radius / 2, digabung saturasi `component.glassPanel.saturation` lewat `ImageFilter.compose`. Nilainya disetel di perangkat.
- Cahaya latar digambar statis, satu kali, sebagai `RadialGradient`.
- Ikon: Lucide, memakai path dari artboard atau `CustomPaint`, tanpa `Icons.*` Material.
- Ikon app dirender dari SVG inline di `design/export/artboards/Logo.dc.html`; ikon gelap adalah default launcher.
