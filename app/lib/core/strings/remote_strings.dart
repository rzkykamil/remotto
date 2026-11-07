/// Remote copy (SCR-010 states, C06 pill, C07 toast, C08 offline).
/// Source: `design/export/artboards/States-light.dc.html`.
abstract final class RemoteStrings {
  // C06 StatusPill labels
  static String pillOnline(String uptime) => 'NYAMBUNG · $uptime';
  static const pillBack = 'NYAMBUNG LAGI';
  static const pillConnecting = 'MENYAMBUNG…';
  static const pillOffline = 'NGGAK KEJANGKAU';
  static const pillOff = 'LAGI MATI';

  // C06 Semantics per varian: tanpa uptime, dibacakan saat status berubah.
  static const pillOnlineA11y = 'Nyambung';
  static const pillBackA11y = 'Nyambung lagi';
  static const pillConnectingA11y = 'Menyambung';
  static const pillOfflineA11y = 'Nggak kejangkau';
  static const pillOffA11y = 'Laptop lagi mati';

  // C08 OfflineContent
  static const offlineTitle = 'Laptop nggak kejangkau';
  static const offlineBody =
      'Pastikan HP dan laptop satu WiFi, dan laptop lagi nyala.';
  static const offlineRetry = 'Coba lagi';
  static const offlineRetrying = 'Nyoba…';
  static const repairPairing = 'Pairing ulang';

  /// Title for the powered-off state (P15, M4).
  static const poweredOffTitle = 'Laptop lagi mati';

  // S02 hint while connecting
  static const hintWaiting = 'Nunggu jawaban dari laptop…';

  // Toasts
  static const toastBackOnline = 'Laptop nyambung lagi';
  static const toastCommandFailed = 'Perintah nggak sampai ke laptop';
  static const toastRetry = 'Ulangi';

  static const settingsButton = 'Pengaturan';

  // SCR-010 media dock (C03, C10)
  static const playLabel = 'Putar';
  static const pauseLabel = 'Jeda';
  static const playSendingHint = 'Ngirim ke laptop';
  static const prevLabel = 'Lagu sebelumnya';
  static const nextLabel = 'Lagu berikutnya';
  static const mediaGroupLabel = 'Media';
}
