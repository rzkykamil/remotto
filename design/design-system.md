# Design system — Warm Liquid Glass

Nilai konkret ada di `tokens.json`. Dokumen ini hanya merujuk nama token.

## Personality

Kaca hangat di atas cahaya lampu kamar: lapisan bening yang tenang, dengan satu bola oranye yang menandai "ini yang penting". Terasa solid dan bisa ditebak, karena app ini dipakai berulang tanpa banyak mikir.

## Prinsip (bisa diuji di screen)

1. **Satu ketukan, satu hasil.** Media dan volume tidak pernah butuh dialog atau scroll.
2. **Jempol dulu.** Aksi tersering ada di 45% bawah layar. Tombol daya di atas, di luar jangkauan jempol.
3. **Oranye cuma satu tempat.** Maksimal satu elemen beraksen penuh per layar (play, atau CTA utama).
4. **Bahaya muncul saat perlu.** Merah hanya di tahap 2 konfirmasi daya, hitung mundur, dan hasil gagal daya. Error form memakai `accent.text` + ikon.
5. **Status tidak cuma warna.** Setiap state punya bentuk ikon + teks. Disabled selalu disertai penjelasan.
6. **Kaca tidak boleh mengorbankan keterbacaan.** Teks di atas kaca lulus 4.5:1 di titik cahaya paling terang. Ada fallback solid.
7. **Terasa ditekan.** Kapsul mengecil 6% dan makin opak saat ditekan, dengan haptic < 100 ms.

## Anti-pattern

- Gradient ungu-biru, neon, blob warna-warni mencolok.
- Kaca bertumpuk: maksimal 1 lapis blur per area. Tombol di dalam panel memakai `glass.chip` tanpa blur sendiri.
- Teks tipis abu-abu di atas kaca terang tanpa cek kontras.
- Tampilan Material default: FAB, ripple ungu, AppBar standar, `Slider`/`SnackBar`/`SegmentedButton` default.
- Skeuomorph 2010: tekstur logam/kulit, bevel mengkilap.
- Tombol shutdown di zona jempol atau di sebelah play; merah di layar utama.
- Copy kaku/korporat ("Perangkat berhasil terautentikasi").
- Spinner kosong tanpa teks; spacing/radius di luar skala token.
- Putih murni di atas hitam murni di mode gelap.

## Warna

Mode: Terang, Gelap, Ikuti sistem (default). Key `semantic.light` dan `semantic.dark` identik.

| Peran | Token | Pemakaian |
| --- | --- | --- |
| Latar | `color.bg.base`, `color.bg.glowA`, `color.bg.glowB` | Latar + dua cahaya radial statis (kanan atas, kiri bawah). Dimatikan saat reduce transparency. |
| Teks | `color.fg.primary`, `.secondary`, `.disabled` | Disabled tidak harus lulus kontras, tapi selalu disertai teks penjelas. |
| Aksen | `color.accent.default`, `.highlight`, `.on`, `.text`, `.shadow` | Gradient tombol play (highlight → default), ikon di atasnya `accent.on`, link/teks aksen `accent.text`. |
| Status | `color.status.success`, `.warning` | Online / menyambung. Offline sengaja netral (`fg.secondary`). |
| Bahaya | `color.status.danger`, `.dangerText`, `.dangerSoft`, `.onDanger` | Hanya alur daya tahap 2+, dan hasil gagal daya. |
| Kaca | `color.glass.*` | `fill` (panel blur), `chip` (tombol dalam panel), `edge`, `highlight`, `lowlight`, `shadow`, `sheet`, `toast`, `scrim`, `solid` (fallback). |
| Kontrol | `color.slider.*`, `color.control.*` | Isi/track slider, segmented, switch, isi cincin hitung mundur. |

Sleep memakai `accent.text` untuk cincin hitung mundur, bukan merah (tidak destruktif).

Mode gelap dioptimalkan untuk kamar gelap: `bg.base` bukan hitam murni, `fg.primary` bukan putih murni, cahaya latar redup (alpha 0.18–0.20), dan isi slider `slider.fill` hangat, tidak putih.

## Tipografi

- **Geist** untuk UI: lebar, tenang, terbaca di ukuran kecil.
- **Geist Mono** untuk semua angka (volume, uptime, hitung mundur, alamat, token) dengan tabular figures, supaya angka tidak goyang saat berubah.
- Fallback: Roboto (Android), SF Pro (iOS), lalu monospace sistem.

Skala: `typography.displayCountdown`, `displayVolume`, `titleXl`, `titleLg`, `titleMd`, `body`, `label`, `caption` (huruf kapital).

Teks sistem diperbesar:

- Semua teks mengikuti `textScaler`.
- `displayVolume` dan `displayCountdown` dikunci maksimal 1.3×.
- Label tombol boleh 2 baris dan tinggi tombol ikut bertambah.
- Nama laptop di Remote di-ellipsis 1 baris; di Pengaturan dibungkus penuh.

## Layout

- Margin layar: `size.screenMargin` (≥390 dp) / `size.screenMarginCompact` (≤360 dp).
- Struktur Remote: header → baris daya → panel volume (mengisi sisa tinggi, jadi tengah layar tidak pernah kosong) → dock media.
- Safe area: konten di dalam padding sistem. Dock + 16 dp di atas home indicator.
- Target sentuh: minimal `size.touchMin`. Kontrol utama `size.play`, `size.media`, `size.control`, `size.hold`, `size.cancel`.
- Zona jempol: aksi tersering di 45% bawah. Aksi berbahaya di atas atau di balik sheet.
- Spacing hanya dari `spacing.*`. Radius berbeda per peran: `radius.xs` badge, `radius.sm` input/toast, `radius.md` grup, `radius.lg` panel, `radius.xl` sheet, `radius.full` kapsul/tombol.

## Elevation / lapisan kaca

| Level | Wujud | Token |
| --- | --- | --- |
| g0 | Track (cekung) | `slider.track` |
| g1 | Chip dalam panel, tanpa blur | `glass.chip`, `glass.edge`, `glass.highlight` |
| g2 | Panel kaca dengan blur | `glass.fill`, `blur.glass`, `glass.shadow` |
| g3 | Tint aksen (play) | `accent.highlight` → `accent.default`, `accent.shadow` |
| g4 | Sheet / overlay | `glass.sheet`, `blur.sheet`, `glass.scrim` |

Implementasi: `ClipRRect` + `BackdropFilter(ImageFilter.blur)` per panel, sekitar 6 area blur per layar. Cahaya latar digambar statis. Fallback otomatis ke `glass.solid` saat:

- reduce transparency / high contrast aktif di OS;
- perangkat dinilai lemah (keputusan saat implementasi).

## Motion

| Momen | Token | Catatan |
| --- | --- | --- |
| Press | `duration.pressDown` + skala `component.key.pressedScale` | Lepas: `duration.pressUp` + `easing.spring` |
| Slider | langsung ikut jari; rollback `duration.fast` | Track menebal `size.trackActive` saat ditarik |
| Sheet | `duration.sheetOpen` (`easing.decelerate`) / `duration.sheetClose` (`easing.accelerate`) | Tahap 1→2 crossfade di sheet yang sama |
| Layar | `duration.screen` | Geser 24 dp + fade, bukan slide penuh |
| Status pill | `duration.status` | Crossfade |
| Tahan konfirmasi | `duration.hold` linear, mundur `duration.holdRewind` | |
| Hitung mundur | `duration.countdown`; angka berganti setiap 1000 ms | |
| Toast | `duration.toast` masuk/keluar | |

Reduced motion: tanpa geser/skala, hanya fade `duration.fast`. Cincin hitung mundur diganti 5 segmen statis.

## Haptic

| Momen | Pola |
| --- | --- |
| Play / prev / next / mute / −+ | `lightImpact` saat jari turun |
| Slider setiap 5% | `selectionClick` |
| Slider mentok 0 / 100 | `mediumImpact` |
| QR terbaca | `mediumImpact` |
| Tahan 50% | `selectionClick` |
| Tahan selesai | `heavyImpact` |
| Gagal kirim / batal gagal | `vibrate` pendek |

Semua haptic mati jika "Getar saat ditekan" off.

## Target aksesibilitas

- Kontras teks ≥ 4.5:1 di kedua tema, dihitung terhadap komposit kaca terburuk (lihat `review.md`).
- Target ≥ 48 dp, dengan kontrol utama jauh lebih besar.
- State tidak hanya dibedakan lewat warna (ikon, label, posisi thumb, centang).
- Label `Semantics` untuk semua kontrol. Perubahan penting diumumkan: status koneksi, toast, hitung mundur di 5/3/1, hasil.
- Dukung teks sistem diperbesar (lihat Tipografi), reduced motion, dan reduce transparency.
- Kepatuhan **belum diklaim**: perlu uji TalkBack/VoiceOver di perangkat (lihat `review.md`).
