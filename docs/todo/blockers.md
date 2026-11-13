# Blockers

Format tiap item:

```text
- M3: <apa yang mandek>
  Kenapa: <penyebab>
  Yang harus dilakukan: <langkah, oleh siapa>
```

- M7: CI merah di dua job setelah push akhir modul (run `43381256379`, `agent-test` dan `app-test`). Job `build` skipped karena aturan `team/*`.
  Kenapa: dugaan, belum diverifikasi sebagai bukan akibat M7.
  - `agent-test` gagal di langkah Vulnerability check (`govulncheck@latest`): ada temuan vulnerability di standard library Go yang tercapai dari kode agent (`net/http`, `os/exec`, dan lain-lain). Dugaan: versi toolchain Go di CI. govulncheck tidak dijalankan di langkah lokal tim, jadi tidak tertangkap sebelum push.
  - `app-test` gagal di langkah Analyze: CI memakai Flutter `stable` (3.50.0), lokal 3.47.5. CI melaporkan 86 info `deprecated_member_use` untuk `package:flutter/material.dart` di file yang tidak diubah M7 (contoh `lib/app.dart`). Tidak ada error atau warning, tetapi info membuat `flutter analyze` exit 1. Run `main` terakhir (2026-11-09) hijau, jadi dugaan drift toolchain CI.
  Yang harus dilakukan (keputusan pemilik, dikerjakan sebagai tugas terpisah lewat tim, bukan membuka ulang M7):
  - Flutter: pilih salah satu. Pin versi Flutter di `.github/workflows/ci.yml` ke versi yang sama dengan lokal, atau migrasikan API yang deprecated.
  - Go: naikkan toolchain atau `go` di `agent/go.mod` ke versi yang memuat perbaikan stdlib, atau tambahkan pengecualian govulncheck yang dicatat di `docs/decision-log.md`.
  - Setelah salah satu dipilih, jalankan ulang CI dan catat hasilnya di `docs/todo/modules/M7-auto-discovery-jaringan.md`.
