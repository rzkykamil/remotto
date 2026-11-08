# Menunggu pemilik

Hal yang hanya bisa dicek dengan laptop dan HP sungguhan. Simpan pekerjaan sebelum mengetes sleep, restart, dan shutdown.

## M0 Fondasi Proyek

- [ ] M0: Tampilan dasar app enak dilihat di HP, terang dan gelap.
  Buka: app Remotto di HP.
  Lakukan: ganti tema HP ke terang, lalu ke gelap.
  Harusnya: warna hangat, tidak ada teks yang susah dibaca, dan kaca terlihat halus.

- [ ] M0: Efek kaca tidak bikin app patah-patah.
  Buka: app Remotto di HP paling lemah yang kamu punya.
  Lakukan: pindah-pindah layar dan buka sheet beberapa kali.
  Harusnya: gerakan tetap mulus.

- [ ] M0: Ikon Remotto di launcher HP terlihat benar.
  Buka: layar utama HP (launcher), lalu lihat ikon Remotto.
  Lakukan: lihat ikonnya di launcher, lalu perkecil ukuran ikon/tampilan di pengaturan HP kalau bisa (sekitar 48 dp).
  Harusnya: bentuk ikon utuh (bulat atau kotak membulat sesuai HP), tidak terpotong, dan titik-titik kecilnya masih terbaca.

- [ ] M0: Bobot font Geist terbaca berbeda.
  Buka: app Remotto di HP.
  Lakukan: lihat teks di layar placeholder. M0 hanya punya layar placeholder, jadi pengecekan ini terbatas; ulangi saat M1 sudah punya layar nyata.
  Harusnya: teks tampil dengan font Geist, dan bobot Regular, Medium, SemiBold, Bold terlihat berbeda.

- [ ] M0: Latar cahaya, kaca, ring fokus, dan skala tekan terlihat benar di HP terang dan gelap, tanpa jank.
  Buka: app Remotto di HP, dalam mode terang lalu gelap.
  Lakukan: tekan dan tahan elemen yang bisa ditekan, lalu pindah layar. Di M0 kaca dan tombol hanya ada di komponen uji, jadi ulangi saat M1 dan M2.
  Harusnya: latar punya dua cahaya lembut, kaca tampak halus, ring fokus 3 dp terlihat, tombol mengecil sedikit saat ditekan, dan tidak ada patah-patah.

- [ ] M0: Transisi layar dan tombol back sistem di placeholder. Boleh ditunda ke M2 atau M5.
  Buka: app Remotto di HP.
  Lakukan: pindah antar layar placeholder (lewat tombol di M2 atau M5 nanti) lalu tekan tombol back HP.
  Harusnya: layar bergeser naik dengan fade, dan back dari Remote keluar app sementara back dari Pengaturan kembali ke Remote.

- [ ] M0: Build iOS berhasil di Mac.
  Buka: Mac dengan Xcode, folder `app/` dari repo ini.
  Lakukan: jalankan `flutter build ios`, lalu tambahkan `PERMISSION_CAMERA=1` di `GCC_PREPROCESSOR_DEFINITIONS` pada `post_install` di Podfile.
  Harusnya: build berhasil, app hanya mode potret, ikon AppIcon terpasang, dan izin kamera serta jaringan lokal punya teks penjelasan di Info.plist.

- [ ] M0: Build APK debug berhasil di laptop ini.
  Buka: PowerShell di laptop, folder `app/` dari repo ini.
  Lakukan: jalankan `flutter doctor --android-licenses` dan terima semua lisensi, lalu jalankan `flutter build apk --debug`. Unduhan NDK 28.2 bisa sangat lambat, jadi sabar atau ulangi.
  Harusnya: build berhasil dan muncul file APK debug di `app/build/app/outputs/`.

- [ ] M0: Agent menyala dan berhenti bersih di laptop.
  Buka: PowerShell di laptop, folder `agent` dari repo ini.
  Lakukan: jalankan `go run ./cmd/agent run`, tunggu sebentar, lalu tekan Ctrl+C. Buka file `%APPDATA%\Remotto\logs\agent.log` lewat File Explorer.
  Harusnya: konsol dan file log sama-sama berisi baris JSON "server started" dan "server stopped"; ada satu peringatan "config file not found" karena belum ada `config.json`. "server stopped" muncul dalam sekitar 3 detik setelah Ctrl+C. Folder dan file log dibuat otomatis. Belum ada endpoint, jadi membuka alamat agent di browser hanya menampilkan `not_found`.

- [ ] M0: Build agent memakai Go 1.27 dan perintah `version` berjalan.
  Buka: PowerShell di laptop, folder `agent` dari repo ini.
  Lakukan: jalankan `go version`, lalu `go build -o bin/remotto-agent.exe ./cmd/agent`, lalu `bin\remotto-agent.exe version`.
  Harusnya: `go version` menyebut go1.27.x (toolchain terunduh otomatis pertama kali), build berhasil, dan `version` mencetak `remotto-agent dev`.

- [ ] M0: Job `agent-test` di GitHub Actions hijau setelah push.
  Buka: browser, halaman repo Remotto di GitHub, tab Actions.
  Lakukan: buka run terbaru untuk branch `team/m0-fondasi-proyek`, lalu lihat job `agent-test`, khususnya langkah cache `setup-go`.
  Harusnya: job hijau. Cache `setup-go` memakai `agent/go.sum` yang kosong; kalau langkah itu gagal, catat pesannya.

## M1 Pairing & Koneksi

- [ ] M1: Scan QR dengan kamera HP berhasil.
  Buka: terminal di laptop, dan app Remotto di HP → layar pairing.
  Lakukan: jalankan `remotto-agent pair`, lalu scan QR di terminal.
  Harusnya: muncul "berhasil" dan masuk ke layar Remote.

- [ ] M1: Windows Firewall mengizinkan jaringan Private.
  Buka: PowerShell Administrator di laptop.
  Lakukan: jalankan perintah firewall di `docs/release.md` Bagian B, lalu buka app di HP.
  Harusnya: status di app "Nyambung".

- [ ] M1: Alamat di QR benar walau laptop punya banyak adapter jaringan.
  Buka: teks di bawah QR pada terminal laptop.
  Lakukan: bandingkan alamatnya dengan IP WiFi di Pengaturan Windows.
  Harusnya: alamatnya sama.

- [ ] M1: Indikator online dan offline jujur.
  Buka: app Remotto di HP → layar Remote.
  Lakukan: matikan WiFi laptop, tunggu sebentar, lalu nyalakan lagi.
  Harusnya: berubah ke "Nggak kejangkau", lalu "Nyambung lagi".

- [ ] M1: Kamera ditolak tetap ada jalan keluar.
  Buka: pengaturan aplikasi di HP.
  Lakukan: cabut izin kamera Remotto, lalu buka layar scan.
  Harusnya: muncul pilihan "Buka pengaturan HP" dan "Isi manual".

- [ ] M1: QR asli terbaca dari kamera, dengan senter dan getar.
  Buka: app Remotto di HP, layar Scan QR, dan QR yang tampil di layar laptop.
  Lakukan: arahkan kamera ke QR asli, lalu nyalakan senter. Coba juga dengan QR gambar lain.
  Harusnya: QR asli langsung terbaca dan lanjut ke tes. QR lain memunculkan banner "QR tidak valid" selama sekitar 3 detik. Senter menyala dan HP bergetar saat QR terbaca.

- [ ] M1: Izin kamera ditolak sekali, lalu ditolak permanen.
  Buka: app Remotto di HP (layar Izinkan kamera), dan pengaturan izin kamera HP.
  Lakukan: tolak izin sekali, lalu coba lagi. Lalu tolak permanen (di Android, centang "jangan tanya lagi" bila ada), buka app lagi.
  Harusnya: setelah ditolak sekali tetap di layar Izinkan kamera. Setelah permanen muncul "Buka pengaturan HP". Setelah izin diberikan dan app dibuka lagi, langsung masuk ke scan.

- [ ] M1: Tampilan layar pairing dan Remote sesuai artboard, terang dan gelap.
  Buka: app Remotto di HP, dan file di `design/export/artboards/` di laptop sebagai pembanding.
  Lakukan: jalani alur pairing dari awal sampai layar sukses, lihat juga layar gagal dan Remote saat putus. Ulangi dengan tema gelap. Selama backend belum ada, app masih memakai data tiruan: alamat `10.0.0.1` menampilkan layar gagal (timeout), dan token berisi 64 angka nol menampilkan layar token ditolak.
  Harusnya: warna, teks, dan susunan tiap layar mirip artboard. Tidak ada tombol yang terlihat palsu di layar Remote.

- [ ] M1: Mengetik alamat dan menempel token di HP.
  Buka: layar Isi manual di app.
  Lakukan: ketik alamat, tempel token 64 karakter dari papan klip, lalu coba token yang kurang satu karakter.
  Harusnya: keyboard alamat menampilkan angka dan titik. Token bisa ditempel. Token salah menampilkan pesan "Tokennya 64 karakter, huruf a–f dan angka". Tombol "Sambungkan" aktif hanya saat kedua kolom terisi.

- [ ] M1: Pembaca layar membacakan layar pairing dengan urutan masuk akal.
  Buka: TalkBack di HP Android atau VoiceOver di iPhone, lalu app Remotto.
  Lakukan: jelajahi judul, langkah, banner QR tidak valid, tombol mata token, dan toast "Laptop nyambung lagi".
  Harusnya: judul terbaca sebagai judul, tombol mata terbaca "Tampilkan token" atau "Sembunyikan token", pesan error dibacakan, dan toast tidak mengganggu.

- [ ] M1: Tombol back HP di layar pairing.
  Buka: app Remotto di HP, layar Scan QR atau Isi manual.
  Lakukan: tekan tombol back HP dari Scan, dari Isi manual, dan dari layar pertama pairing.
  Harusnya: dari Scan atau Isi manual kembali ke layar pertama. Dari layar pertama app keluar.

- [ ] M1: Layar pairing dan Remote muat di HP kecil dengan teks besar.
  Buka: HP ukuran kecil (lebar sekitar 360 dp), dan pengaturan ukuran font HP sekitar 130%.
  Lakukan: buka layar pertama pairing, layar Isi manual, layar tes, dan layar Remote.
  Harusnya: tidak ada teks terpotong, tombol utama tetap terlihat dan bisa digulir, dan tidak ada yang tumpang tindih.

- [ ] M1: Pill status di HP kecil dengan teks besar tetap rapi.
  Buka: HP ukuran kecil dengan font 130%, layar Remote.
  Lakukan: lihat pill saat laptop "Nyambung" dan saat "Nggak kejangkau".
  Harusnya: pill tetap di dalam layar. Kalau teks terlalu panjang, ujungnya berakhir dengan "…" dan tidak keluar dari layar.

- [ ] M1: Alamat IP publik di input manual.
  Buka: layar Isi manual di app.
  Lakukan: ketik alamat `8.8.8.8`, lalu pindah ke kolom token.
  Harusnya: muncul pesan kesalahan alamat yang sama dengan format lain. Kalau mau pesan khusus untuk alamat seperti ini, beri tahu tulisannya.

- [ ] M1: Uptime di bawah 1 jam di pill.
  Buka: layar Remote di HP, saat laptop baru menyala (kurang dari 1 jam).
  Lakukan: lihat tulisan di pill status.
  Harusnya: tertulis dengan menit saja, misalnya "NYAMBUNG · 12M". Kalau mau format lain, beri tahu.

- [ ] M1: Pairing ulang tidak menghapus sambungan lama.
  Buka: layar Remote di HP yang sudah tersambung ke laptop.
  Lakukan: matikan WiFi laptop sampai status "Nggak kejangkau", tekan "Pairing ulang", lalu tekan back sampai keluar dari pairing. Buka app lagi.
  Harusnya: sambungan lama masih ada dan app kembali ke layar Remote dengan status yang sesuai.

- [ ] M1 Backend: Izin file config hanya milik akun kamu, dan agent memperbaikinya sendiri.
  Buka: PowerShell di laptop, folder `agent` dari repo ini. Lalu File Explorer ke `%APPDATA%\Remotto\`.
  Lakukan: jalankan `icacls "$env:APPDATA\Remotto\config.json"` dan catat daftarnya. Lalu klik kanan `config.json` → Properties → Security → Edit → Add, tambahkan "Everyone" (atau "Semua") dengan izin Read, lalu OK. Jalankan `go run ./cmd/agent run` sebentar, tekan Ctrl+C, lalu jalankan `icacls` lagi dan buka `%APPDATA%\Remotto\logs\agent.log`.
  Harusnya: setelah agent jalan, izin file hanya akun kamu lagi, dan `agent.log` memuat peringatan izin diperbaiki. Token tidak terlihat di log.

- [ ] M1 Backend: Token lama langsung ditolak tanpa restart agent.
  Buka: PowerShell di laptop (agent sedang jalan lewat `go run ./cmd/agent run`), dan Notepad untuk `%APPDATA%\Remotto\config.json`.
  Lakukan: catat token lama, ganti isi `"token"` dengan 64 karakter lain (huruf a–f dan angka), simpan. Di PowerShell lain jalankan `Invoke-WebRequest http://127.0.0.1:8765/api/v1/status -Headers @{Authorization="Bearer <token lama>"}`, lalu ulangi dengan token baru.
  Harusnya: token lama dibalas 401 tanpa restart agent, token baru dibalas 200. Jangan bagikan token ke siapa pun.

- [ ] M1 Backend: `remotto-agent pair` tanpa `--host` memilih IP WiFi yang benar dan QR terbaca.
  Buka: PowerShell di laptop, folder `agent`. Pengaturan Windows → Network & internet → Wi-Fi → Properties untuk IP WiFi.
  Lakukan: jalankan `go run ./cmd/agent pair` tanpa `--host`, lalu bandingkan alamat yang tercetak dengan IP WiFi. Kalau ada WSL atau Hyper-V terpasang, pastikan alamatnya bukan IP adapter virtual. Scan QR-nya dari app di HP.
  Harusnya: alamat sama dengan IP WiFi, adapter WSL atau Hyper-V terlewati, dan QR terbaca sampai app menampilkan berhasil.

- [ ] M1 Integrasi: Pairing manual dengan agent asli sampai layar berhasil.
  Buka: terminal di laptop (agent jalan lewat `go run ./cmd/agent run`), dan layar Isi manual di app HP.
  Lakukan: isi alamat IP WiFi laptop dan token dari `%APPDATA%\Remotto\config.json`, lalu tekan Sambungkan.
  Harusnya: muncul layar berhasil dengan nama laptop yang benar, lalu layar Remote menampilkan nama dan uptime yang terus bertambah.

- [ ] M1 Integrasi: Token salah menampilkan layar token ditolak.
  Buka: layar Isi manual di app HP.
  Lakukan: isi alamat IP laptop yang benar dan token 64 karakter yang salah (misalnya semua angka 1), lalu tekan Sambungkan.
  Harusnya: muncul layar "Token ditolak" (Q11), bukan layar gagal jaringan.

- [ ] M1 Integrasi: Ganti token saat app sudah tersambung, tanpa restart agent.
  Buka: layar Remote di HP, dan Notepad untuk `%APPDATA%\Remotto\config.json` di laptop. Agent tetap jalan.
  Lakukan: ganti isi `"token"` dengan 64 karakter lain, simpan, lalu tunggu sekitar 10 detik. Perintah `reset-token` belum tersedia (M5), jadi pakai cara ini.
  Harusnya: app pindah ke layar "Token ditolak" (Q12) dan berhenti mencoba. Tanpa restart agent.

- [ ] M1 Integrasi: IP laptop salah tidak bikin app menggantung.
  Buka: layar Isi manual di app HP.
  Lakukan: isi alamat IP yang salah (misalnya `192.168.99.99`) dengan token benar, lalu tekan Sambungkan. Catat berapa lama sampai muncul pesan.
  Harusnya: sekitar 5 detik muncul layar "Nggak kejangkau" (Q10), tidak berputar terus.

- [ ] M1 Integrasi: APK debug bisa bicara ke agent lewat HTTP di IP LAN (Android).
  Buka: PowerShell di laptop, folder `app/`, dan HP Android.
  Lakukan: jalankan `flutter build apk --debug`, pasang APK di HP, lalu pairing ke IP WiFi laptop.
  Harusnya: pairing berhasil tanpa error koneksi karena HTTP biasa (cleartext) ke alamat LAN.

- [ ] M1 Integrasi: iPhone bisa bicara ke agent lewat IP LAN dan Tailscale.
  Buka: iPhone dengan app dari Xcode, laptop dengan agent jalan, dan Tailscale aktif di kedua perangkat.
  Lakukan: pairing ke IP WiFi laptop, lalu pairing ke IP Tailscale laptop (alamat 100.x). Saat pertama kali, jawab izin jaringan lokal.
  Harusnya: muncul pertanyaan izin "Jaringan Lokal". Setelah diizinkan, kedua alamat menampilkan "Nyambung".

## M2 Kontrol Media

- [ ] M2: Play/pause mengenai Brave.
  Buka: video di Brave pada laptop, dan layar Remote di HP.
  Lakukan: tekan tombol play/pause di HP.
  Harusnya: video berhenti dalam sekejap, tekan lagi jalan lagi.

- [ ] M2: Play/pause, next, dan prev mengenai Spotify, langsung lewat agent.
  Buka: Spotify di laptop yang sudah menjalankan agent hasil build, dan layar Remote di HP. Tombol HP sudah lewat agent asli, jadi bisa juga pakai Postman atau PowerShell dengan token pairing.
  Lakukan: putar lagu, lalu tekan play/pause, next, dan prev di HP. Lewat Postman atau PowerShell: kirim POST ke `/api/v1/media/play-pause`, lalu `/api/v1/media/next` dan `/api/v1/media/prev`.
  Harusnya: lagu berhenti, pindah ke berikutnya, dan kembali. Respons 200 berisi nama aksinya, misalnya `{"data":{"action":"next"}}`.

- [ ] M2: Perilaku saat laptop terkunci sudah jelas.
  Buka: lagu yang sedang jalan di laptop, dan layar Remote di HP. Atau Postman atau PowerShell dengan token pairing.
  Lakukan: kunci laptop dengan Win+L, lalu tekan play/pause di HP, atau kirim POST `/api/v1/media/play-pause` lewat Postman atau PowerShell.
  Harusnya: kalau lagu tidak berhenti, HP menampilkan pesan gagal, bukan diam saja. Lewat Postman atau PowerShell, respons harus 500 dengan kode `media_failed`, bukan 200.

- [ ] M2: Getar terasa pas.
  Buka: layar Remote di HP.
  Lakukan: tekan play, next, dan prev.
  Harusnya: getar terasa singkat tepat saat jari menyentuh.

- [ ] M2 Frontend: Dock media di HP fisik mirip desain, lebar 412 dp dan 360 dp, terang dan gelap.
  Buka: app Remotto di HP (layar Remote), dan file di `design/export/artboards/` di laptop sebagai pembanding: Remote-412-dark, Remote-360-light, dan States-light (S01, S03, S04, S10).
  Lakukan: bandingkan dock media dengan artboard, lalu ganti tema HP ke terang dan gelap. Tombol media sudah lewat agent asli, jadi agent di laptop harus menyala.
  Harusnya: susunan prev, play, dan next mirip artboard, warna cocok, tidak ada yang terpotong atau tumpang tindih.

- [ ] M2 Frontend: Getar saat tombol media ditekan.
  Buka: layar Remote di HP.
  Lakukan: tekan play, prev, dan next, satu per satu.
  Harusnya: tiap tekan terasa satu getaran singkat tepat saat jari menyentuh. Getar gagal dicoba dengan mematikan agent, lihat item M2 Integrasi.

- [ ] M2 Frontend: Kedip ikon, cincin proses, dan posisi toast.
  Buka: layar Remote di HP.
  Lakukan: tekan prev dan next, lihat ikonnya berkedip. Tekan play; cincin proses hanya muncul bila jawaban lebih dari sekitar 0,4 detik, dan agent di laptop biasanya lebih cepat, jadi cincin mungkin tidak terlihat. Toast "Perintah nggak sampai ke laptop" muncul saat agent mati, lihat item M2 Integrasi.
  Harusnya: kedip ikon sekitar 240 ms (sekejap). Cincin berputar sekitar 0,4 detik setelah tekan bila jawaban lambat. Toast muncul 12 dp di atas dock.

- [ ] M2 Integrasi: Tombol media HP mengenai laptop lewat agent asli.
  Buka: Spotify di laptop (agent jalan lewat `go run ./cmd/agent run`), dan layar Remote di HP yang sudah pairing.
  Lakukan: tekan play, next, dan prev di HP. Lalu matikan agent (Ctrl+C), tekan play lagi. Nyalakan agent lagi, lalu tekan "Ulangi". Terakhir, ganti isi `"token"` di `config.json`, simpan, lalu tekan next.
  Harusnya: lagu mengikuti tiap tombol. Saat agent mati, ikon kembali dan muncul toast "Perintah nggak sampai ke laptop" beserta "Ulangi". "Ulangi" berhasil saat agent hidup lagi. Setelah token diganti, app menampilkan layar "Token ditolak" (Q12). Saat ditekan cepat, tidak ada perintah ganda.

## M3 Volume

- [ ] M3: Volume laptop mengikuti slider.
  Buka: lagu di laptop, dan layar Remote di HP.
  Lakukan: geser slider pelan, lalu cepat.
  Harusnya: suara laptop ikut berubah dan angkanya sama dengan ikon volume Windows.

- [ ] M3: Tombol − / + dan mute bekerja.
  Buka: layar Remote di HP.
  Lakukan: tekan + dua kali, − sekali, lalu mute.
  Harusnya: volume naik 10, turun 5, lalu laptop bisu.

- [ ] M3: Perubahan dari laptop terbaca di HP.
  Buka: layar Remote di HP.
  Lakukan: ubah volume dari ikon speaker Windows.
  Harusnya: angka di HP ikut berubah dalam beberapa detik.

- [ ] M3: Volume mengikuti perangkat suara yang dipakai.
  Buka: laptop dengan headset, dan layar Remote di HP.
  Lakukan: colok atau sambungkan headset, lalu geser slider.
  Harusnya: volume headset yang berubah.

- [ ] M3: Slider nyaman di HP kecil.
  Buka: layar Remote di HP sekitar 360 dp, kalau ada.
  Lakukan: atur volume dengan satu jempol.
  Harusnya: mudah dipakai, dan layar pendek tetap rapi.

- [ ] M3 Frontend: Panel volume di HP fisik mirip desain, lebar 412 dan 360 dp, terang dan gelap, serta angka dan layar pendek.
  Buka: app Remotto di HP (layar Remote, setelah Integrasi M3 selesai), dan file di `design/export/artboards/` di laptop sebagai pembanding: Remote-412-dark, Remote-360-light, dan States-light (S01, S05, S07, S08, S09, S12). Syarat sudah terpenuhi setelah Integrasi M3: pasang APK baru dari build ini, karena provider volume asli sudah ada.
  Lakukan: bandingkan panel volume dengan artboard, lalu ganti tema HP ke terang dan gelap. Pastikan agent di laptop menyala.
  Harusnya: susunan dan warna mirip artboard, angka besar (128, 108 di layar 360 dp) terbaca, badge BISU hanya muncul saat laptop dibisukan, dan tidak ada yang terpotong atau tumpang tindih.

- [ ] M3 Frontend: Rasa geser slider, haptic, dan tap-lompat.
  Buka: layar Remote di HP (setelah Integrasi M3 selesai).
  Lakukan: geser slider pelan, lalu cepat, lalu tahan di tengah. Ketuk track di beberapa titik.
  Harusnya: track menebal sedikit saat ditarik (60 ke 68 dp) dan handle hanya tampak di atas 6%. Getar tipis tiap kelipatan 5% dan getar di 0 dan 100%. Tap-lompat langsung pindah tanpa getar tiap 5%.

- [ ] M3 Frontend: Toast S06 dan animasi rollback.
  Buka: layar Remote di HP (setelah Integrasi M3 selesai). Matikan agent di laptop dulu supaya kirim gagal.
  Lakukan: geser slider saat agent mati, lalu lihat slider dan angkanya. Ulangi dengan mode animasi dikurangi di pengaturan HP.
  Harusnya: slider dan angka kembali ke nilai terakhir dalam sekitar 120 ms. Toast "Volume nggak kekirim, balik ke N%" dengan tombol "Ulangi" muncul 12 dp di atas dock dan tidak menutupi tombol. Animasi balik tetap jalan walau animasi dikurangi.

- [ ] M3 Aksesibilitas: TalkBack dan VoiceOver pada slider volume, dan urutan fokusnya.
  Buka: TalkBack di HP Android atau VoiceOver di iPhone, lalu layar Remote (setelah Integrasi M3 selesai).
  Lakukan: jelajahi grup volume, slider, mute, −, dan +. Di slider, naik dan turun dengan gerakan geser ke atas dan ke bawah.
  Harusnya: slider terbaca "Volume, N persen" sesuai nilai, dan tiap geser naik atau turun 5. Urutannya slider, mute, −, lalu +. Cek apakah "Volume" terbaca dua kali karena grup dan slider sama-sama berlabel "Volume". Bila iya, catat pembacaannya.

- [ ] M3 Frontend: Ambang layar pendek 700 dp di HP nyata.
  Buka: layar Remote di HP dengan tinggi layar dekat 700 dp (setelah Integrasi M3 selesai).
  Lakukan: lihat hint dan angka volume di HP yang tingginya di bawah 700 dp, lalu di HP yang lebih tinggi.
  Harusnya: di bawah 700 dp hint hilang dan angka mengecil (96). Di atasnya hint tampak. Tidak ada yang terpotong. Bila ambang 700 dp tidak pas, catat tinggi layarnya.

- [ ] M3 Backend: Volume lewat Postman ke agent asli.
  Buka: laptop Windows, jalankan agent dengan `cd agent && go run ./cmd/agent run` di terminal. Buka Postman dengan environment `Remotto Agent`, lalu folder Volume.
  Lakukan: kirim GET `/volume`, lalu PUT `/volume` dengan level 35. Kirim POST `/volume/up` dua kali, lalu `/volume/down` sekali. Kirim POST `/volume/mute` dengan `true`, lalu `false`. Terakhir kirim PUT `/volume` dengan level 101, lalu 35.5. Setelah itu buka `GET /status` dan lihat isi `volume`. Opsional: colok headset, lalu ulangi PUT `/volume` dan lihat perangkat mana yang berubah.
  Harusnya: angka sama dengan ikon volume Windows. Up dan down berubah 5. Mute menyalakan dan mematikan ikon speaker. Level 101 dan 35.5 ditolak dengan 400 dan kode `invalid_level`. `GET /status` memuat `volume` yang sama, bukan null. Saat headset dicolok, perubahan mengenai headset.

- [ ] M3 Integrasi: Volume laptop mengikuti slider dan tombol lewat agent asli.
  Buka: agent jalan lewat `go run ./cmd/agent run` di laptop, laptop sedang memutar musik, dan layar Remote di HP yang sudah pairing.
  Lakukan: geser slider, tekan − dan +, lalu tekan mute dua kali. Ubah volume dari ikon speaker Windows dan tunggu beberapa detik. Matikan agent (Ctrl+C), geser slider, lalu nyalakan agent lagi dan tekan "Ulangi". Terakhir, ganti isi `"token"` di `config.json`, simpan, lalu tekan +.
  Harusnya: volume laptop mengikuti tiap aksi, dan perubahan dari laptop terbaca di HP. Saat agent mati, toast "Volume nggak kekirim" muncul dan slider kembali ke nilai terakhir. "Ulangi" berhasil saat agent hidup lagi. Setelah token diganti, muncul layar "Token ditolak" (Q12). Saat ditekan cepat, tidak ada perintah ganda.

- [ ] M3 Fixing: geser slider dan tombol −/+ tidak lagi memunculkan toast gagal di laptop ini.
  Buka: PowerShell di laptop, folder `agent`; app Remotto di HP (layar Remote); File Explorer ke `%APPDATA%\Remotto\logs\agent.log`.
  Lakukan: hentikan agent lama (Ctrl+C atau tutup prosesnya) bila masih jalan. Jalankan `go build -o bin/remotto-agent.exe ./cmd/agent`, lalu `bin\remotto-agent.exe run`. Pastikan laptop tidak bisu, geser slider di HP pelan lalu cepat, tekan + dua kali dan − sekali. Lalu tekan mute di HP, kemudian geser slider atau tekan +, dan bandingkan dengan ikon speaker Windows. Terakhir buka agent.log dan cari "audio failed".
  Harusnya: volume laptop berubah dan tidak ada toast "Volume nggak kekirim" atau angka loncat balik saat tidak bisu. Setelah mute lalu geser atau +, laptop kembali bersuara (BR-15). Kalau muncul toast di langkah itu, lihat `cause` di log dan kabari: artinya SetMute(false) memang gagal di perangkat ini saat sedang bisu. Tombol mute tetap bekerja seperti sebelumnya. agent.log tidak boleh punya baris "audio failed" baru untuk geser slider atau −/+ saat tidak bisu.

## M4 Daya

- [ ] M4: Sleep benar-benar menidurkan laptop.
  Buka: layar Remote di HP. Simpan pekerjaan dulu.
  Lakukan: buka PowerShell di laptop dan jalankan `powercfg /a`, catat hasilnya. Lalu tekan Sleep di HP, konfirmasi, dan tunggu hitung mundur. Setelah itu buka `%APPDATA%\Remotto\logs\agent.log` lewat File Explorer dan cari baris `sleep path chosen`.
  Harusnya: layar laptop mati lalu laptop masuk Modern Standby, bukan hibernate atau tetap menyala. Baris `sleep path chosen` menyebut jalur AoAc. Perhatikan: apakah lagu ikut berhenti, dan berapa lama sampai app menganggap laptop mati?

- [ ] M4: Jalur S3 (`SetSuspendState`) belum terbukti di laptop ini.
  Buka: PowerShell di laptop, lalu hasil `powercfg /a` yang tadi dicatat.
  Lakukan: lihat apakah daftar memuat "Standby (S3)". Laptop pengembangan ini hanya punya S0, jadi jalur ini hanya bisa dicek di laptop lain yang punya S3.
  Harusnya: di laptop ber-S3, sleep lewat `SetSuspendState` membuat laptop tidur dan bangun normal. Di laptop ini cukup dicatat bahwa S3 tidak tersedia.

- [ ] M4: Shutdown atau restart yang ditahan Windows tidak merusak status agent.
  Buka: Notepad di laptop (ketik sesuatu tanpa menyimpan), lalu layar Remote di HP.
  Lakukan: jalankan Matikan atau Restart dari HP, lalu di laptop pilih batal saat Windows menanyakan pekerjaan belum tersimpan. Tunggu hitung mundur selesai, lalu cek `GET /status` lewat browser di laptop (`http://127.0.0.1:<port>/status`, dengan token dari config).
  Harusnya: field `pending` kembali null, agent tetap menjawab `/status`, dan Notepad tidak kehilangan tulisan.

- [ ] M4: Offset AoAc di struct daya dicocokkan dengan SDK (opsional, teknis).
  Buka: folder SDK Windows di laptop (biasanya `C:\Program Files (x86)\Windows Kits\10\Include`), file `winnt.h`.
  Lakukan: cari `SYSTEM_POWER_CAPABILITIES` dan hitung posisi field `AoAc`. Bandingkan dengan `agent/internal/oswin/sleep_windows.go`. Bila SDK tidak ada, lewati item ini.
  Harusnya: posisi AoAc sama dengan offset 20 di kode. Bila beda, kabari untuk perbaikan.

- [ ] M4: Laptop bangun lagi dari sleep dan app tersambung sendiri.
  Buka: layar Remote di HP.
  Lakukan: bangunkan laptop dan login.
  Harusnya: app tersambung lagi tanpa pairing ulang.

- [ ] M4: Shutdown berjalan.
  Buka: layar Remote di HP. Simpan pekerjaan dulu.
  Lakukan: tekan Matikan → Lanjut → tahan sampai penuh, lalu tunggu.
  Harusnya: laptop mati, dan app menampilkan "Laptop lagi mati".

- [ ] M4: Restart berjalan.
  Buka: layar Remote di HP. Simpan pekerjaan dulu.
  Lakukan: tekan Restart → Lanjut → tahan sampai penuh, lalu tunggu.
  Harusnya: laptop restart, dan setelah login app tersambung lagi.

- [ ] M4: Batal benar-benar membatalkan.
  Buka: layar Remote di HP. Simpan pekerjaan dulu.
  Lakukan: mulai shutdown, lalu tekan Batal saat hitung mundur.
  Harusnya: laptop tetap nyala dan muncul "Nggak jadi dimatiin".

- [ ] M4: Menutup app saat hitung mundur tidak menghilangkan kendali.
  Buka: layar Remote di HP. Simpan pekerjaan dulu.
  Lakukan: mulai shutdown, tutup app, lalu buka lagi dalam 2 detik.
  Harusnya: hitung mundur muncul lagi dengan sisa waktu asli, dan Batal berfungsi.

- [ ] M4: Shutdown dengan pekerjaan belum tersimpan aman.
  Buka: Notepad di laptop, ketik sesuatu tanpa menyimpan.
  Lakukan: jalankan shutdown dari HP.
  Harusnya: Windows menahan dan menanyakan, tulisanmu tidak hilang diam-diam.

- [ ] M4: Tahan 1,2 detik terasa pas di kasur.
  Buka: sheet Matikan di HP.
  Lakukan: coba tahan dengan satu jempol sampai terasa penuh, lalu coba lepas lebih cepat di tengah, lalu geser jari keluar dari tombol sebelum penuh. Jangan tahan sampai penuh di tahap terakhir kecuali memang mau laptop mati.
  Harusnya: tidak mungkin kepencet, tapi juga tidak menyebalkan. Lepas di tengah atau geser keluar membatalkan tanpa perintah terkirim. Ada getar saat tahan penuh.

- [ ] M4 Frontend: Layar daya di HP mirip desain, lebar 360 dan 412 dp, terang dan gelap.
  Buka: app Remotto di HP (layar Remote), dan file di `design/export/artboards/` di laptop sebagai pembanding: Remote-412-dark, Remote-360-light, dan States-light (sheet daya dan hitung mundur).
  Lakukan: buka tombol Sleep, Restart, dan Matikan satu per satu sampai sheet terbuka, lalu lihat hitung mundur. Ganti tema HP ke terang dan gelap. Batalkan hitung mundur dengan tombol Batal sebelum habis.
  Harusnya: susunan dan warna mirip artboard, tidak ada yang terpotong, dan label tombol daya tidak pecah di tengah kata (misalnya "Matika-n").

- [ ] M4 Frontend: Pembaca layar membacakan tombol daya, sheet, tahan, dan hitung mundur.
  Buka: TalkBack di HP Android atau VoiceOver di iPhone, lalu app Remotto (layar Remote, sheet daya, dan hitung mundur).
  Lakukan: jelajahi tombol Sleep, Restart, dan Matikan, lalu sheet dan tombol tahan. Cari aksi "Matikan sekarang" lewat menu aksi pembaca layar. Di hitung mundur, dengarkan pengumuman dan cek fokus awal. Batalkan sebelum habis.
  Harusnya: setiap tombol terbaca jelas, aksi "Matikan sekarang" ada, fokus awal di Batal, dan pengumuman hitung mundur tidak terlalu sering.

- [ ] M4 Frontend: Layar tetap menyala selama hitung mundur, dan tombol back membatalkan.
  Buka: app Remotto di HP, layar Remote. Simpan pekerjaan di laptop dulu.
  Lakukan: atur "layar mati otomatis" HP ke waktu tersingkat. Pilih Sleep, konfirmasi, lalu diamkan HP dan lihat layarnya sampai hitung mundur tampil. Lalu tekan tombol back HP sebelum hitung mundur habis.
  Harusnya: layar tidak mati selama hitung mundur. Back membatalkan, dan laptop tetap nyala. Hitung mundur singkat, jadi bila layar mati saat diam, catat itu sebagai gagal.

## M5 Pengaturan & Tema

- [ ] M5: Tampilan di HP fisik sesuai desain, terang dan gelap.
  Buka: layar Pengaturan di HP.
  Lakukan: ganti tema Terang, Gelap, Sistem, lalu matikan getar.
  Harusnya: tema langsung berubah dan getar mati di semua tombol.

- [ ] M5: Reset token mematikan akses lama.
  Buka: terminal laptop dan layar Remote di HP.
  Lakukan: jalankan `remotto-agent reset-token`.
  Harusnya: HP langsung diarahkan ke pairing ulang.

- [ ] M5: Pembaca layar bisa mengendalikan app.
  Buka: TalkBack di HP Android, lalu app Remotto.
  Lakukan: jelajahi tombol Remote, slider, sheet daya, tahan, dan hitung mundur.
  Harusnya: semua terbaca jelas, urutannya masuk akal, dan pengumuman tidak mengganggu.

- [ ] M5: Teks besar tetap rapi.
  Buka: pengaturan ukuran font di HP.
  Lakukan: besarkan teks sampai sekitar 130%, lalu buka Remote dan Pengaturan.
  Harusnya: tidak ada teks terpotong atau tombol tumpang tindih.

## M6 Ketahanan & Startup

- [ ] M6: Agent jalan otomatis setelah login.
  Buka: PowerShell Administrator di laptop.
  Lakukan: jalankan `install-startup`, logout, lalu login lagi.
  Harusnya: tanpa membuka apa pun, app di HP tersambung.

- [ ] M6: Jendela konsol tidak mengganggu saat login.
  Buka: laptop saat login.
  Lakukan: perhatikan layar setelah login.
  Harusnya: paling banyak berkedip sekali, lalu tidak ada jendela yang tertinggal.

- [ ] M6: App pulih setelah lama di background.
  Buka: app Remotto di HP.
  Lakukan: pindah ke app lain sebentar, lalu kembali.
  Harusnya: muncul "Menyambung…" singkat, lalu normal.

- [ ] M6: APK dari CI bisa di-install.
  Buka: tab Actions di GitHub, lalu HP.
  Lakukan: unduh artefak `main`, lalu install `remotto.apk`.
  Harusnya: app terbuka normal dan ikonnya benar, termasuk di ukuran kecil.
