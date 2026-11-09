import 'dart:convert';

import 'package:remotto/core/network/agent_status.dart';
import 'package:remotto/core/network/api_failure.dart';
import 'package:remotto/features/remote/data/power_repository.dart';

/// One scripted step of [FakePowerRepository].
sealed class FakePowerStep {
  const FakePowerStep();
}

/// Success. Applies the requested change to the fake state, like the agent does.
final class FakePowerOk extends FakePowerStep {
  const FakePowerOk();
}

/// Fixed HTTP reply. The body goes through the same parsing as the HTTP path.
final class FakePowerReply extends FakePowerStep {
  const FakePowerReply(this.statusCode, this.body, {this.headers = const {}});

  final int statusCode;
  final String body;
  final Map<String, String> headers;
}

/// No response within the time limit. The state does not change.
final class FakePowerTimeout extends FakePowerStep {
  const FakePowerTimeout();
}

const _fakeScheduledAt = '2026-01-01T23:41:00+07:00';

/// 202 reply `{ "data": { "pending": ... } }`.
FakePowerReply fakePowerScheduled(
  PowerAction action, {
  int remainingMs = 5000,
  int delayMs = 5000,
}) {
  return FakePowerReply(
    202,
    jsonEncode({
      'data': {
        'pending': {
          'action': action.wire,
          'remainingMs': remainingMs,
          'delayMs': delayMs,
          'scheduledAt': _fakeScheduledAt,
        },
      },
    }),
  );
}

/// 200 reply `{ "data": { "cancelled": ..., "pending": null } }`.
FakePowerReply fakePowerCancelled(PowerAction action) {
  return FakePowerReply(
    200,
    jsonEncode({
      'data': {'cancelled': action.wire, 'pending': null},
    }),
  );
}

/// Error envelope `{ "error": { "code", "message" } }`.
FakePowerReply fakePowerError(int statusCode, String code) {
  return FakePowerReply(
    statusCode,
    jsonEncode({
      'error': {'code': code, 'message': 'fake error'},
    }),
  );
}

/// Programmable fake of the power endpoints with a stateful schedule.
///
/// Steps are used in order per call; after they run out, the last step repeats.
/// Only a successful step changes the state. Default: every call succeeds.
final class FakePowerRepository implements PowerRepository {
  FakePowerRepository({
    List<FakePowerStep> script = const [FakePowerOk()],
    this.delay = Duration.zero,
  }) : assert(script.isNotEmpty, 'script must contain at least one step'),
       _script = List.unmodifiable(script);

  final List<FakePowerStep> _script;

  /// Delay before the reply. Zero in tests.
  final Duration delay;

  int _steps = 0;

  int scheduleCalls = 0;
  int cancelCalls = 0;

  /// Argument of the most recent [schedule] call, or null if none yet.
  PowerAction? lastScheduled;

  /// Schedule the fake currently holds (what the agent would report), or null.
  Pending? get pending => _pending;
  Pending? _pending;

  @override
  Future<Pending> schedule(PowerAction action) async {
    scheduleCalls++;
    lastScheduled = action;
    return _run(
      () {
        // Same rule as the agent: one active schedule at a time (BR-5).
        if (_pending != null) throw const ServerFailure(code: 'power_pending');
        return Pending(
          action: action.wire,
          remainingMs: 5000,
          delayMs: 5000,
          scheduledAt: _fakeScheduledAt,
        );
      },
      parseScheduledPending,
      (result) => result,
    );
  }

  @override
  Future<PowerAction> cancel() async {
    cancelCalls++;
    return _run(
      () {
        final current = _pending;
        if (current == null) {
          throw const ServerFailure(code: 'no_pending_power');
        }
        return PowerAction.fromWire(current.action)!;
      },
      parseCancelledAction,
      (_) => null,
    );
  }

  /// Takes the next step. [onOk] is the agent-side effect of a successful call
  /// and may throw an [ApiFailure] for a rule violation. [parse] reads the
  /// `data` of a scripted reply. [stateAfter] gives the schedule after a
  /// success, for both the Ok and the reply path.
  Future<T> _run<T>(
    T Function() onOk,
    T Function(Map<String, Object?> data) parse,
    Pending? Function(T result) stateAfter,
  ) async {
    final index = _steps < _script.length ? _steps : _script.length - 1;
    _steps++;
    if (delay > Duration.zero) await Future<void>.delayed(delay);

    final step = _script[index];
    switch (step) {
      case FakePowerOk():
        final result = onOk();
        _pending = stateAfter(result);
        return result;
      case FakePowerReply():
        final data = unwrapAgentResponse(
          step.statusCode,
          step.body,
          headers: step.headers,
        );
        final result = parse(data);
        _pending = stateAfter(result);
        return result;
      case FakePowerTimeout():
        throw const TimeoutFailure();
    }
  }
}
