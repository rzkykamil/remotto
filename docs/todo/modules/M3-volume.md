# M3 Volume

## Frontend

- Selesai dengan Reviewer LOLOS DENGAN SARAN. 10 task `docs/todo/frontend.md` M3 dicentang. Gerbang lolos: analyze dan format bersih, 651 test lulus.
- Dibangun: `VolumeRepository` dan fake di `test/support/`, `VolumeSlider` (tap, drag, rollback, muted, disabled), `VolumeSender` (throttle 100 ms, satu request berjalan), `VolumeController` dan providers, `VolumeReadout` dan `VolumePanel`, sinkron dari polling, dan Semantics slider.
- Data masih tiruan. `volumeRepositoryProvider` belum punya implementasi asli; layar Remote di app asli melempar error sampai Integrasi M3. Tes lewat fake dan `app/test/features/remote/volume_flow_test.dart`.
- Keputusan ada di `docs/decision-log.md` dengan tag `[Frontend M3]`. Saran dan item lanjutan: `docs/todo/backlog/frontend.md` bagian M3.
- Pembuktian di HP, rasa slider, dan TalkBack/VoiceOver ada di `docs/todo/waiting.md` bagian M3.
- Fase aktif pindah ke Backend karena DoD Frontend terpenuhi.

## Backend

- Selesai dengan Reviewer LOLOS tanpa temuan WAJIB dan SARAN. 6 task `docs/todo/backend.md` M3 dicentang, termasuk sub-task `postman/`.
- Dibangun: `VolumeService` bermutex di `internal/control`, pekerja COM go-wca dan go-ole di `internal/oswin/audio_windows.go`, rute `GET/PUT /api/v1/volume` dan `POST /volume/up|down|mute` di `internal/server/volume.go`, wiring `/status.volume` di Windows, dan 5 request Postman Volume diperkaya.
- Gerbang lolos: `go test ./...`, `go vet`, `gofmt -l .`, dan `GOOS=linux go build` bersih. COM asli belum dijalankan; pembuktian ada di `docs/todo/waiting.md` bagian M3.
- Keputusan ada di `docs/decision-log.md` dengan tag `[Backend M3]`. Saran di `docs/todo/backlog/backend.md` bagian M3.
- Fase aktif pindah ke Integrasi karena DoD Backend terpenuhi.
