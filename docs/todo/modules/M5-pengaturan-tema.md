# M5 Pengaturan & Tema

## Frontend

- Selesai dengan Reviewer LOLOS DENGAN SARAN, tanpa temuan WAJIB. Task T0 sampai T9 selesai. T10 adalah dokumentasi ini. Gerbang: `flutter test` 1023 test lulus, `flutter analyze` bersih, format bersih.
- Dibangun: `SettingsGroup` dan `SettingsRow`, `ThemeSegmented`, `GlassSwitch`, `SimpleConfirmSheet`, string di `core/strings/`, layar Pengaturan R01 sampai R06, alur pairing ulang dari Pengaturan dan dari Remote offline, dan channel reduce transparency (sisi Dart).
- Dicentang di `docs/todo/frontend.md` berdasarkan widget test, alur test, dan test channel. Verifikasi visual di HP, TalkBack, dan kode Swift iOS tidak dicentang. Itu ada di `docs/todo/waiting.md` bagian M5.
- Keputusan di `docs/decision-log.md` dengan tag `[Frontend M5]`. Saran dan item lanjutan di `docs/todo/backlog/frontend.md` bagian M5.

## Backend

Fase tidak relevan: M5 memakai data lokal (tema dan getar di penyimpanan HP) atau data yang sudah ada dari M1 sampai M4, dan tidak ada endpoint baru di `docs/api-spec.md`. Uji pairing ulang di perangkat ada di `docs/todo/waiting.md` bagian M5.

## Integrasi

Fase tidak relevan: tidak ada repository atau endpoint baru yang perlu disambungkan ke agent. Pairing ulang memakai repository pairing yang sudah ada. Uji pairing ulang dengan agent sungguhan ada di `docs/todo/waiting.md` bagian M5.
