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
}
