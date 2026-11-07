# Release

## Bagian A — Build & CI

`.github/workflows/ci.yml` berjalan saat push ke `main` dan `team/**`, serta pull request ke `main`.

| Job | Runner | Isi | Kapan |
|---|---|---|---|
| `agent-test` | windows-latest | `gofmt`, `go vet`, `go test`, `govulncheck` | Selalu |
| `app-test` | ubuntu-latest | `dart format`, `flutter analyze`, `flutter test` | Selalu |
| `build` | ubuntu-latest | `remotto-agent.exe` (Windows amd64) dan `remotto.apk` | Hanya `main` |

`build` hanya jalan di `main` karena `main` adalah branch rilis. CI tidak butuh secret.

Build lokal agent:

```powershell
cd agent
go build -o bin/remotto-agent.exe ./cmd/agent
```

Build lokal app:

```powershell
cd app
flutter run
flutter build apk --release
```

**Artefak CI:** tab Actions di GitHub → run terakhir `main` → bagian Artifacts → `remotto-<sha>`, berisi `remotto-agent.exe` dan `remotto.apk`.

**Signing APK:** memakai signing debug sampai keystore rilis dibuat. Keystore dan `key.properties` tidak pernah di-commit.

**iOS:** dibangun manual di Mac dengan `flutter build ios`.

## Bagian B — Install agent di laptop (satu kali)

1. Buat folder tetap, lalu taruh `remotto-agent.exe` di sana. Contoh: `C:\Tools\Remotto\`.

2. Tampilkan QR:

   ```powershell
   cd C:\Tools\Remotto
   .\remotto-agent.exe pair
   ```

   Kalau alamat di QR salah, tentukan sendiri: `.\remotto-agent.exe pair --host 192.168.1.10`.

3. Pastikan jaringan WiFi rumah berprofil **Private**, lalu izinkan port agent. Jalankan di PowerShell sebagai Administrator:

   ```powershell
   Get-NetConnectionProfile
   New-NetFirewallRule -DisplayName "Remotto Agent" -Direction Inbound -Protocol TCP -LocalPort 8765 -Action Allow -Profile Private
   ```

   Jangan izinkan profil Public.

4. Pasang startup, dari terminal Administrator:

   ```powershell
   .\remotto-agent.exe install-startup
   ```

   Task "At log on" berjalan di sesi user tanpa hak admin. Jendela konsol bisa berkedip sekali saat login.

5. Cek jenis sleep laptop:

   ```powershell
   powercfg /a
   ```

   - Ada **Standby (S0 Low Power Idle)**: tidak perlu tindakan. Sleep mematikan layar lalu laptop masuk Modern Standby.
   - Ada **Standby (S3)**: kalau sleep malah jadi hibernate, jalankan `powercfg -h off` sebagai Administrator. Perintah ini juga mematikan Fast Startup.

**Cek agent jalan:** `Get-Process remotto-agent`.

**Log:** `%APPDATA%\Remotto\logs\agent.log`. Config: `%APPDATA%\Remotto\config.json`.

**Uninstall:**

```powershell
.\remotto-agent.exe uninstall-startup
Stop-Process -Name remotto-agent
Remove-NetFirewallRule -DisplayName "Remotto Agent"
Remove-Item -Recurse "$env:APPDATA\Remotto"
```

## Bagian C — Install app di HP

1. Sideload `remotto.apk`, atau `flutter run` dengan HP tersambung.
2. Izinkan kamera saat diminta.
3. Scan QR dari `remotto-agent pair`.

## Bagian D — Rilis & rollback

Alur rilis:

1. Semua kerja selesai di `team/*`.
2. `/merge-to-main` memeriksa syarat, menggabungkan, dan push setelah dikonfirmasi.
3. CI menjalankan `build` di `main`.
4. Unduh artefak.
5. Ganti agent:

   ```powershell
   Stop-Process -Name remotto-agent
   # salin remotto-agent.exe baru ke folder tetap
   schtasks /Run /TN "Remotto\Agent"
   ```

6. Install APK baru di HP.

**Rollback:** pasang artefak versi sebelumnya dengan langkah yang sama. Artefak CI punya masa simpan terbatas, jadi simpan salinan versi yang stabil.

**HP hilang:** `.\remotto-agent.exe reset-token`. Token lama langsung tidak berlaku. Jalankan `pair` dan scan ulang di HP lain.

## Bagian E — Akses dari luar rumah

Jangan port-forward port agent ke internet.

1. Pasang Tailscale di laptop dan HP, dengan akun yang sama.
2. Lihat IP Tailscale laptop: `tailscale ip -4`.
3. Pairing dengan IP tersebut:

   ```powershell
   .\remotto-agent.exe pair --host 100.x.y.z
   ```

4. Aturan firewall hanya berlaku di profil Private, jadi cek profil adapter Tailscale dengan `Get-NetConnectionProfile`. Kalau Public, ubah sebagai Administrator:

   ```powershell
   Set-NetConnectionProfile -InterfaceAlias Tailscale -NetworkCategory Private
   ```

App hanya menyimpan satu laptop, jadi berpindah antara IP LAN dan IP Tailscale berarti pairing ulang.
