# M6 Ketahanan & Startup

## Frontend

- Selesai dengan Reviewer LOLOS DENGAN SARAN. Gerbang: `flutter test` lulus, `flutter analyze` bersih.
- Dibangun: `WidgetsBindingObserver` di `RemoteScreen` untuk pause dan resume polling, `ConnectionController.pause()` dan `resume()`, timeout tunggal `RMotion.commandTimeout`, retry `VolumeSender` hanya untuk kegagalan transien, dan monitor raster di `raster_monitor.dart`.
- Dicentang di `docs/todo/frontend.md` berdasarkan test lifecycle, test resume, dan test raster. Empat item pembuktian di HP ada di `docs/todo/waiting.md` bagian M6.
- Keputusan di `docs/decision-log.md` dengan tag `[Frontend M6]`. Saran di `docs/todo/backlog/integration.md` bagian M6.
- Branch `team/m6-ketahanan-startup` dibuat dari `team/m5-pengaturan-tema`, bukan dari `main`.
