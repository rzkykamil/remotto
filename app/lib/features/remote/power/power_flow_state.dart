import 'package:remotto/features/remote/data/power_repository.dart';

/// State of the power flow (SCR-013: P07, P08, P09, P10, P11, P13, P14).
///
/// Only [PowerFlowController] creates these. Seconds are whole numbers,
/// rounded up, so the screen shows the same value as the agent (BR-20).
sealed class PowerFlowState {
  const PowerFlowState();
}

/// No flow. Nothing is shown.
final class PowerFlowIdle extends PowerFlowState {
  const PowerFlowIdle();
}

/// The schedule request is in flight.
final class PowerFlowScheduling extends PowerFlowState {
  const PowerFlowScheduling(this.action);

  final PowerAction action;
}

/// Countdown running (P07 normal, P13 resumed, P11 after a failed check).
final class PowerFlowCounting extends PowerFlowState {
  const PowerFlowCounting({
    required this.action,
    required this.remaining,
    required this.total,
    required this.fromThisPhone,
    this.since,
    this.cancelFailed = false,
  });

  final PowerAction action;

  /// Whole seconds left, rounded up. Reaching 0 means the command is sent.
  final int remaining;

  /// Whole seconds of the full delay. The ring uses it with [remaining].
  final int total;

  /// Whole seconds that had already passed when this countdown started
  /// (P13). Null when the countdown started fresh or the value is unknown.
  final int? since;

  /// True only when `lastPowerCommand` exists on this phone and has the same
  /// action (FR-4.13).
  final bool fromThisPhone;

  /// True after a failed cancel or an unknown result (P11). "Batal lagi" is
  /// shown and calls [PowerFlowController.cancel] again.
  final bool cancelFailed;

  PowerFlowCounting copyWith({int? remaining, bool? cancelFailed}) {
    return PowerFlowCounting(
      action: action,
      remaining: remaining ?? this.remaining,
      total: total,
      since: since,
      fromThisPhone: fromThisPhone,
      cancelFailed: cancelFailed ?? this.cancelFailed,
    );
  }
}

/// Cancel request in flight. The countdown in [counting] keeps running, but
/// it never sends the command while the cancel is pending.
final class PowerFlowCancelling extends PowerFlowState {
  const PowerFlowCancelling({required this.counting});

  final PowerFlowCounting counting;
}

/// Final outcome. Closed by [PowerFlowController.dismiss].
final class PowerFlowResult extends PowerFlowState {
  const PowerFlowResult(this.result);

  final PowerResult result;
}

/// Outcome shown in [PowerFlowResult].
sealed class PowerResult {
  const PowerResult();
}

/// The command ran out its delay (P09). For restart the fast poll is on.
final class PowerSent extends PowerResult {
  const PowerSent(this.action);

  final PowerAction action;
}

/// The command never reached the laptop (P10).
final class PowerNotScheduled extends PowerResult {
  const PowerNotScheduled(this.action);

  final PowerAction action;
}

/// The command is executing or about to run, so it cannot be cancelled (P14).
final class PowerTooLate extends PowerResult {
  const PowerTooLate({
    required this.action,
    required this.elapsed,
    required this.fromThisPhone,
  });

  final PowerAction action;

  /// Whole seconds of the delay that had passed (total minus remaining).
  final int elapsed;

  /// Same meaning as [PowerFlowCounting.fromThisPhone].
  final bool fromThisPhone;
}

/// The schedule was cancelled (P08).
final class PowerCancelled extends PowerResult {
  const PowerCancelled(this.action);

  final PowerAction action;
}
