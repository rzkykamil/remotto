/// Power confirmation copy (P01-P15, M4). Source: `design/export/artboards/`
/// `Power-light.dc.html`, `Power-resume.dc.html`, and `Remote.dc.html` (C09).
///
/// Actions are split into separate constants and functions (no enum), so this
/// file does not depend on the domain `PowerAction` type.
abstract final class PowerStrings {
  // C09 PowerRow visual labels (Remote.dc.html).
  static const rowSleep = 'Sleep';
  static const rowRestart = 'Restart';
  static const rowShutdown = 'Matikan';

  // C09 Semantics labels.
  static const semSleep = 'Sleep laptop';
  static const semRestart = 'Restart laptop';
  static const semShutdown = 'Matikan laptop';

  /// Bottom cancel action of the confirmation sheets (P01-P06).
  static const cancelAction = 'Nggak jadi';

  // P01 sleep confirmation.
  static const sleepKicker = 'SLEEP';
  static const sleepTitle = 'Sleep-in laptop?';
  static const sleepAction = 'Sleep-in';

  /// P01 body. [laptopName] comes from `/status` of the agent.
  static String sleepBody(String laptopName) =>
      '$laptopName bakal tidur 5 detik lagi. Masih bisa dibatalin.';

  // P02 stage 1 (tap). Shared kicker and body, separate titles.
  static const stage1Kicker = '1 / 2';
  static const stage1Action = 'Lanjut';
  static const shutdownStage1Title = 'Yakin matiin laptop?';
  static const restartStage1Title = 'Yakin restart laptop?';

  /// P02 body, same for shutdown and restart.
  static String stage1Body(String laptopName) =>
      'Kerjaan yang belum disimpan di $laptopName bisa hilang.';

  // P03 / P06 stage 2 (hold). Shared kicker.
  static const stage2Kicker = '2 / 2';
  static const shutdownHoldTitle = 'Tahan buat matiin';
  static const shutdownHoldBody = 'Habis itu masih ada 5 detik buat batal.';
  static const shutdownHoldLabel = 'Tahan buat matiin';
  static const restartHoldTitle = 'Tahan buat restart';
  static const restartHoldBody =
      'Laptop nyala lagi sendiri. Masih ada 5 detik buat batal.';
  static const restartHoldLabel = 'Tahan buat restart';

  // Hold hint under the hold button.
  static const holdIdleHint = 'Tahan sampai penuh, sekitar 1 detik';
  static const holdingHint = 'Terus tahan…';
  static const holdReleasedHint = 'Kelepasan. Tahan sampai penuh ya.';

  // P07 / P11 countdown (SCR-013).
  static const countdownTitleShutdown = 'Laptop mati dalam';
  static const countdownTitleRestart = 'Laptop restart dalam';
  static const countdownTitleSleep = 'Laptop tidur dalam';
  static const countdownHint = 'Mau berhenti? Tekan Batal kapan aja.';
  static const countdownCancel = 'Batal';

  /// P11 hint when the cancel command did not reach the laptop.
  static const countdownFailedHint = 'Kalau tetap gagal, laptop bakal mati.';
  static const countdownCancelAgain = 'Batal lagi';

  /// Cancel button label and Semantics hint while the cancel is in flight.
  static const countdownCancelling = 'Lagi dibatalin…';
  static const countdownCancellingHint = 'Tunggu sebentar';

  /// Spoken countdown, e.g. "Laptop mati dalam 3 detik" (title + seconds).
  static String countdownAnnounce(String title, int seconds) =>
      '$title $seconds detik';

  // Hold control Semantics (C12).
  static const holdSemanticsHint = 'tahan';
  static const holdNowShutdown = 'Matikan sekarang';
  static const holdNowRestart = 'Restart sekarang';

  /// P11 warning banner.
  static const countdownCancelWarning =
      'Batal nggak sampai ke laptop. Tekan lagi sekarang.';

  /// P13 small label. Explains why the countdown opened. [seconds] is the time
  /// since the command was scheduled. Set [fromThisPhone] when this app
  /// scheduled it.
  static String since(int seconds, {bool fromThisPhone = false}) =>
      'Dijadwalkan $seconds detik lalu${fromThisPhone ? ' dari HP ini' : ''}';

  // P08 toast after cancel.
  static const toastCancelledShutdown = 'Nggak jadi dimatiin';
  static const toastCancelledRestart = 'Nggak jadi restart';
  static const toastCancelledSleep = 'Nggak jadi tidur';

  // P09 command delivered.
  static const doneShutdownTitle = 'Laptop lagi dimatiin';
  static const doneSleepTitle = 'Laptop lagi tidur';
  static const doneRestartTitle = 'Laptop lagi restart';
  static const doneAction = 'Oke';

  /// P09 body for shutdown and sleep. [laptopName] is the laptop name.
  static String doneShutdownBody(String laptopName) =>
      '$laptopName udah dapet perintahnya. Sampai besok!';

  static String doneSleepBody(String laptopName) =>
      '$laptopName udah dapet perintahnya. Selamat istirahat!';

  static const doneRestartBody = 'Lagi restart, nanti nyambung sendiri.';

  // P10 schedule failed.
  static const scheduleFailedTitle = 'Perintah nggak sampai';
  static const scheduleFailedBody =
      'Laptop masih nyala. Cek WiFi, lalu coba lagi.';
  static const scheduleFailedRetry = 'Coba lagi';
  static const scheduleFailedClose = 'Tutup';

  // P14 cancel came too late.
  static const lateTitle = 'Udah telat buat batal';

  /// P14 body. [seconds] is the time since the command was sent.
  static String lateShutdownBody(
    String laptopName,
    int seconds, {
    bool fromThisPhone = false,
  }) => _lateBody('lagi dimatiin', laptopName, seconds, fromThisPhone);

  static String lateRestartBody(
    String laptopName,
    int seconds, {
    bool fromThisPhone = false,
  }) => _lateBody('lagi restart', laptopName, seconds, fromThisPhone);

  static String lateSleepBody(
    String laptopName,
    int seconds, {
    bool fromThisPhone = false,
  }) => _lateBody('lagi tidur', laptopName, seconds, fromThisPhone);

  static String _lateBody(
    String phrase,
    String laptopName,
    int seconds,
    bool fromThisPhone,
  ) =>
      '$laptopName $phrase. Perintahnya dikirim $seconds detik lalu'
      '${fromThisPhone ? ' dari HP ini' : ''}.';

  /// P14 action.
  static const lateAction = 'Oke';

  // P15 powered off (title reuses `RemoteStrings.poweredOffTitle`).
  static String poweredOffShutdownBody(DateTime at) =>
      'Dimatiin dari HP ini jam ${formatClock(at)}. '
      'Nyalain laptopnya, nanti nyambung sendiri.';

  static String poweredOffSleepBody(DateTime at) =>
      'Di-sleep-in dari HP ini jam ${formatClock(at)}. '
      'Buka lagi laptopnya, nanti nyambung sendiri.';

  /// Clock as `HH.mm`, e.g. `23.41`. Dot separator per artboard.
  static String formatClock(DateTime at) {
    final hour = at.hour.toString().padLeft(2, '0');
    final minute = at.minute.toString().padLeft(2, '0');
    return '$hour.$minute';
  }
}
