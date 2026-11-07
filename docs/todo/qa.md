# QA

Tanda: **[O]** otomatis, **[M]** manual oleh pemilik lewat `waiting.md`.

## M0 Fondasi Proyek

- [ ] [O] `flutter analyze`, `dart format`, `go vet`, `gofmt` bersih
- [x] [O] Generator menghasilkan semua token terang dan gelap
- [x] [O] App tanpa data pairing masuk ke Q01; dengan data ke Remote
- [x] [O] `pubspec.yaml` bebas UI kit
- [ ] [M] Tampilan dasar dan kinerja blur di HP

## M1 Pairing & Koneksi

- [ ] [O] Token 64 hex dibuat saat first run
- [ ] [O] BR-1: semua route menolak tanpa token
- [ ] [O] BR-2: token salah format dan salah nilai → 401
- [ ] [O] BR-11: token tidak ada di log dan respons
- [ ] [O] BR-12: IP sumber publik → 403; app menolak host publik
- [ ] [O] QR tidak valid: bukan JSON, `v` salah, token salah format, host publik
- [ ] [O] Config rusak → config baru + cadangan; config lebih baru → agent menolak start
- [ ] [O] BR-8: satu gagal tetap online, dua gagal offline
- [ ] [O] BR-9: 401 → Q12, data lama dipertahankan
- [ ] [O] Polling tidak menumpuk
- [ ] [M] Scan QR, firewall, offline → online

## M2 Kontrol Media

- [ ] [O] Happy path tiga endpoint dengan fake OS
- [ ] [O] `media_failed` → ikon kembali + toast
- [ ] [O] Tap ulang selama proses diabaikan
- [ ] [O] BR-7: kontrol nonaktif saat offline
- [ ] [O] Tanpa retry otomatis
- [ ] [M] Brave, Spotify, layar terkunci

## M3 Volume

- [ ] [O] BR-3: −1, 101, pecahan, teks → 400
- [ ] [O] BR-15: level berubah mematikan mute
- [ ] [O] BR-16: langkah 5, berhenti di 0 dan 100
- [ ] [O] BR-14: throttle 100 ms, nilai akhir selalu terkirim
- [ ] [O] Mute eksplisit idempoten
- [ ] [O] Gagal → rollback; offline saat drag → gesture batal
- [ ] [O] `volume: null` di status tidak dianggap offline
- [ ] [O] Rate limit tidak terpicu laju slider
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
