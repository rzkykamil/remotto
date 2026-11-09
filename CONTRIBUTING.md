# Berkontribusi

Terima kasih sudah tertarik membantu Remotto. Proyek ini kecil dan dipakai
pribadi, tapi perbaikan dan saran tetap disambut.

## Sebelum mulai

- Cek [issue](../../issues) yang sudah ada supaya tidak dobel.
- Untuk perubahan besar, buka issue dulu dan diskusikan arahnya.
- Celah keamanan jangan dilaporkan lewat issue publik. Lihat [SECURITY.md](SECURITY.md).

## Setup

Prasyarat dan cara menjalankan ada di [README.md](README.md). Ringkasnya:

```powershell
# Agent (Go)
cd agent
go run ./cmd/agent run

# App (Flutter)
cd app
flutter pub get
flutter run
```

Rujukan desain dan kontrak ada di folder `docs/`: `prd.md`, `technical-spec.md`,
`api-spec.md`, dan `design-system.md`.

## Alur kerja

1. Fork repositori, lalu buat branch dari `main`, misalnya `fix/volume-clamp`.
2. Buat perubahan kecil dan fokus. Satu pull request untuk satu tujuan.
3. Jalankan pemeriksaan di bawah sampai bersih.
4. Buka pull request ke `main` dan isi template-nya.

## Pemeriksaan sebelum PR

Agent:

```bash
cd agent
go test ./...
go vet ./...
gofmt -l .
```

App:

```bash
cd app
flutter test
flutter analyze
dart format --output=none --set-exit-if-changed .
```

## Aturan penting

- **Jangan menjalankan perintah sleep, restart, atau shutdown sungguhan di test otomatis.** Integrasi OS hanya lewat interface di `internal/control` supaya bisa di-fake.
- Semua endpoint agent wajib token dan hanya untuk LAN. Jangan melonggarkan ini.
- Jangan commit `config.json` asli, token, atau keystore.
- Perubahan endpoint harus ikut memperbarui `docs/api-spec.md` dan collection di `postman/`.
- UI Flutter mengikuti `docs/design-system.md`. Tanpa package UI kit.

## Gaya kode dan commit

- Kode, identifier, komentar, dan commit message memakai bahasa Inggris. Teks UI memakai bahasa Indonesia santai dan singkat.
- Commit mengikuti [Conventional Commits](https://www.conventionalcommits.org) dengan scope `agent`, `app`, `docs`, atau `ci`. Contoh: `feat(agent): add volume endpoint`.
- Tambahkan test untuk perilaku baru atau bug yang diperbaiki.

## Lisensi

Dengan berkontribusi, kamu setuju kontribusimu dilisensikan di bawah [MIT](LICENSE).
