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

## M2 Kontrol Media

- [ ] M2: Play/pause mengenai Brave.
  Buka: video di Brave pada laptop, dan layar Remote di HP.
  Lakukan: tekan tombol play/pause di HP.
  Harusnya: video berhenti dalam sekejap, tekan lagi jalan lagi.

- [ ] M2: Play/pause, next, dan prev mengenai Spotify.
  Buka: Spotify di laptop, dan layar Remote di HP.
  Lakukan: putar lagu, lalu tekan play/pause, next, dan prev.
  Harusnya: lagu berhenti, pindah ke berikutnya, dan kembali.

- [ ] M2: Perilaku saat laptop terkunci sudah jelas.
  Buka: lagu yang sedang jalan di laptop, dan layar Remote di HP.
  Lakukan: kunci laptop dengan Win+L, lalu tekan play/pause di HP.
  Harusnya: kalau lagu tidak berhenti, HP menampilkan pesan gagal, bukan diam saja.

- [ ] M2: Getar terasa pas.
  Buka: layar Remote di HP.
  Lakukan: tekan play, next, dan prev.
  Harusnya: getar terasa singkat tepat saat jari menyentuh.

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

## M4 Daya

- [ ] M4: Sleep benar-benar menidurkan laptop.
  Buka: layar Remote di HP. Simpan pekerjaan dulu.
  Lakukan: tekan Sleep, konfirmasi, lalu tunggu hitung mundur.
  Harusnya: layar laptop mati lalu laptop masuk standby. Perhatikan: apakah lagu ikut berhenti, dan berapa lama sampai app menganggap laptop mati?

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
  Lakukan: coba tahan dengan satu jempol, lalu coba lepas lebih cepat.
  Harusnya: tidak mungkin kepencet, tapi juga tidak menyebalkan.

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
