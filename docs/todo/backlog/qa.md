# Backlog QA

Satu baris per temuan, dengan referensi inline. Heading modul tidak boleh dihapus.

## M0 Fondasi Proyek

Belum ada temuan.

## M1 Pairing & Koneksi

- `go test -race` belum bisa dijalankan lokal karena gcc dan CGO tidak ada. Jalankan di CI atau mesin ber-gcc (`agent/internal/server`, `agent/internal/pairing`).
- Sisi log app untuk BR-11 belum teruji karena app belum punya logger. Ditunda ke M6 (lihat `docs/todo/backlog/integration.md`).

## M2 Kontrol Media

Belum ada temuan.

## M3 Volume

Belum ada temuan.

## M4 Daya

Belum ada temuan.

## M5 Pengaturan & Tema

Belum ada temuan.

## M6 Ketahanan & Startup

Belum ada temuan.

## Stretch

Hanya dikerjakan kalau pemilik menyebutnya.

- [ ] Golden test komponen utama, terang dan gelap
- [ ] Uji VoiceOver dan build iOS di Mac
