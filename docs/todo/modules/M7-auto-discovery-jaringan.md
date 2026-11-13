# M7 Auto-Discovery Jaringan

## Frontend

- Selesai dengan Reviewer LOLOS DENGAN SARAN, tanpa temuan WAJIB. 8 task (T1 sampai T8) dicentang di `docs/todo/frontend.md` M7.
- Dibangun: `agentId` di app (storage opsional, `AgentStatus`, validator QR `id`), abstraksi discovery dengan implementasi `nsd`, `NetworkChangeSource` untuk `connectivity_plus`, `EndpointResolver`, dan integrasi ke `ConnectionController`. Tanpa layar, widget, atau teks baru.
- Gerbang lolos: `dart format` dan `flutter analyze` bersih, `flutter test` 1139 test hijau, `flutter build apk --debug` sukses. Pubspec bebas UI kit.
- Keputusan `[Frontend M7]` di `docs/decision-log.md`. Saran reviewer di `docs/todo/backlog/integration.md` bagian M7.
- Pembuktian di HP, di iOS, dan dengan agent asli ada di `docs/todo/waiting.md` bagian M7. Sebagian besar baru bisa dites setelah fase Backend selesai.

## Backend

- Selesai dengan Reviewer LOLOS DENGAN SARAN, tanpa temuan WAJIB. Gerbang: `gofmt`, `go vet` (termasuk tag `manual`), `go test ./...`, build Linux dan Windows, `go mod tidy` dan `go mod verify` hijau. `go test -race` belum bisa lokal (CGO mati), dicek lewat baca kode dan perlu CI.
- Dibangun: `agentId` di config (`EnsureAgentID` untuk config lama), `discovery.enabled`, `agentId` di `GET /status`, `id` opsional di QR, paket `internal/discovery` dengan `grandcat/zeroconf` v1.0.0, dan wiring di `run` dan `pair`.
- Dicentang di `docs/todo/backend.md` bagian M7 (B1 sampai B9). Keputusan `[Backend M7]` di `docs/decision-log.md`. Saran di `docs/todo/backlog/backend.md` bagian M7.
- Pembuktian mDNS nyata, adapter berganti, dan firewall UDP 5353 ada di `docs/todo/waiting.md` bagian M7 (Backend).
