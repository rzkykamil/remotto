# Backlog QA

Satu baris per temuan, dengan referensi inline. Heading modul tidak boleh dihapus.

## M0 Fondasi Proyek

Belum ada temuan.

## M1 Pairing & Koneksi

- `go test -race` belum bisa dijalankan lokal karena gcc dan CGO tidak ada. Jalankan di CI atau mesin ber-gcc (`agent/internal/server`, `agent/internal/pairing`).
- Sisi log app untuk BR-11 belum teruji karena app belum punya logger. Ditunda ke M6 (lihat `docs/todo/backlog/integration.md`).
- [ ] `test/features/pairing/state/pairing_flow_controller_test.dart` (4 test: scan QR valid, langganan scanner, Coba lagi dari Q10, Q09 expired) gagal dengan `Expected PairingStep.success, Actual PairingStep.timeout`. Bukan dari T10: folder pairing tidak disentuh, dan `core/network/agent_status.dart` ikut termodifikasi di working tree M4. Cek setelah perubahan itu di-commit.


## M2 Kontrol Media

- `go test -race` belum bisa jalan lokal (CGO mati) untuk `agent/internal/control` dan `agent/internal/server`. CI belum menjalankan `-race` (`ci.yml` hanya `go test ./...`); tambahkan di CI atau jalankan di mesin ber-gcc, konsisten dengan M1.

## M3 Volume

- `go test -race` belum bisa jalan lokal (CGO mati) untuk `agent/internal/control`, `oswin`, dan `agent/internal/server`. Jalankan di CI atau mesin ber-gcc, konsisten dengan M1 dan M2.
- Tes rate limit terhadap laju slider nyata (`docs/todo/qa.md` M3) menunggu middleware rate limit di M6 (FR-6.2). M3 hanya memeriksa default config lewat `TestDefaultRateLimitAboveSliderRate`.

## M4 Daya

- [x] `test/features/remote/state/volume_controller_test.dart` (6 test offline) dan `test/integration/connection_http_flow_test.dart` (1 test, "dua kegagalan berturut ke offline"): gagal dengan `UnimplementedError: override in bootstrap` karena `lastPowerCommandProvider` membutuhkan `sharedPreferencesProvider`. Diperbaiki di Frontend M4 (lihat `[Frontend M4] Test wajib meng-override sharedPreferencesProvider` di `docs/decision-log.md`).
- Butir QA "Race batal dan eksekusi aman" (`docs/todo/qa.md` M4) belum terbukti: `TestPowerCancelAndFireRaceSingleOutcome` (`agent/internal/control/power_test.go`) ada, tapi belum dijalankan dengan `-race`. Sama seperti M1-M3, jalankan `go test -race ./internal/control/...` di CI atau mesin ber-gcc, lalu centang butir itu.

## M5 Pengaturan & Tema

Belum ada temuan.

## M6 Ketahanan & Startup

Belum ada temuan.

## Stretch

Hanya dikerjakan kalau pemilik menyebutnya.

- [ ] Golden test komponen utama, terang dan gelap
- [ ] Uji VoiceOver dan build iOS di Mac
