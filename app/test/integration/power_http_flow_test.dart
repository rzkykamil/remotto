import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotto/core/connection/connection_providers.dart';
import 'package:remotto/core/connection/connection_state.dart';
import 'package:remotto/core/haptics/r_haptics.dart';
import 'package:remotto/core/network/network_providers.dart';
import 'package:remotto/core/storage/pairing_data.dart';
import 'package:remotto/core/storage/storage_providers.dart';
import 'package:remotto/features/remote/data/http_power_repository.dart';
import 'package:remotto/features/remote/data/power_repository.dart';
import 'package:remotto/features/remote/power/power_flow_controller.dart';
import 'package:remotto/features/remote/power/power_flow_state.dart';
import 'package:remotto/features/remote/power/power_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_poll_scheduler.dart';
import '../support/fakes.dart';
import 'fake_agent_server.dart';

/// Integration test: the power flow goes through the real default
/// `powerRepositoryProvider` (HttpPowerRepository -> AgentHttpClient -> IOClient)
/// to a loopback fake agent. Only the poll scheduler, haptics, and the
/// connection storage are fakes. No real power command is sent to a laptop.
void main() {
  late FakeAgentServer server;
  late FakePollScheduler scheduler;
  late RecordingHapticSink sink;
  ProviderContainer? container;
  late SharedPreferences prefs;

  const shutdownPath = '/api/v1/power/shutdown';
  const sleepPath = '/api/v1/power/sleep';
  const cancelPath = '/api/v1/power/cancel';
  const scheduledAt = '2026-01-01T23:41:00+07:00';
  const shortTimeout = Duration(milliseconds: 100);
  final wrongToken = 'b' * 64;

  ProviderContainer c() => container!;

  /// Builds the container. [powerTimeout] swaps in an HttpPowerRepository with
  /// a short per-request limit; without it the default provider is used.
  void boot({Duration? powerTimeout}) {
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        initialPairingProvider.overrideWithValue(
          PairingData(
            host: '127.0.0.1',
            port: server.port,
            token: fakeAgentToken,
            laptopName: 'Laptop-Kamil',
          ),
        ),
        connectionStorageProvider.overrideWithValue(
          InMemoryConnectionStorage(),
        ),
        pollSchedulerProvider.overrideWithValue(scheduler),
        hapticSinkProvider.overrideWithValue(sink),
        if (powerTimeout != null)
          powerRepositoryProvider.overrideWith(
            (ref) => HttpPowerRepository(
              ref.watch(agentHttpClientProvider),
              () => ref.read(pairingProvider),
              timeout: powerTimeout,
            ),
          ),
      ],
    );
  }

  PowerFlowState flowState() => c().read(powerFlowControllerProvider);

  PowerFlowController flow() => c().read(powerFlowControllerProvider.notifier);

  ConnectionPhase phase() => c().read(connectionControllerProvider).phase;

  String? lastCommand() => c().read(lastPowerCommandProvider)?.action;

  PowerFlowCounting counting() {
    final state = flowState();
    expect(state, isA<PowerFlowCounting>());
    return state as PowerFlowCounting;
  }

  PowerResult result() {
    final state = flowState();
    expect(state, isA<PowerFlowResult>());
    return (state as PowerFlowResult).result;
  }

  /// Runs the 1 s countdown ticker [times] times, as the real timer would.
  /// The connection poll (5 s) is a different periodic job and is skipped.
  void tick([int times = 1]) {
    for (var i = 0; i < times; i++) {
      final ticker = scheduler.jobs.lastWhere(
        (job) =>
            job.live && job.periodic && job.delay == const Duration(seconds: 1),
      );
      ticker.run();
    }
  }

  setUp(() async {
    server = await FakeAgentServer.start();
    scheduler = FakePollScheduler();
    sink = RecordingHapticSink();
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  tearDown(() async {
    container?.dispose();
    container = null;
    await server.close();
  });

  test('default provider is HttpPowerRepository (no override)', () {
    boot();

    expect(c().read(powerRepositoryProvider), isA<HttpPowerRepository>());
  });

  test(
    'schedule shutdown: counting 5 of 5, one POST, lastPowerCommand recorded',
    () async {
      boot();

      await flow().begin(PowerAction.shutdown);

      final state = counting();
      expect(state.action, PowerAction.shutdown);
      expect(state.remaining, 5);
      expect(state.total, 5);
      expect(state.since, 0);
      expect(state.fromThisPhone, isTrue);
      expect(server.powerPaths, [shutdownPath]);
      expect(server.pending?.action, 'shutdown');
      expect(lastCommand(), 'shutdown');
    },
  );

  test('cancel while counting: PowerCancelled, server has no pending, lastPowerCommand cleared', () async {
    boot();
    await flow().begin(PowerAction.shutdown);

    await flow().cancel();

    final cancelled = result();
    expect(cancelled, isA<PowerCancelled>());
    expect((cancelled as PowerCancelled).action, PowerAction.shutdown);
    expect(server.pending, isNull);
    expect(lastCommand(), isNull);
    expect(server.powerPaths, [shutdownPath, cancelPath]);
  });

  test('409 power_pending: reads /status and counts the server pending, old schedule untouched', () async {
    boot();
    server.pending = const FakePending(
      action: 'sleep',
      remainingMs: 3000,
      delayMs: 5000,
      scheduledAt: scheduledAt,
    );
    final before = server.requests;

    await flow().begin(PowerAction.shutdown);

    final state = counting();
    // The countdown shows the schedule that exists on the laptop, not the
    // action the user just tried to send.
    expect(state.action, PowerAction.sleep);
    expect(state.remaining, 3);
    expect(state.since, 2);
    expect(state.total, 5);
    expect(state.fromThisPhone, isFalse);
    expect(lastCommand(), isNull, reason: 'a 409 is not a sent command');
    expect(server.powerPaths, [shutdownPath], reason: 'no second schedule');
    expect(server.requests - before, 2, reason: 'one POST and one GET /status');
    expect(server.pending?.action, 'sleep');
    expect(server.pending?.remainingMs, 3000);
  });

  test(
    '500 power_failed: PowerNotScheduled, exactly one request, no retry',
    () async {
      boot();
      server.failNextPowerSchedule = true;

      await flow().begin(PowerAction.sleep);

      final notScheduled = result();
      expect(notScheduled, isA<PowerNotScheduled>());
      expect((notScheduled as PowerNotScheduled).action, PowerAction.sleep);
      expect(server.requests, 1, reason: 'no /status read and no retry');
      expect(server.powerPaths, [sleepPath]);
      expect(server.pending, isNull);
      expect(lastCommand(), isNull);
      expect(sink.calls, contains('vibrate'));
    },
  );

  group('schedule timeout', () {
    test(
      'timeout, /status has no pending: PowerNotScheduled, one POST',
      () async {
        boot(powerTimeout: shortTimeout);
        server.hold = Completer<void>();

        final pending = flow().begin(PowerAction.sleep);
        await server.untilRequests(1);
        // Only the POST is held. Release the hold so /status can answer.
        server.hold = null;
        await pending;

        expect(result(), isA<PowerNotScheduled>());
        expect(server.powerPaths, [sleepPath], reason: 'no second schedule');
        expect(lastCommand(), isNull);
      },
    );

    test('timeout, schedule stored on the laptop: counts from the remaining time', () async {
      boot(powerTimeout: shortTimeout);
      server.storePendingBeforeHold = true;
      server.hold = Completer<void>();

      final pending = flow().begin(PowerAction.sleep);
      await server.untilRequests(1);
      // The schedule was stored before the reply got lost. By the time /status
      // is read, 3 s are left on the laptop.
      server.pending = const FakePending(
        action: 'sleep',
        remainingMs: 3000,
        delayMs: 5000,
        scheduledAt: scheduledAt,
      );
      server.hold = null;
      await pending;

      final state = counting();
      expect(state.action, PowerAction.sleep);
      expect(state.remaining, 3);
      expect(state.since, 2);
      expect(state.total, 5);
      expect(state.fromThisPhone, isTrue);
      expect(lastCommand(), 'sleep');
      expect(server.powerPaths, [sleepPath], reason: 'no second schedule');
    });
  });

  group('cancel', () {
    test(
      '409 no_pending_power: PowerCancelled and lastPowerCommand cleared',
      () async {
        boot();
        await flow().begin(PowerAction.shutdown);
        // Another client already cancelled it on the laptop.
        server.pending = null;

        await flow().cancel();

        final cancelled = result();
        expect(cancelled, isA<PowerCancelled>());
        expect((cancelled as PowerCancelled).action, PowerAction.shutdown);
        expect(lastCommand(), isNull);
      },
    );

    test(
      '409 power_executing: PowerTooLate with elapsed seconds, no retry',
      () async {
        boot();
        await flow().begin(PowerAction.shutdown);
        tick(4);
        // The laptop has started executing the command.
        server.pending = const FakePending(
          action: 'shutdown',
          remainingMs: 0,
          delayMs: 5000,
          scheduledAt: scheduledAt,
        );

        await flow().cancel();

        final tooLate = result();
        expect(tooLate, isA<PowerTooLate>());
        final late = tooLate as PowerTooLate;
        expect(late.action, PowerAction.shutdown);
        expect(late.elapsed, 4);
        expect(late.fromThisPhone, isTrue);
        expect(server.powerPaths, [shutdownPath, cancelPath]);
      },
    );

    test('cancel 500: cancelFailed, countdown continues, one cancel until the user repeats it', () async {
      boot();
      await flow().begin(PowerAction.shutdown);
      server.mode = FakeAgentMode.serverError;

      await flow().cancel();

      var state = counting();
      expect(state.cancelFailed, isTrue);
      expect(state.remaining, 5);
      expect(server.powerPaths, [shutdownPath, cancelPath]);

      tick(2);
      expect(counting().remaining, 3);
      expect(server.powerPaths, [
        shutdownPath,
        cancelPath,
      ], reason: 'no automatic retry');

      server.mode = FakeAgentMode.ok;
      await flow().cancel();

      expect(result(), isA<PowerCancelled>());
      expect(server.powerPaths, [shutdownPath, cancelPath, cancelPath]);
      expect(server.pending, isNull);
    });

    test('cancel timeout: cancelFailed, countdown continues, one cancel until the user repeats it', () async {
      boot(powerTimeout: shortTimeout);
      await flow().begin(PowerAction.shutdown);
      server.hold = Completer<void>();

      await flow().cancel();

      var state = counting();
      expect(state.cancelFailed, isTrue);
      expect(state.remaining, 5);
      expect(server.powerPaths, [shutdownPath, cancelPath]);

      tick(2);
      expect(counting().remaining, 3);
      expect(server.powerPaths, [
        shutdownPath,
        cancelPath,
      ], reason: 'no automatic retry');

      server.hold = null;
      await flow().cancel();

      expect(result(), isA<PowerCancelled>());
      expect(server.powerPaths, [shutdownPath, cancelPath, cancelPath]);
    });
  });

  group('token rejected', () {
    test('401 on schedule: idle and connection phase tokenRejected', () async {
      boot();
      server.token = wrongToken;

      await flow().begin(PowerAction.sleep);

      expect(flowState(), isA<PowerFlowIdle>());
      expect(phase(), ConnectionPhase.tokenRejected);
      expect(server.powerPaths, [sleepPath]);
    });

    test('401 on cancel: idle and connection phase tokenRejected', () async {
      boot();
      await flow().begin(PowerAction.shutdown);
      server.token = wrongToken;

      await flow().cancel();

      expect(flowState(), isA<PowerFlowIdle>());
      expect(phase(), ConnectionPhase.tokenRejected);
    });
  });

  test('/status with pending is parsed by the HTTP repository and resumes counting', () async {
    boot();
    server.pending = const FakePending(
      action: 'restart',
      remainingMs: 3000,
      delayMs: 5000,
      scheduledAt: scheduledAt,
    );

    final status = await c().read(statusRepositoryProvider).fetchStatus();
    final pending = status.pending;
    expect(pending, isNotNull);
    expect(pending!.action, 'restart');
    expect(pending.remainingMs, 3000);
    expect(pending.delayMs, 5000);
    expect(pending.scheduledAt, scheduledAt);

    flow().resumeFromStatus(pending);

    final state = counting();
    expect(state.action, PowerAction.restart);
    expect(state.remaining, 3);
    expect(state.since, 2);
    expect(state.fromThisPhone, isFalse);
    expect(server.powerPaths, isEmpty, reason: 'resume only reads status');
  });

  test('/status without pending: resume does nothing', () async {
    boot();

    final status = await c().read(statusRepositoryProvider).fetchStatus();
    expect(status.pending, isNull);

    // Nothing to resume: the flow stays idle and no request is sent.
    expect(flowState(), isA<PowerFlowIdle>());
    expect(server.powerPaths, isEmpty);
  });
}
