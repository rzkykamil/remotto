# M4 Daya

## Frontend

- Selesai dengan Reviewer LOLOS DENGAN SARAN. 13 task `docs/todo/frontend.md` M4 dicentang. Gerbang lolos: analyze dan format bersih, 897 test lulus.
- Dibangun: `PowerRepository` dan fake di `test/support/`, `PowerFlowController` sebagai satu sumber state, `PowerFlowHost` sebagai cermin route, `PowerRow`, `ConfirmSheet`, `HoldToConfirm`, `CountdownScreen` dengan Batal dan wakelock, `ResultScreen` (P09, P10, P14), P11, P13, P15, `lastPowerCommand` di SharedPreferences, dan polling cepat setelah restart.
- Data masih tiruan. `powerRepositoryProvider` belum punya implementasi asli sampai Integrasi M4. Tidak ada perintah daya sungguhan yang dijalankan selama pengerjaan.
- Keputusan ada di `docs/decision-log.md` dengan tag `[Frontend M4]`. Saran dan item lanjutan: `docs/todo/backlog/frontend.md` bagian M4.
- Verifikasi visual, rasa tahan, TalkBack/VoiceOver, dan wakelock di HP ada di `docs/todo/waiting.md` bagian M4.
- Fase aktif pindah ke Backend karena DoD Frontend terpenuhi.

## Backend

- Selesai dengan Reviewer LOLOS tanpa temuan. 6 task `docs/todo/backend.md` M4 dicentang, termasuk sub-task `postman/`.
- Dibangun: scheduler daya bermutex dengan generasi di `internal/control/power.go` dan `clock.go`, pekerja `oswin` untuk shutdown/restart dan sleep (`power_windows.go`, `sleep_windows.go`), rute `/power/*` di `internal/server/power.go`, `pending` di `/status`, dan perakitan di `cmd/agent`.
- Gerbang lolos: `gofmt`, `go vet`, `go test ./... -count=1` (dan `-count=5`), dan `GOOS=linux go build` bersih. `-race` belum bisa lokal (tanpa gcc). Tidak ada efek OS sungguhan yang dijalankan.
- Keputusan ada di `docs/decision-log.md` dengan tag `[Backend M4]`. Saran di `docs/todo/backlog/backend.md` bagian M4.
- Pembuktian efek nyata (sleep, jalur S3, `pending` setelah shutdown tertahan) ada di `docs/todo/waiting.md` bagian M4.
- Fase aktif pindah ke Integrasi karena DoD Backend terpenuhi.

## Integrasi

- Selesai dengan Reviewer LOLOS. Gerbang: 965 test hijau, `dart format` dan `flutter analyze` bersih, test integrasi daya dijalankan 5 kali dan stabil.
- Dibangun: `HttpPowerRepository`, `AgentHttpClient.postPowerSchedule` dan `postPowerCancel`, rute `/power/*` di `FakeAgentServer`, dan validasi action di `Pending.fromData`. Test: `http_power_repository_test.dart`, `power_http_flow_test.dart`, `power_contract_test.dart`.
- Bug `Pending.fromData` menerima action tak dikenal ditemukan test kontrak lalu `fixed` (lihat `docs/todo/qa.md`). Keputusan di `docs/decision-log.md` tag `[Integrasi M4]`. Backlog di `docs/todo/backlog/integration.md` bagian M4.
- Verifikasi visual belum dilakukan karena tidak ada perubahan UI. Pembuktian dengan agent dan HP sungguhan ada di `docs/todo/waiting.md` bagian M4 (Integrasi).
- Fase aktif pindah ke Selesai setelah Integrasi, QA, dan Fixing lolos.
