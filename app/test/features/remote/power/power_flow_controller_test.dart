import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotto/core/connection/connection_providers.dart';
import 'package:remotto/core/connection/connection_state.dart';
import 'package:remotto/core/haptics/r_haptics.dart';
import 'package:remotto/core/network/agent_status.dart';
import 'package:remotto/core/network/api_failure.dart';
import 'package:remotto/core/network/network_providers.dart';
import 'package:remotto/core/storage/storage_providers.dart';
import 'package:remotto/core/theme/r_behavior.dart';
import 'package:remotto/core/theme/tokens.g.dart';
import 'package:remotto/features/remote/data/power_repository.dart';
import 'package:remotto/features/remote/power/power_flow_state.dart';
import 'package:remotto/features/remote/power/power_flow_controller.dart';
import 'package:remotto/features/remote/power/power_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/fake_poll_scheduler.dart';
import '../../../support/fake_power_repository.dart';
import '../../../support/fake_status_repository.dart';
import '../../../support/fakes.dart';

/// Same value as the fake repository's `scheduledAt`.
const _scheduledAt = '2026-01-01T23:41:00+07:00';
const _oneSecond = Duration(seconds: 1);

Pending _pending(
  PowerAction action, {
  required int remainingMs,
  int delayMs = 5000,
}) {
  return Pending(
    action: action.wire,
    remainingMs: remainingMs,
    delayMs: delayMs,
    scheduledAt: _scheduledAt,
  );
}

Map<String, Object?> _pendingJson(
  PowerAction action, {
  required int remainingMs,
  int delayMs = 5000,
}) {
  return {
    'action': action.wire,
    'remainingMs': remainingMs,
    'delayMs': delayMs,
    'scheduledAt': _scheduledAt,
  };
}

PowerFlowCounting _asCounting(PowerFlowState state) {
  expect(state, isA<PowerFlowCounting>());
  return state as PowerFlowCounting;
}

PowerResult _asResult(PowerFlowState state) {
  expect(state, isA<PowerFlowResult>());
  return (state as PowerFlowResult).result;
}

/// Mutable phone clock for `sentAt`.
final class _Clock {
  DateTime now = DateTime.utc(2026, 1, 1, 12);
}

/// Power repository whose cancel waits for the test to answer.
final class _GatedPower implements PowerRepository {
  Completer<PowerAction>? gate;

  @override
  Future<Pending> schedule(PowerAction action) async =>
      _pending(action, remainingMs: 5000);

  @override
  Future<PowerAction> cancel() {
    return (gate = Completer<PowerAction>()).future;
  }
}

/// Power repository for an agent that cannot be reached.
final class _UnreachablePower implements PowerRepository {
  int scheduleCalls = 0;

  @override
  Future<Pending> schedule(PowerAction action) async {
    scheduleCalls++;
    throw const UnreachableFailure();
  }

  @override
  Future<PowerAction> cancel() async => throw const UnreachableFailure();
}

final class _Harness {
  _Harness(this.container, this.scheduler, this.sink, this.clock);

  final ProviderContainer container;
  final FakePollScheduler scheduler;
  final RecordingHapticSink sink;
  final _Clock clock;
  bool _disposed = false;

  PowerFlowState get state => container.read(powerFlowControllerProvider);

  PowerFlowController get flow =>
      container.read(powerFlowControllerProvider.notifier);

  ConnectionPhase get phase =>
      container.read(connectionControllerProvider).phase;

  LastPowerCommand? get lastCommand => container.read(lastPowerCommandProvider);

  /// Delays of the live periodic jobs. Tells the 1 s countdown ticker apart
  /// from the connection poll.
  List<Duration> get periodicDelays => [
    for (final job in scheduler.jobs)
      if (job.live && job.periodic) job.delay,
  ];

  /// Runs the countdown ticker [times] times, as the 1 s timer would.
  void tick([int times = 1]) {
    for (var i = 0; i < times; i++) {
      final ticker = scheduler.jobs.lastWhere(
        (job) => job.live && job.periodic && job.delay == _oneSecond,
      );
      ticker.run();
    }
  }

  void startConnection() {
    container.read(connectionControllerProvider.notifier).start();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    container.dispose();
  }
}

Future<_Harness> _harness({
  required PowerRepository power,
  FakeStatusRepository? status,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final scheduler = FakePollScheduler();
  final sink = RecordingHapticSink();
  final clock = _Clock();
  final container = ProviderContainer(
    overrides: [
      powerRepositoryProvider.overrideWithValue(power),
      statusRepositoryProvider.overrideWithValue(
        status ?? FakeStatusRepository([fakeStatusOk()]),
      ),
      pollSchedulerProvider.overrideWithValue(scheduler),
      hapticSinkProvider.overrideWithValue(sink),
      sharedPreferencesProvider.overrideWithValue(prefs),
      connectionClockProvider.overrideWithValue(() => clock.now),
    ],
  );
  final harness = _Harness(container, scheduler, sink, clock);
  addTearDown(harness.dispose);
  return harness;
}

void main() {
  group('begin (BR-4, BR-5, FR-4.5, FR-4.6)', () {
    test(
      '202 counts down from 5 and is sent at 0, recording lastPowerCommand',
      () async {
        final power = FakePowerRepository();
        final h = await _harness(power: power);

        await h.flow.begin(PowerAction.shutdown);

        final counting = _asCounting(h.state);
        expect(counting.action, PowerAction.shutdown);
        expect(counting.remaining, 5);
        expect(counting.total, 5);
        expect(counting.since, 0);
        expect(counting.fromThisPhone, isTrue);
        expect(counting.cancelFailed, isFalse);
        expect(
          h.lastCommand,
          LastPowerCommand(action: 'shutdown', sentAt: h.clock.now),
        );

        h.tick(4);
        expect(_asCounting(h.state).remaining, 1);
        h.tick();

        final result = _asResult(h.state);
        expect(result, isA<PowerSent>());
        expect((result as PowerSent).action, PowerAction.shutdown);
        expect(power.scheduleCalls, 1);
        expect(h.lastCommand, isNotNull, reason: 'sent keeps lastPowerCommand');
      },
    );

    test(
      '409 power_pending reads /status and counts the remaining time (P13)',
      () async {
        final power = FakePowerRepository(
          script: [fakePowerError(409, 'power_pending')],
        );
        final status = FakeStatusRepository([
          fakeStatusOk(
            pending: _pendingJson(PowerAction.sleep, remainingMs: 3000),
          ),
        ]);
        final h = await _harness(power: power, status: status);

        await h.flow.begin(PowerAction.sleep);

        final counting = _asCounting(h.state);
        expect(counting.action, PowerAction.sleep);
        expect(counting.remaining, 3);
        expect(counting.since, 2);
        expect(counting.total, 5);
        expect(counting.fromThisPhone, isFalse);
        expect(h.lastCommand, isNull, reason: 'a 409 is not a sent command');
        expect(status.calls, 1);
        expect(h.sink.calls, contains('medium'));
        expect(power.scheduleCalls, 1, reason: 'no automatic retry');
      },
    );

    test(
      '409 power_pending is fromThisPhone when this phone sent the same action',
      () async {
        final power = FakePowerRepository(
          script: [fakePowerError(409, 'power_pending')],
        );
        final status = FakeStatusRepository([
          fakeStatusOk(
            pending: _pendingJson(PowerAction.sleep, remainingMs: 3000),
          ),
        ]);
        final h = await _harness(power: power, status: status);
        h.container
            .read(lastPowerCommandProvider.notifier)
            .record(LastPowerCommand(action: 'sleep', sentAt: h.clock.now));

        await h.flow.begin(PowerAction.sleep);

        expect(_asCounting(h.state).fromThisPhone, isTrue);
      },
    );

    test(
      '409 power_pending with /status unreadable shows P11, not P10',
      () async {
        final power = FakePowerRepository(
          script: [fakePowerError(409, 'power_pending')],
        );
        final status = FakeStatusRepository([
          const FakeTransportFailure(TimeoutFailure()),
        ]);
        final h = await _harness(power: power, status: status);

        await h.flow.begin(PowerAction.shutdown);

        final counting = _asCounting(h.state);
        expect(counting.cancelFailed, isTrue);
        expect(counting.remaining, 5);
        expect(counting.total, 5);
        expect(counting.since, isNull);
      },
    );

    test(
      '409 power_pending with no pending left in /status is not scheduled',
      () async {
        final power = FakePowerRepository(
          script: [fakePowerError(409, 'power_pending')],
        );
        final h = await _harness(power: power);

        await h.flow.begin(PowerAction.shutdown);

        expect(_asResult(h.state), isA<PowerNotScheduled>());
        expect(h.lastCommand, isNull);
      },
    );

    test(
      '500 power_failed is not scheduled (P10) and is not retried',
      () async {
        final power = FakePowerRepository(
          script: [fakePowerError(500, 'power_failed')],
        );
        final h = await _harness(power: power);

        await h.flow.begin(PowerAction.sleep);

        final result = _asResult(h.state);
        expect(result, isA<PowerNotScheduled>());
        expect((result as PowerNotScheduled).action, PowerAction.sleep);
        expect(power.scheduleCalls, 1);
        expect(h.lastCommand, isNull);
        expect(h.sink.calls, contains('vibrate'));
      },
    );

    test(
      'unreachable agent is not scheduled (P10) and is not retried',
      () async {
        final power = _UnreachablePower();
        final h = await _harness(power: power);

        await h.flow.begin(PowerAction.sleep);

        expect(_asResult(h.state), isA<PowerNotScheduled>());
        expect(power.scheduleCalls, 1);
        expect(h.lastCommand, isNull);
      },
    );

    test('403 and 429 are not scheduled (P10)', () async {
      final replies = [
        fakePowerError(403, 'forbidden'),
        fakePowerError(429, 'rate_limited'),
      ];
      for (final reply in replies) {
        final power = FakePowerRepository(script: [reply]);
        final h = await _harness(power: power);

        await h.flow.begin(PowerAction.sleep);

        expect(_asResult(h.state), isA<PowerNotScheduled>());
        expect(power.scheduleCalls, 1);
        h.dispose();
      }
    });

    test(
      'timeout, then /status shows pending: counts from the remaining time',
      () async {
        final power = FakePowerRepository(script: [const FakePowerTimeout()]);
        final status = FakeStatusRepository([
          fakeStatusOk(
            pending: _pendingJson(PowerAction.sleep, remainingMs: 4000),
          ),
        ]);
        final h = await _harness(power: power, status: status);

        await h.flow.begin(PowerAction.sleep);

        final counting = _asCounting(h.state);
        expect(counting.action, PowerAction.sleep);
        expect(counting.remaining, 4);
        expect(counting.since, 1);
        expect(counting.fromThisPhone, isTrue);
        expect(
          h.lastCommand,
          LastPowerCommand(action: 'sleep', sentAt: h.clock.now),
        );
        expect(power.scheduleCalls, 1, reason: 'no automatic retry');
      },
    );

    test(
      'timeout, then /status without pending is not scheduled (P10)',
      () async {
        final power = FakePowerRepository(script: [const FakePowerTimeout()]);
        final h = await _harness(power: power);

        await h.flow.begin(PowerAction.sleep);

        expect(_asResult(h.state), isA<PowerNotScheduled>());
        expect(h.lastCommand, isNull);
        expect(power.scheduleCalls, 1);
      },
    );

    test('timeout, then /status fails: P11 from the full delay, lastPowerCommand recorded', () async {
      final power = FakePowerRepository(script: [const FakePowerTimeout()]);
      final status = FakeStatusRepository([
        const FakeTransportFailure(TimeoutFailure()),
      ]);
      final h = await _harness(power: power, status: status);

      await h.flow.begin(PowerAction.shutdown);

      final counting = _asCounting(h.state);
      expect(counting.cancelFailed, isTrue);
      expect(counting.remaining, 5);
      expect(counting.total, 5);
      expect(counting.fromThisPhone, isTrue);
      expect(
        h.lastCommand,
        LastPowerCommand(action: 'shutdown', sentAt: h.clock.now),
      );
    });

    test(
      '401 on schedule goes to token rejected and returns to idle',
      () async {
        final power = FakePowerRepository(
          script: [fakePowerError(401, 'invalid_token')],
        );
        final h = await _harness(power: power);

        await h.flow.begin(PowerAction.sleep);

        expect(h.state, isA<PowerFlowIdle>());
        expect(h.phase, ConnectionPhase.tokenRejected);
        expect(power.scheduleCalls, 1);
      },
    );

    test('401 on /status after a timeout goes to token rejected', () async {
      final power = FakePowerRepository(script: [const FakePowerTimeout()]);
      final status = FakeStatusRepository([
        fakeErrorReply(401, 'invalid_token'),
      ]);
      final h = await _harness(power: power, status: status);

      await h.flow.begin(PowerAction.sleep);

      expect(h.state, isA<PowerFlowIdle>());
      expect(h.phase, ConnectionPhase.tokenRejected);
    });

    test('a second begin while a flow is active is ignored', () async {
      final power = FakePowerRepository();
      final h = await _harness(power: power);

      await h.flow.begin(PowerAction.sleep);
      await h.flow.begin(PowerAction.shutdown);

      expect(power.scheduleCalls, 1);
      expect(_asCounting(h.state).action, PowerAction.sleep);
    });
  });

  group('cancel (BR-17, technical-spec §6)', () {
    test('200 cancels and clears lastPowerCommand', () async {
      final power = FakePowerRepository();
      final h = await _harness(power: power);
      await h.flow.begin(PowerAction.shutdown);

      await h.flow.cancel();

      final result = _asResult(h.state);
      expect(result, isA<PowerCancelled>());
      expect((result as PowerCancelled).action, PowerAction.shutdown);
      expect(h.lastCommand, isNull);
      expect(power.cancelCalls, 1);
    });

    test(
      'a stale pending of a cancelled schedule does not reopen the countdown',
      () async {
        final h = await _harness(power: FakePowerRepository());
        await h.flow.begin(PowerAction.shutdown);
        await h.flow.cancel();
        expect(_asResult(h.state), isA<PowerCancelled>());
        h.flow.dismiss();

        h.flow.resumeFromStatus(
          _pending(PowerAction.shutdown, remainingMs: 3000),
        );

        expect(h.state, isA<PowerFlowIdle>());
      },
    );

    test(
      '409 no_pending_power also keeps the old pending from coming back',
      () async {
        final power = FakePowerRepository(
          script: [
            const FakePowerOk(),
            fakePowerError(409, 'no_pending_power'),
          ],
        );
        final h = await _harness(power: power);
        await h.flow.begin(PowerAction.sleep);
        await h.flow.cancel();
        h.flow.dismiss();

        h.flow.resumeFromStatus(_pending(PowerAction.sleep, remainingMs: 3000));

        expect(h.state, isA<PowerFlowIdle>());
      },
    );

    test(
      '409 no_pending_power counts as cancelled and clears lastPowerCommand',
      () async {
        final power = FakePowerRepository(
          script: [
            const FakePowerOk(),
            fakePowerError(409, 'no_pending_power'),
          ],
        );
        final h = await _harness(power: power);
        await h.flow.begin(PowerAction.sleep);

        await h.flow.cancel();

        expect(_asResult(h.state), isA<PowerCancelled>());
        expect(h.lastCommand, isNull);
      },
    );

    test('409 power_executing shows P14 with elapsed seconds and keeps the command', () async {
      final power = FakePowerRepository(
        script: [const FakePowerOk(), fakePowerError(409, 'power_executing')],
      );
      final h = await _harness(power: power);
      await h.flow.begin(PowerAction.shutdown);
      h.tick(2);

      await h.flow.cancel();

      final result = _asResult(h.state);
      expect(result, isA<PowerTooLate>());
      final tooLate = result as PowerTooLate;
      expect(tooLate.action, PowerAction.shutdown);
      expect(tooLate.elapsed, 2);
      expect(tooLate.fromThisPhone, isTrue);
      expect(h.lastCommand, isNotNull);
    });

    test('cancel timeout shows P11, the countdown keeps running, and only the user repeats cancel', () async {
      final power = FakePowerRepository(
        script: [
          const FakePowerOk(),
          const FakePowerTimeout(),
          const FakePowerOk(),
        ],
      );
      final h = await _harness(power: power);
      await h.flow.begin(PowerAction.shutdown);

      await h.flow.cancel();

      var counting = _asCounting(h.state);
      expect(counting.cancelFailed, isTrue);
      expect(counting.remaining, 5);
      expect(power.cancelCalls, 1);

      h.tick(2);
      counting = _asCounting(h.state);
      expect(counting.remaining, 3);
      expect(power.cancelCalls, 1, reason: 'no automatic retry');

      await h.flow.cancel();

      expect(_asResult(h.state), isA<PowerCancelled>());
      expect(power.cancelCalls, 2);
    });

    test('a tap while a cancel is pending is ignored', () async {
      final power = FakePowerRepository();
      final h = await _harness(power: power);
      await h.flow.begin(PowerAction.shutdown);

      final first = h.flow.cancel();
      await h.flow.cancel();
      await first;

      expect(power.cancelCalls, 1);
      expect(_asResult(h.state), isA<PowerCancelled>());
    });

    test(
      'countdown reaching 0 during a cancel waits for the cancel reply',
      () async {
        final power = _GatedPower();
        final h = await _harness(power: power);
        await h.flow.begin(PowerAction.shutdown);

        final pendingCancel = h.flow.cancel();
        h.tick(5);

        expect(h.state, isA<PowerFlowCancelling>());
        expect((h.state as PowerFlowCancelling).counting.remaining, 0);

        power.gate!.complete(PowerAction.shutdown);
        await pendingCancel;

        expect(_asResult(h.state), isA<PowerCancelled>());
      },
    );

    test(
      'failed cancel after the countdown reached 0 sends the command',
      () async {
        final power = _GatedPower();
        final h = await _harness(power: power);
        await h.flow.begin(PowerAction.shutdown);

        final pendingCancel = h.flow.cancel();
        h.tick(5);
        power.gate!.completeError(const TimeoutFailure());
        await pendingCancel;

        final result = _asResult(h.state);
        expect(result, isA<PowerSent>());
        expect((result as PowerSent).action, PowerAction.shutdown);
      },
    );

    test(
      '401 during cancel goes to token rejected and returns to idle',
      () async {
        final power = FakePowerRepository(
          script: [const FakePowerOk(), fakePowerError(401, 'invalid_token')],
        );
        final h = await _harness(power: power);
        await h.flow.begin(PowerAction.shutdown);

        await h.flow.cancel();

        expect(h.state, isA<PowerFlowIdle>());
        expect(h.phase, ConnectionPhase.tokenRejected);
      },
    );
  });

  group('countdown and restart (FR-4.12)', () {
    test('restart sent at 0 turns the fast poll on', () async {
      final power = FakePowerRepository();
      final h = await _harness(power: power);
      h.startConnection();
      expect(h.periodicDelays, contains(RMotion.poll));

      await h.flow.begin(PowerAction.restart);
      expect(h.periodicDelays, isNot(contains(RBehavior.fastPoll)));

      h.tick(5);

      expect(_asResult(h.state), isA<PowerSent>());
      expect(h.periodicDelays, contains(RBehavior.fastPoll));
      expect(h.periodicDelays, isNot(contains(RMotion.poll)));
    });

    test('sleep sent at 0 does not change the poll interval', () async {
      final power = FakePowerRepository();
      final h = await _harness(power: power);
      h.startConnection();
      await h.flow.begin(PowerAction.sleep);

      h.tick(5);

      expect(_asResult(h.state), isA<PowerSent>());
      expect(h.periodicDelays, contains(RMotion.poll));
      expect(h.periodicDelays, isNot(contains(RBehavior.fastPoll)));
    });

    test('timers are cancelled on dispose', () async {
      final power = FakePowerRepository();
      final h = await _harness(power: power);
      await h.flow.begin(PowerAction.shutdown);

      h.dispose();

      expect(h.scheduler.jobs.where((job) => job.live), isEmpty);
    });
  });

  group('resume from status (FR-4.9, FR-4.10, BR-19, BR-20)', () {
    test(
      'pending with 3000 ms left counts 3 seconds, since 2, medium haptic',
      () async {
        final h = await _harness(power: FakePowerRepository());

        h.flow.resumeFromStatus(_pending(PowerAction.sleep, remainingMs: 3000));

        final counting = _asCounting(h.state);
        expect(counting.action, PowerAction.sleep);
        expect(counting.remaining, 3);
        expect(counting.since, 2);
        expect(counting.total, 5);
        expect(counting.fromThisPhone, isFalse);
        expect(h.sink.calls, contains('medium'));
      },
    );

    test('pending with 999 ms left is too late (P14), elapsed 4', () async {
      final h = await _harness(power: FakePowerRepository());

      h.flow.resumeFromStatus(_pending(PowerAction.shutdown, remainingMs: 999));

      final result = _asResult(h.state);
      expect(result, isA<PowerTooLate>());
      expect((result as PowerTooLate).elapsed, 4);
    });

    test(
      'pending with 0 ms is too late (P14), and restart enables the fast poll',
      () async {
        final h = await _harness(power: FakePowerRepository());
        h.startConnection();

        h.flow.resumeFromStatus(_pending(PowerAction.restart, remainingMs: 0));

        final result = _asResult(h.state);
        expect(result, isA<PowerTooLate>());
        expect((result as PowerTooLate).elapsed, 5);
        expect(h.periodicDelays, contains(RBehavior.fastPoll));
      },
    );

    test(
      'fromThisPhone is true only when lastPowerCommand has the same action',
      () async {
        final same = await _harness(power: FakePowerRepository());
        same.container
            .read(lastPowerCommandProvider.notifier)
            .record(LastPowerCommand(action: 'sleep', sentAt: same.clock.now));
        same.flow.resumeFromStatus(
          _pending(PowerAction.sleep, remainingMs: 3000),
        );
        expect(_asCounting(same.state).fromThisPhone, isTrue);

        final other = await _harness(power: FakePowerRepository());
        other.container
            .read(lastPowerCommandProvider.notifier)
            .record(LastPowerCommand(action: 'sleep', sentAt: other.clock.now));
        other.flow.resumeFromStatus(
          _pending(PowerAction.restart, remainingMs: 3000),
        );
        expect(_asCounting(other.state).fromThisPhone, isFalse);

        final none = await _harness(power: FakePowerRepository());
        none.flow.resumeFromStatus(
          _pending(PowerAction.sleep, remainingMs: 3000),
        );
        expect(_asCounting(none.state).fromThisPhone, isFalse);
      },
    );

    test('pending from polling is ignored while a flow is not idle', () async {
      final h = await _harness(power: FakePowerRepository());
      await h.flow.begin(PowerAction.shutdown);

      h.flow.resumeFromStatus(_pending(PowerAction.sleep, remainingMs: 2000));

      final counting = _asCounting(h.state);
      expect(counting.action, PowerAction.shutdown);
      expect(counting.remaining, 5);
    });

    test(
      'a sent schedule the user closed is not shown again (loop guard)',
      () async {
        final h = await _harness(power: FakePowerRepository());
        await h.flow.begin(PowerAction.shutdown);
        h.tick(5);
        expect(_asResult(h.state), isA<PowerSent>());

        h.flow.dismiss();
        expect(h.state, isA<PowerFlowIdle>());

        h.flow.resumeFromStatus(
          _pending(PowerAction.shutdown, remainingMs: 3000),
        );
        expect(h.state, isA<PowerFlowIdle>());
      },
    );

    test(
      'a too-late schedule the user closed is not shown again (loop guard)',
      () async {
        final h = await _harness(power: FakePowerRepository());
        h.flow.resumeFromStatus(_pending(PowerAction.sleep, remainingMs: 0));
        expect(_asResult(h.state), isA<PowerTooLate>());

        h.flow.dismiss();
        h.flow.resumeFromStatus(_pending(PowerAction.sleep, remainingMs: 0));

        expect(h.state, isA<PowerFlowIdle>());
      },
    );

    test(
      'a different schedule is shown even after another one was closed',
      () async {
        final h = await _harness(power: FakePowerRepository());
        h.flow.resumeFromStatus(_pending(PowerAction.sleep, remainingMs: 0));
        h.flow.dismiss();

        h.flow.resumeFromStatus(
          Pending(
            action: PowerAction.sleep.wire,
            remainingMs: 3000,
            delayMs: 5000,
            scheduledAt: '2026-01-02T08:00:00+07:00',
          ),
        );

        expect(_asCounting(h.state).remaining, 3);
      },
    );

    test('dismiss does nothing while a countdown runs', () async {
      final h = await _harness(power: FakePowerRepository());
      await h.flow.begin(PowerAction.shutdown);

      h.flow.dismiss();

      expect(_asCounting(h.state).remaining, 5);
    });
  });
}
