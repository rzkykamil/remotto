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

## Integrasi

- Selesai dengan Reviewer LOLOS tanpa temuan WAJIB dan SARAN. 5 baris `docs/todo/integration.md` M3 berstatus Selesai (tes loopback).
- Dibangun: `AgentHttpClient.putVolume`, `postVolumeStep`, dan `postVolumeMute`; `HttpVolumeRepository` (tanpa retry sendiri, pairing null menjadi UnreachableFailure); `volumeRepositoryProvider` memakai HTTP; `FakeAgentServer` menangani rute volume dan mode audioFailed. Tes: 23 kasus di `test/integration/volume_http_flow_test.dart`.
- Gerbang lolos: analyze dan format bersih, 707 test lulus. Tidak ada endpoint agent baru; `agent/` dan `postman/` tidak berubah.
- Keputusan ada di `docs/decision-log.md` dengan tag `[Integrasi M3]`. Saran di `docs/todo/backlog/integration.md` bagian M3.
- Pembuktian dengan agent asli dan HP sungguhan ada di `docs/todo/waiting.md`.
- Fase aktif pindah ke QA karena DoD Integrasi terpenuhi.

## QA

- Delapan skenario [O] tercakup test: BR-3 (`TestBR3_*` di `agent/internal/control/volume_test.go` dan `agent/internal/server/volume_test.go`, `app/test/support/fake_volume_repository_test.dart`); BR-15 (`TestBR15_*`, `app/test/features/remote/volume_flow_test.dart`); BR-16 (`TestBR16_*`, `volume_controller_test.dart`, `widgets/volume_panel_test.dart`); BR-14 (`app/test/features/remote/state/volume_sender_test.dart`); mute idempoten (`TestVolumeMuteIsIdempotent`); rollback dan offline (`state/volume_controller_test.dart`, `integration/volume_http_flow_test.dart`); `volume: null` (`TestStatusVolumeNullWhenAudioFails`, `core/connection/connection_controller_test.dart`); rate limit (`TestDefaultRateLimitAboveSliderRate`, `agent/internal/config/config_test.go`, sebagai penjaga default config saja).
- Tidak ada bug. Fixing dilewati karena tidak ada temuan.
- Pembuktian manual [M] (volume nyata, headset, perubahan dari laptop) ada di `docs/todo/waiting.md` bagian M3.
- `-race` belum dijalankan (lihat `docs/todo/backlog/qa.md`). Tes rate limit terhadap laju slider nyata menunggu M6 (lihat backlog QA).
