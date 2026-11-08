# QA

Tanda: **[O]** otomatis, **[M]** manual oleh pemilik lewat `waiting.md`.

## M0 Fondasi Proyek

- [ ] [O] `flutter analyze`, `dart format`, `go vet`, `gofmt` bersih
- [x] [O] Generator menghasilkan semua token terang dan gelap
- [x] [O] App tanpa data pairing masuk ke Q01; dengan data ke Remote
- [x] [O] `pubspec.yaml` bebas UI kit
- [ ] [M] Tampilan dasar dan kinerja blur di HP

## M1 Pairing & Koneksi

- [x] [O] Token 64 hex dibuat saat first run
- [x] [O] BR-1: semua route menolak tanpa token
- [x] [O] BR-2: token salah format dan salah nilai → 401
- [x] [O] BR-11: token tidak ada di log dan respons
- [x] [O] BR-12: IP sumber publik → 403; app menolak host publik
- [x] [O] QR tidak valid: bukan JSON, `v` salah, token salah format, host publik
- [x] [O] Config rusak → config baru + cadangan; config lebih baru → agent menolak start
- [x] [O] BR-8: satu gagal tetap online, dua gagal offline
- [x] [O] BR-9: 401 → Q12, data lama dipertahankan
- [x] [O] Polling tidak menumpuk
- [ ] [M] Scan QR, firewall, offline → online

## M2 Kontrol Media

- [x] [O] Happy path tiga endpoint dengan fake OS
- [x] [O] `media_failed` → ikon kembali + toast
- [x] [O] Tap ulang selama proses diabaikan
- [x] [O] BR-7: kontrol nonaktif saat offline
- [x] [O] Tanpa retry otomatis
- [ ] [M] Brave, Spotify, layar terkunci

## M3 Volume

- [x] [O] BR-3: −1, 101, pecahan, teks → 400
- [x] [O] BR-15: level berubah mematikan mute
- [x] [O] BR-16: langkah 5, berhenti di 0 dan 100
- [x] [O] BR-14: throttle 100 ms, nilai akhir selalu terkirim
- [x] [O] Mute eksplisit idempoten
- [x] [O] Gagal → rollback; offline saat drag → gesture batal
- [x] [O] `volume: null` di status tidak dianggap offline
- [x] [O] Rate limit tidak terpicu laju slider
- [ ] [M] Volume nyata, headset, perubahan dari laptop

## M4 Daya

- [ ] [O] BR-4: eksekusi setelah jeda, tidak sebelumnya
- [ ] [O] BR-5: jadwal kedua → 409, jadwal lama utuh
- [ ] [O] BR-17: batal tanpa jadwal → 409
- [ ] [O] Batal saat eksekusi → 409 `power_executing`
- [ ] [O] BR-6: satu ketukan tidak pernah cukup; lepas cepat mereset
- [ ] [O] BR-19: P14 tanpa tombol Batal
- [ ] [O] BR-20: sisa dari `remainingMs`
- [ ] [O] Timeout ambigu tidak menampilkan P10
- [ ] [O] Gagal eksekusi membersihkan `pending`
- [ ] [O] Race batal dan eksekusi aman (`go test -race`)
- [ ] [M] Sleep, shutdown, restart, batal, tutup app saat hitung mundur

## M5 Pengaturan & Tema

- [ ] [O] Tema dan haptic tersimpan
- [ ] [O] Haptic mati menonaktifkan semua haptic
- [ ] [O] Pairing ulang menghapus data sambungan dan `lastPowerCommand`, tema tetap
- [ ] [O] BR-10: token lama ditolak agent yang berjalan
- [ ] [O] BR-18: pairing baru mengganti yang lama
- [ ] [M] Tampilan di HP, TalkBack, teks 130%

## M6 Ketahanan & Startup

- [ ] [O] Rate limit → 429 + `Retry-After`
- [ ] [O] Panic handler tidak menjatuhkan proses
- [ ] [O] Graceful shutdown membuang jadwal
- [ ] [O] Rotasi log
- [ ] [O] Polling berhenti di background, jalan saat resume
- [ ] [O] BR-21: kontrol tidak bisa ditekan selama S02
- [ ] [M] Auto-start, kedip konsol, APK dari CI

## Bugs Ditemukan

| Bug | Status | Referensi |
|---|---|---|
