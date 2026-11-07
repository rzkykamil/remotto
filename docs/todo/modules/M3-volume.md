# M3 Volume

## Frontend

- Selesai dengan Reviewer LOLOS DENGAN SARAN. 10 task `docs/todo/frontend.md` M3 dicentang. Gerbang lolos: analyze dan format bersih, 651 test lulus.
- Dibangun: `VolumeRepository` dan fake di `test/support/`, `VolumeSlider` (tap, drag, rollback, muted, disabled), `VolumeSender` (throttle 100 ms, satu request berjalan), `VolumeController` dan providers, `VolumeReadout` dan `VolumePanel`, sinkron dari polling, dan Semantics slider.
- Data masih tiruan. `volumeRepositoryProvider` belum punya implementasi asli; layar Remote di app asli melempar error sampai Integrasi M3. Tes lewat fake dan `app/test/features/remote/volume_flow_test.dart`.
- Keputusan ada di `docs/decision-log.md` dengan tag `[Frontend M3]`. Saran dan item lanjutan: `docs/todo/backlog/frontend.md` bagian M3.
- Pembuktian di HP, rasa slider, dan TalkBack/VoiceOver ada di `docs/todo/waiting.md` bagian M3.
- Fase aktif pindah ke Backend karena DoD Frontend terpenuhi.
