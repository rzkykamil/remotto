## Ringkasan

<!-- Apa yang berubah dan kenapa. Tautkan issue terkait: Closes #123 -->

## Jenis perubahan

- [ ] Perbaikan bug
- [ ] Fitur baru
- [ ] Dokumentasi
- [ ] Refactor atau chore
- [ ] CI

## Area

- [ ] `agent/` (Go)
- [ ] `app/` (Flutter)
- [ ] `docs/` atau `postman/`
- [ ] `.github/`

## Checklist

- [ ] Agent: `go test ./...`, `go vet ./...`, dan `gofmt -l .` bersih
- [ ] App: `flutter test`, `flutter analyze`, dan `dart format` bersih
- [ ] Test ditambahkan atau diperbarui untuk perilaku yang berubah
- [ ] Tidak ada test yang menjalankan sleep, restart, atau shutdown sungguhan
- [ ] Semua endpoint tetap wajib token
- [ ] `docs/api-spec.md` dan `postman/` diperbarui kalau endpoint berubah
- [ ] Tidak ada `config.json` asli, token, atau keystore di commit
- [ ] Commit mengikuti Conventional Commits

## Catatan untuk reviewer

<!-- Hal yang perlu diperhatikan, screenshot untuk perubahan UI, dll. -->
