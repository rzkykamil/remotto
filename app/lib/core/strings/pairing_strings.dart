/// Pairing copy (Q01-Q12). Source: `design/export/artboards/Pairing-light.dc.html`
/// and `States-light.dc.html`. Do not invent copy outside the artboards.
abstract final class PairingStrings {
  // Umum
  static const back = 'Kembali';

  // Q01 intro
  static const introTagline = 'Kontrol laptop dari kasur.';
  static const introStep1 = 'Nyalain agent Remotto di laptop.';
  static const introStep2 = 'Scan QR yang muncul di layar laptop.';
  static const introStep3 = 'Udah. Play, volume, sleep dari HP.';
  static const scanQr = 'Scan QR';
  static const manualLink = 'Isi manual';

  // Q02 camera permission
  static const permTitle = 'Pinjem kamera bentar';
  static const permBody =
      'Cuma buat scan QR dari layar laptop. Nggak ada foto yang disimpan.';
  static const permAllow = 'Izinkan kamera';
  static const permManualLink = 'Isi manual aja';

  // Q03 / Q04 scan
  static const scanHint = 'Arahkan ke QR di layar laptop';
  static const scanInvalidBanner =
      'QR-nya bukan dari Remotto. Coba QR di aplikasi laptop.';
  // Label Semantics tombol back dan senter (belum ada di artboard, keputusan M1).
  static const scanBack = 'Kembali';
  static const scanTorch = 'Senter';

  // Q05 permission permanently denied
  static const deniedTitle = 'Kamera dimatiin buat Remotto';
  static const deniedBody =
      'Nyalain izin kamera di pengaturan HP, atau ketik alamat & token manual.';
  static const deniedOpenSettings = 'Buka pengaturan HP';
  static const deniedManualLink = 'Isi manual';

  // Q06 / Q07 manual input
  static const manualTitle = 'Ketik yang muncul di laptop';
  static const manualBody =
      'Buka agent Remotto di laptop, alamat dan token ada di bawah QR.';
  static const addressLabel = 'Alamat laptop';
  static const addressExample = '192.168.1.20:8765';
  static const addressFormatError =
      'Formatnya kayak 192.168.1.20 atau 192.168.1.20:8765';
  static const tokenLabel = 'Token';
  static const tokenPlaceholder = 'Tempel token dari laptop';
  static const tokenFormatError = 'Tokennya 64 karakter, huruf a–f dan angka';
  static const tokenShow = 'Tampilkan token';
  static const tokenHide = 'Sembunyikan token';
  static const connect = 'Sambungkan';

  // Q08 connection test
  static const testingTitle = 'Lagi nyambung…';
  static const testStepFound = 'Laptop ketemu';
  static const testStepToken = 'Cek token';
  static const testStepSave = 'Simpan sambungan';
  static const cancel = 'Batal';

  // Q09 success
  static const successKicker = 'NYAMBUNG';
  static const successBody =
      'Sambungan disimpan. Lain kali buka app langsung ke remote.';
  static const successStart = 'Mulai pakai';

  // Q10 laptop not found (step 1 failed)
  static const timeoutTitle = 'Laptop nggak ketemu';
  static const timeoutTip1 = 'HP dan laptop harus di WiFi yang sama.';
  static const timeoutTip2 = 'Agent Remotto di laptop lagi jalan.';
  static const timeoutTip3 = 'Firewall Windows ngizinin Remotto.';
  static const retry = 'Coba lagi';
  static const changeAddress = 'Ubah alamat';

  /// Q10 body. [address] is `host:port`, [seconds] the step timeout.
  static String timeoutBody({required String address, required int seconds}) =>
      'Udah dicoba $seconds detik di $address.';

  // Q11 token rejected (step 2 returned 401)
  static const rejectedTitle = 'Token-nya ditolak';
  static const rejectedBody =
      'Laptop nolak token ini. Mungkin token di laptop udah diganti.';
  static const rescanQr = 'Scan ulang QR';

  // Q12 connection dropped from another screen (401 during daily use)
  static const expiredTitle = 'Sambungan putus';
  static const expiredBody =
      'Token-nya udah nggak berlaku. Scan QR di laptop sekali lagi ya.';
  static const expiredAnnouncement = 'Sambungan putus, perlu pairing ulang';

  /// Q09 title. [laptopName] comes from `/status` of the agent.
  static String successTitle(String laptopName) => '$laptopName siap dikontrol';
}
