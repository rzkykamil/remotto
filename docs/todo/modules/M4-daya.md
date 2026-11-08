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
