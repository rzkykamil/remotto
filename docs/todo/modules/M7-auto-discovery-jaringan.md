# M7 Auto-Discovery Jaringan

## Frontend

- Selesai dengan Reviewer LOLOS DENGAN SARAN, tanpa temuan WAJIB. 8 task (T1 sampai T8) dicentang di `docs/todo/frontend.md` M7.
- Dibangun: `agentId` di app (storage opsional, `AgentStatus`, validator QR `id`), abstraksi discovery dengan implementasi `nsd`, `NetworkChangeSource` untuk `connectivity_plus`, `EndpointResolver`, dan integrasi ke `ConnectionController`. Tanpa layar, widget, atau teks baru.
- Gerbang lolos: `dart format` dan `flutter analyze` bersih, `flutter test` 1139 test hijau, `flutter build apk --debug` sukses. Pubspec bebas UI kit.
- Keputusan `[Frontend M7]` di `docs/decision-log.md`. Saran reviewer di `docs/todo/backlog/integration.md` bagian M7.
- Pembuktian di HP, di iOS, dan dengan agent asli ada di `docs/todo/waiting.md` bagian M7. Sebagian besar baru bisa dites setelah fase Backend selesai.
