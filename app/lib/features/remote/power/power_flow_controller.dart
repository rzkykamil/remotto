import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:remotto/core/connection/connection_controller.dart';
import 'package:remotto/core/connection/connection_providers.dart';
import 'package:remotto/core/connection/connection_state.dart';
import 'package:remotto/core/haptics/r_haptics.dart';
import 'package:remotto/core/network/agent_status.dart';
import 'package:remotto/core/network/api_failure.dart';
import 'package:remotto/core/network/network_providers.dart';
import 'package:remotto/core/theme/tokens.g.dart';
import 'package:remotto/features/remote/data/power_repository.dart';
import 'package:remotto/features/remote/power/power_flow_state.dart';
import 'package:remotto/features/remote/power/power_providers.dart';

/// Power flow: schedule, countdown, cancel (technical-spec §5 and §6,
/// BR-4, BR-5, BR-17, BR-19, BR-20).
///
/// Safety rules:
/// - A schedule request is never retried automatically.
/// - P10 ("not scheduled") is shown only when the agent proves it. When the
///   result is unknown, the countdown is shown as P11 instead.
/// - The countdown runs from the agent's `remainingMs`, never from the
///   difference between the phone and laptop clocks.
/// - Only the user repeats a cancel.
final class PowerFlowController extends Notifier<PowerFlowState> {
  static const Duration _tickInterval = Duration(seconds: 1);

  /// Below this much time left, the schedule can no longer be cancelled (BR-19).
  static const int _minCancellableMs = 1000;

  late PowerRepository _repository;
  late PollScheduler _scheduler;
  late RHaptics _haptics;
  late DateTime Function() _now;

  /// Ticks the countdown once per second. Null when no countdown is running.
  ScheduledJob? _ticker;

  /// Identifies the schedule on screen (action and scheduledAt). Null if unknown.
  String? _key;

  /// Schedule the user closed (P09 or P14). [resumeFromStatus] ignores it, so
  /// a status that still shows it (executing, or the next poll) does not reopen
  /// the same screen.
  String? _dismissedKey;

  @override
  PowerFlowState build() {
    _repository = ref.read(powerRepositoryProvider);
    _scheduler = ref.read(pollSchedulerProvider);
    _haptics = ref.read(hapticsProvider);
    _now = ref.read(connectionClockProvider);
    ref.onDispose(_stopTicker);
    return const PowerFlowIdle();
  }

  // Commands ----------------------------------------------------------------

  /// Sends a power command. Only from idle. Never retried automatically.
  Future<void> begin(PowerAction action) async {
    if (state is! PowerFlowIdle) return;
    _key = null;
    state = PowerFlowScheduling(action);

    Pending? pending;
    ApiFailure? failure;
    try {
      pending = await _repository
          .schedule(action)
          .timeout(RMotion.commandTimeout);
    } catch (error) {
      failure = _toFailure(error);
    }
    if (!ref.mounted) return;

    try {
      if (failure == null) {
        _onScheduled(action, pending!);
      } else {
        await _onScheduleFailed(action, failure);
      }
    } on UnauthorizedFailure {
      _reportUnauthorized();
    }
  }

  /// Cancels the schedule. Ignored while a cancel is pending, and when no
  /// countdown is shown. Only the user repeats it ("Batal lagi").
  Future<void> cancel() async {
    final current = state;
    if (current is! PowerFlowCounting) return;
    state = PowerFlowCancelling(counting: current);

    PowerAction? cancelled;
    ApiFailure? failure;
    try {
      cancelled = await _repository.cancel().timeout(RMotion.commandTimeout);
    } catch (error) {
      failure = _toFailure(error);
    }
    if (!ref.mounted) return;

    // Ticks during the cancel keep the countdown current.
    final latest = _countingOf(state) ?? current;
    if (failure == null) {
      _clearCommand();
      _markDismissed();
      _setResult(PowerCancelled(cancelled ?? latest.action));
      return;
    }

    switch (failure) {
      case UnauthorizedFailure():
        _reportUnauthorized();
      case ServerFailure(code: 'no_pending_power'):
        _clearCommand();
        _markDismissed();
        _setResult(PowerCancelled(latest.action));
      case ServerFailure(code: 'power_executing'):
        _setResult(
          PowerTooLate(
            action: latest.action,
            elapsed: latest.total - latest.remaining,
            fromThisPhone: latest.fromThisPhone,
          ),
        );
      case ForbiddenFailure():
      case RateLimitedFailure():
      case ServerFailure():
      case UnreachableFailure():
      case TimeoutFailure():
        // The cancel is not confirmed, so the schedule may still run. Keep
        // counting and let the user try again.
        _haptics.failure();
        _enterCounting(latest.copyWith(cancelFailed: true));
    }
  }

  /// A cancelled schedule must not come back from a status poll that was
  /// already in flight, or from the stale status held by the connection.
  void _markDismissed() {
    final key = _key;
    if (key != null) _dismissedKey = key;
  }

  /// Closes the result screen. Only from [PowerFlowResult]: a countdown is
  /// never dropped here, because the laptop still has the schedule.
  void dismiss() {
    final current = state;
    if (current is! PowerFlowResult) return;
    final result = current.result;
    final key = _key;
    if (key != null && (result is PowerSent || result is PowerTooLate)) {
      _dismissedKey = key;
    }
    _key = null;
    state = const PowerFlowIdle();
  }

  /// Called with a `pending` read by the status poll (T11, on app open or
  /// resume). Ignored while the flow is not idle, and for a key the user has
  /// already closed.
  void resumeFromStatus(Pending pending) {
    if (state is! PowerFlowIdle) return;
    final action = PowerAction.fromWire(pending.action);
    if (action == null) return;
    if (_keyOf(action, pending.scheduledAt) == _dismissedKey) return;
    _showPending(action, pending);
  }

  // Results of a schedule request ---------------------------------------------

  void _onScheduled(PowerAction action, Pending pending) {
    _recordCommand(action);
    _key = _keyOf(action, pending.scheduledAt);
    _enterCounting(
      _countingFrom(action, pending, fromThisPhone: _fromThisPhone(action)),
    );
  }

  Future<void> _onScheduleFailed(PowerAction action, ApiFailure failure) async {
    switch (failure) {
      case UnauthorizedFailure():
        _reportUnauthorized();
      case ServerFailure(code: 'power_pending'):
        await _resolveConflict(action);
      case ServerFailure(code: 'power_failed'):
      case ForbiddenFailure():
      case RateLimitedFailure():
      case UnreachableFailure():
        // The agent rejected the request, or it never arrived (BR-5, 500
        // power_failed, 403, 429). Safe to show P10.
        _notScheduled(action);
      case TimeoutFailure():
      case ServerFailure():
        // The request may have reached the agent, or the reply did not match
        // the contract. The schedule may exist, so read /status.
        await _resolveAmbiguous(action);
    }
  }

  /// 409 `power_pending`: a schedule exists (BR-5). Read it from `/status`.
  Future<void> _resolveConflict(PowerAction action) async {
    final status = await _readStatus();
    if (!ref.mounted) return;
    if (status == null) {
      // The 409 proves a schedule exists, so P10 would be false (technical-spec
      // §6). Show P11 instead.
      _enterFailedCountdown(_fullCountdown(action, cancelFailed: true));
      return;
    }
    final pending = status.pending;
    if (pending == null) {
      _notScheduled(action);
      return;
    }
    _showStatusPending(action, pending);
  }

  /// Timeout after the request was sent: the agent may have scheduled it.
  Future<void> _resolveAmbiguous(PowerAction action) async {
    final status = await _readStatus();
    if (!ref.mounted) return;
    if (status == null) {
      // Both the command and the status read are unknown: P11, full countdown.
      _recordCommand(action);
      _enterFailedCountdown(_fullCountdown(action, cancelFailed: true));
      return;
    }
    final pending = status.pending;
    if (pending == null) {
      _notScheduled(action);
      return;
    }
    if (pending.action == action.wire) _recordCommand(action);
    _showStatusPending(action, pending);
  }

  /// Shows the schedule from a status read after a request whose result was
  /// unknown. An action the app does not know is treated as an unreadable
  /// status (P11).
  void _showStatusPending(PowerAction expected, Pending pending) {
    final action = PowerAction.fromWire(pending.action);
    if (action == null) {
      _enterFailedCountdown(_fullCountdown(expected, cancelFailed: true));
      return;
    }
    _showPending(action, pending);
  }

  /// P13 (counting) or P14 (too late) from one `pending` object.
  void _showPending(PowerAction action, Pending pending) {
    _key = _keyOf(action, pending.scheduledAt);
    final fromThisPhone = _fromThisPhone(action);
    if (pending.remainingMs < _minCancellableMs) {
      // Under 1 s left (or executing): cannot be cancelled (BR-19, FR-4.10).
      _setResult(
        PowerTooLate(
          action: action,
          elapsed: _elapsedSeconds(pending),
          fromThisPhone: fromThisPhone,
        ),
      );
      return;
    }
    _haptics.limit();
    _enterCounting(
      _countingFrom(action, pending, fromThisPhone: fromThisPhone),
    );
  }

  // Countdown ---------------------------------------------------------------

  /// Starts (or continues) the countdown. A countdown that is already at 0 is
  /// sent right away, unless a cancel is pending (checked by the caller).
  void _enterCounting(PowerFlowCounting counting) {
    if (counting.remaining <= 0) {
      _setResult(PowerSent(counting.action));
      return;
    }
    state = counting;
    _ticker ??= _scheduler.every(_tickInterval, _tick);
  }

  void _enterFailedCountdown(PowerFlowCounting counting) {
    _haptics.failure();
    _enterCounting(counting);
  }

  void _tick() {
    final current = state;
    switch (current) {
      case PowerFlowCounting():
        final next = current.remaining - 1;
        if (next <= 0) {
          _setResult(PowerSent(current.action));
          return;
        }
        state = current.copyWith(remaining: next);
      case PowerFlowCancelling(:final counting):
        // A cancel is pending: keep counting, but at 0 wait for its reply.
        final next = counting.remaining > 0 ? counting.remaining - 1 : 0;
        state = PowerFlowCancelling(
          counting: counting.copyWith(remaining: next),
        );
      case PowerFlowIdle() || PowerFlowScheduling() || PowerFlowResult():
        _stopTicker();
    }
  }

  void _setResult(PowerResult result) {
    _stopTicker();
    state = PowerFlowResult(result);
    final restarting = switch (result) {
      PowerSent(:final action) ||
      PowerTooLate(:final action) => action == PowerAction.restart,
      PowerNotScheduled() || PowerCancelled() => false,
    };
    // A restart takes the laptop down, so poll faster until it returns (FR-4.12).
    if (restarting) {
      ref
          .read(connectionControllerProvider.notifier)
          .setFastPoll(enabled: true);
    }
  }

  void _notScheduled(PowerAction action) {
    _haptics.failure();
    _setResult(PowerNotScheduled(action));
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  // Helpers -----------------------------------------------------------------

  /// Reads `/status` once. Null when the read failed (P11 applies). A 401 is
  /// passed on.
  Future<AgentStatus?> _readStatus() async {
    try {
      return await ref
          .read(statusRepositoryProvider)
          .fetchStatus()
          .timeout(RMotion.commandTimeout);
    } on UnauthorizedFailure {
      rethrow;
    } catch (_) {
      return null;
    }
  }

  void _recordCommand(PowerAction action) {
    ref
        .read(lastPowerCommandProvider.notifier)
        .record(LastPowerCommand(action: action.wire, sentAt: _now()));
  }

  void _clearCommand() {
    ref.read(lastPowerCommandProvider.notifier).clear();
  }

  bool _fromThisPhone(PowerAction action) {
    final last = ref.read(lastPowerCommandProvider);
    return last != null && last.action == action.wire;
  }

  void _reportUnauthorized() {
    _haptics.failure();
    _stopTicker();
    _key = null;
    state = const PowerFlowIdle();
    ref.read(connectionControllerProvider.notifier).reportUnauthorized();
  }

  /// Countdown from a `pending` object. The remaining time comes from the
  /// agent, rounded up to whole seconds (FR-4.9, BR-20).
  PowerFlowCounting _countingFrom(
    PowerAction action,
    Pending pending, {
    required bool fromThisPhone,
  }) {
    final passedMs = pending.delayMs - pending.remainingMs;
    return PowerFlowCounting(
      action: action,
      remaining: _ceilSeconds(pending.remainingMs),
      total: _ceilSeconds(pending.delayMs),
      since: passedMs <= 0 ? 0 : passedMs ~/ 1000,
      fromThisPhone: fromThisPhone,
    );
  }

  /// P11 countdown: starts from the full delay, because the real remaining
  /// time is unknown (technical-spec §6).
  PowerFlowCounting _fullCountdown(
    PowerAction action, {
    required bool cancelFailed,
  }) {
    return PowerFlowCounting(
      action: action,
      remaining: RComponent.countdownSeconds,
      total: RComponent.countdownSeconds,
      fromThisPhone: _fromThisPhone(action),
      cancelFailed: cancelFailed,
    );
  }

  PowerFlowCounting? _countingOf(PowerFlowState current) {
    return switch (current) {
      PowerFlowCounting() => current,
      PowerFlowCancelling(:final counting) => counting,
      _ => null,
    };
  }

  /// Whole seconds of the delay that already passed.
  int _elapsedSeconds(Pending pending) {
    final elapsed =
        _ceilSeconds(pending.delayMs) - _ceilSeconds(pending.remainingMs);
    return elapsed < 0 ? 0 : elapsed;
  }

  /// Unknown errors (and timeouts) count as ambiguous: the request may have
  /// reached the agent, so the caller reads `/status` before deciding.
  ApiFailure _toFailure(Object error) {
    if (error is ApiFailure) return error;
    return const TimeoutFailure();
  }

  static int _ceilSeconds(int ms) => (ms + 999) ~/ 1000;

  static String _keyOf(PowerAction action, String scheduledAt) =>
      '${action.wire}@$scheduledAt';
}
