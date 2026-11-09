/// Settings copy (SCR-020 / SCR-021). Source: `design/export/artboards/`
/// `Settings-light.dc.html` and `Settings-dark.dc.html`. Do not invent copy
/// outside the artboards.
abstract final class SettingsStrings {
  static const title = 'Pengaturan';

  // Section captions (mono, uppercase).
  static const laptopCaption = 'LAPTOP';
  static const displayCaption = 'TAMPILAN';

  // Laptop card.
  static const uptimeLabel = 'Nyala sejak';
  static const repairPairing = 'Pairing ulang';
  static const statusOnline = 'NYAMBUNG';
  static const statusOffline = 'NGGAK KEJANGKAU';

  /// Shown in place of the uptime when no status has been received yet.
  /// Used by the Settings laptop card (`formatUptimeLong` returns text only
  /// for a known duration).
  static const uptimeUnknown = '—';

  /// Semantics label of the back button in the top bar.
  static const backSemantics = 'Kembali ke remote';

  // Theme segmented control.
  static const themeLabel = 'Tema';
  static const themeLight = 'Terang';
  static const themeDark = 'Gelap';
  static const themeSystem = 'Sistem';

  // Haptic switch.
  static const hapticLabel = 'Getar saat ditekan';
  static const hapticOn = 'Nyala · kerasa saat tombol ditekan';
  static const hapticOff = 'Mati';

  // Repair confirmation sheet (SCR-021).
  static const repairSheetTitle = 'Pairing ulang?';
  static const repairSheetConfirm = 'Hapus & pairing ulang';
  static const repairSheetCancel = 'Nggak jadi';

  /// Sheet body. [laptopName] comes from `/status` of the agent.
  static String repairSheetBody(String laptopName) =>
      'Sambungan ke $laptopName bakal dihapus dari HP ini. '
      'Habis itu kamu perlu scan QR lagi.';
}
