# Discovery Flow (mDNS)

Discovery membuat app menemukan laptop lagi setelah IP berubah, misalnya saat ganti WiFi, tanpa scan QR ulang dan tanpa restart app. Syarat: HP dan laptop berada di WiFi/LAN yang sama. Token tetap wajib dan tidak pernah dikirim ke kandidat yang belum terverifikasi.

Aturan dasar:

- Hanya mDNS/DNS-SD (`_remotto._tcp`). Tidak ada UDP broadcast dan tidak ada sweep subnet.
- Port tidak berubah. Yang berubah hanya IP.
- Discovery tidak membuat endpoint HTTP baru. Verifikasi memakai `GET /status` biasa.
- Discovery nonaktif sampai `agentId` tersimpan di app (pairing lama, lihat `docs/data-design.md`).

## Iklan di agent

```mermaid
flowchart TB
  S[Agent start atau run] --> E{discovery.enabled}
  E -->|false| X[Tidak mengiklankan diri]
  E -->|true| ID{agentId kosong?}
  ID -->|ya| GEN[Buat agentId 128 bit, simpan atomik]
  ID -->|tidak| IF
  GEN --> IF[Pilih interface: Up, multicast, IPv4 privat]
  IF -->|tidak ada| WAIT[Cek ulang tiap 10 detik]
  WAIT --> IF
  IF -->|ada| REG["Daftarkan instance Remotto-(8 hex pertama agentId)<br/>port cfg.Port<br/>TXT v=1, id=agentId, name=laptopName"]
  REG -->|gagal| WARN[Catat warning, agent tetap jalan]
  REG -->|berhasil| LOOP[Poll alamat tiap 10 detik]
  LOOP --> CHG{Himpunan IPv4 privat berubah?}
  CHG -->|tidak| LOOP
  CHG -->|ya| RE[Tutup registrasi lama, daftar ulang]
  RE --> LOOP
```

Catatan:

- Token dan hash token tidak pernah masuk TXT.
- Iklan hanya di interface privat. WSL, Hyper-V, dan Tailscale dikecualikan.
- Kegagalan iklan tidak menghentikan agent. Route HTTP tetap berjalan, dan app bisa memakai scan QR ulang.

## Rediscover di app

Rediscover hanya berjalan saat RemoteScreen aktif (saat polling berjalan). Pemicunya ada empat, dan satu aturan membatasi jalur lainnya.

```mermaid
sequenceDiagram
  participant C as ConnectionController
  participant R as EndpointResolver
  participant D as Discovery (nsd)
  participant G as Kandidat agent
  participant P as Secure storage

  Note over C: Pemicu: poll gagal non-401, event WiFi/Ethernet (debounce 1 detik), resume dari background
  C->>R: rediscover(force sesuai pemicu)
  alt Pairing atau agentId belum ada (legacy)
    R-->>C: none, discovery tidak dijalankan
  else Sesi lain sedang berjalan
    R-->>C: future yang sama
  else Belum lewat 15 detik sejak sesi terakhir, bukan force
    R-->>C: none
  else Lanjut
    R->>D: find, timeout 3 detik
    D-->>R: daftar TXT dan alamat
    R->>R: Saring: v=1, id=agentId, IPv4 privat, port 1-65535, beda dari tersimpan
    loop Maks 3 kandidat
      R->>G: GET /status + token tersimpan
      alt 200 dan agentId sama
        G-->>R: status
        R->>P: Simpan host dan port baru, token dan nama tetap
        R-->>C: updated
      else 200 dan agentId beda
        G-->>R: status
        Note over R: Kandidat dibuang, tidak disimpan
      else 401 pada kandidat dengan agentId sama
        G-->>R: invalid_token
        R-->>C: tokenRejected, lalu Q12
      else Gagal lain atau timeout
        Note over R: Lanjut ke kandidat berikut
      end
    end
    R-->>C: none bila tidak ada kandidat lolos
  end
```

Akibat tiap hasil:

| Hasil | Tindakan controller |
|---|---|
| `updated` | `_failures` direset, poll langsung ke host baru. Fase tetap online, atau pindah dari offline ke back |
| `none` | Fase tidak berubah. Offline tetap offline dan polling berikutnya mencoba lagi |
| `tokenRejected` | Masuk Q12 (BR-9). Polling dan resume berhenti. Data lama dipertahankan sampai pairing baru berhasil |

## Cabang khusus

**agentId beda.** Ada laptop lain di WiFi yang sama, atau laptop yang sama sudah diganti config-nya. Kandidat dengan TXT `id` yang tidak cocok dengan `agentId` tersimpan dibuang sebelum dihubungi, dan endpoint tersimpan tidak berubah. Kandidat yang lolos filter TXT dihubungi dengan token tersimpan, lalu `agentId` di respons `/status` dicek. Bila berbeda, kandidat dibuang dan tidak ada yang disimpan. Risiko kandidat palsu yang menyalin TXT lalu menerima Bearer diterima dan dicatat sebagai R-19.

**401.** Pada kandidat dengan `agentId` yang cocok, 401 berarti token sudah di-reset (`reset-token`). Ini sama dengan 401 dari endpoint biasa: app masuk Q12. Tidak ada yang disimpan.

**Tidak ketemu.** Discovery kosong, alamat privat tidak ada, atau mDNS diblokir router atau firewall (UDP 5353 tidak diizinkan). Ini bukan error. State offline tetap tampil sebagai S10. Pemilik bisa memakai scan QR ulang lewat alur pairing (Q01).

**Hanya seluler.** Jaringan aktif bukan WiFi atau Ethernet. Rediscover dilewati, karena laptop tidak mungkin satu LAN.

**Legacy.** Pairing tanpa `agentId` tidak memakai discovery. Backfill terjadi di `_onSuccess`: setelah `GET /status` berhasil dengan token dan respons memuat `agentId`, app menyimpannya. Sesudah itu discovery aktif.

## Batas yang disengaja

- `agentId` bersifat publik. Perangkat jahat di LAN bisa menyalin TXT lalu menerima Bearer saat verifikasi. Risiko ini setara dengan R-6 dan dicatat sebagai R-19 di `docs/prd.md`. Penguatan (TLS atau challenge-response) masuk backlog.
- Discovery tidak berjalan di background. Pemicu hanya dari layar aktif, resume, dan event jaringan.
