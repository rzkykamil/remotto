/// Behavioural constants that are not design tokens.
///
/// Values come from `docs/design-system.md` section 6 and
/// `docs/technical-spec.md` section 5.
abstract final class RBehavior {
  /// Blink duration for the prev/next key feedback.
  static const Duration prevNextBlink = Duration(milliseconds: 240);

  /// How long the "reconnected" pill stays visible.
  static const Duration reconnectedPill = Duration(seconds: 2);

  /// Polling interval while the remote is in a fast-poll state.
  static const Duration fastPoll = Duration(seconds: 2);

  /// Time after which the last power command is no longer remembered.
  static const Duration lastPowerCommandTtl = Duration(minutes: 10);

  /// Maximum wait for the connection to resume after the app returns.
  static const Duration resumeWait = Duration(seconds: 2);

  /// How long the invalid-QR banner stays visible.
  static const Duration qrErrorBanner = Duration(seconds: 3);

  /// Window in which a repeated QR code is ignored.
  static const Duration qrDuplicateIgnore = Duration(seconds: 2);

  /// Maximum wait for each pairing test step.
  static const Duration stepTimeout = Duration(seconds: 5);

  /// How long one mDNS discovery session collects agent announcements.
  static const Duration discoveryTimeout = Duration(seconds: 3);

  /// Slack on top of [discoveryTimeout] before a search that has not answered
  /// is abandoned.
  static const Duration discoveryGuardMargin = Duration(seconds: 1);

  /// A search taking longer than this counts as no result.
  static final Duration discoveryHardLimit =
      discoveryTimeout + discoveryGuardMargin;

  /// Minimum gap between two background rediscovery runs while offline.
  static const Duration discoveryInterval = Duration(seconds: 15);

  /// Debounce for network change events before forcing a rediscovery.
  static const Duration networkChangeDebounce = Duration(seconds: 1);
}
