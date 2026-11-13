# System Architecture

```mermaid
flowchart TB
  subgraph HP[HP Android atau iOS]
    UI[Widget + primitif lib/ui]
    ST[State Riverpod]
    CC[ConnectionController]
    RP[Repository HTTP]
    SS[(Secure storage)]
    PF[(Preferences)]
    DS[Discovery nsd + validasi kandidat]
    UI --> ST
    ST --> RP
    CC --> RP
    CC --> DS
    DS --> RP
    ST --> PF
    RP --> SS
  end

  subgraph NET[Jaringan]
    LAN[WiFi LAN]
    MD[mDNS: _remotto._tcp]
    TS[Tailscale, opsional]
  end

  subgraph WIN[Laptop Windows, sesi user]
    TSK[Task Scheduler: At log on]
    subgraph AG[remotto-agent.exe]
      MW[Middleware: recover, log, filter jaringan, rate limit, auth]
      H[Handler internal/server]
      D[Domain internal/control]
      SC[Scheduler daya]
      FK[Interface OS]
      DA[Iklan mDNS internal/discovery]
      MW --> H
      H --> D
      D --> SC
      D --> FK
      SC --> FK
    end
    subgraph OSL[Lapisan OS internal/oswin]
      IN[Input: SendInput]
      AU[Audio: pekerja COM Core Audio]
      PW[Power: shutdown, SC_MONITORPOWER, SetSuspendState]
    end
    CFG[(config.json)]
    LOG[(agent.log)]
    FW[Windows Firewall: profil Private]
    FK --> IN
    FK --> AU
    FK --> PW
    MW --> LOG
    CFG --> MW
    TSK -->|menjalankan run --background| AG
  end

  RP -->|HTTP JSON + Bearer token| LAN
  RP -.->|IP Tailscale| TS
  DS -.->|cari service| MD
  DA -.->|iklan, tanpa token| MD
  LAN --> FW
  TS -.-> FW
  FW --> MW
```

## Catatan

- Agent dan app hanya berkomunikasi lewat HTTP; tidak ada komponen lain.
- `internal/control` tidak mengetahui Windows. Implementasi OS hanya di `internal/oswin`.
- Task Scheduler menjalankan agent di sesi user, karena session 0 tidak bisa mengirim media key.
- Tailscale opsional dan tanpa perubahan kode. Port agent tidak pernah di-forward ke internet.
- Discovery hanya mDNS di LAN. Iklan tidak pernah memuat token; alur lengkap ada di `docs/flows/discovery-flow.md`.
- `pair` dan `reset-token` adalah proses terpisah yang membaca atau menulis `config.json`. Agent yang berjalan mendeteksi perubahan token lewat waktu modifikasi file.
