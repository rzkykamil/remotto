import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:remotto/app.dart';
import 'package:remotto/core/connection/connection_providers.dart';
import 'package:remotto/core/connection/connection_state.dart';
import 'package:remotto/core/haptics/r_haptics.dart';
import 'package:remotto/core/network/api_failure.dart';
import 'package:remotto/core/network/network_providers.dart';
import 'package:remotto/core/storage/pairing_data.dart';
import 'package:remotto/core/storage/storage_providers.dart';
import 'package:remotto/core/strings/power_strings.dart';
import 'package:remotto/core/theme/app_theme.dart';
import 'package:remotto/core/theme/r_behavior.dart';
import 'package:remotto/core/theme/tokens.g.dart';
import 'package:remotto/features/remote/power/countdown_screen.dart';
import 'package:remotto/features/remote/power/power_flow_host.dart';
import 'package:remotto/features/remote/power/power_providers.dart';
import 'package:remotto/features/remote/power/result_screen.dart';
import 'package:remotto/features/remote/power/wakelock_controller.dart';
import 'package:remotto/features/remote/remote_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_poll_scheduler.dart';
import '../../support/fake_power_repository.dart';
import '../../support/fake_status_repository.dart';
import '../../support/fakes.dart';
import '../../support/volume_overrides.dart';

const _pairing = PairingData(
  host: '192.168.1.10',
  port: 8765,
  token: 'test-token',
  laptopName: 'Laptop-Kamil',
);

const _scheduledAt = '2026-01-01T23:41:00+07:00';
const _otherScheduledAt = '2026-01-01T23:50:00+07:00';

/// `pending` object of the status (api-spec). [delayMs] is the full delay.
Map<String, Object?> _pending({
  required String action,
  required int remainingMs,
  int delayMs = 5000,
  String scheduledAt = _scheduledAt,
}) {
  return {
    'action': action,
    'remainingMs': remainingMs,
    'delayMs': delayMs,
    'scheduledAt': scheduledAt,
  };
}

/// Status reply with [pending] (null = no schedule).
FakeHttpReply _status([Map<String, Object?>? pending]) =>
    fakeStatusOk(name: 'Laptop-Kamil', pending: pending);

/// Records the screen wakelock calls.
final class _FakeWakelock implements WakelockController {
  @override
  Future<void> enable() async {}

  @override
  Future<void> disable() async {}
}

final class _Harness {
  _Harness({
    required this.container,
    required this.scheduler,
    required this.haptics,
  });

  final ProviderContainer container;
  final FakePollScheduler scheduler;
  final RecordingHapticSink haptics;

  /// Runs one status poll (every 5 s), the periodic job with the poll interval.
  Future<void> pollStatus(WidgetTester tester) async {
    final poll = scheduler.jobs.lastWhere(
      (job) => job.live && job.periodic && job.delay == RMotion.poll,
    );
    poll.run();
    await _settle(tester);
  }

  /// Runs the countdown ticker [times] times, as the real 1 s timer would.
  Future<void> tickCountdown(WidgetTester tester, {int times = 1}) async {
    for (var i = 0; i < times; i++) {
      final ticker = scheduler.jobs.lastWhere(
        (job) =>
            job.live && job.periodic && job.delay == const Duration(seconds: 1),
      );
      ticker.run();
    }
    await _settle(tester);
  }
}

/// Waits for the futures of the fakes, then rebuilds the frames.
Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(() => pumpEventQueue());
  await tester.pumpAndSettle();
}

/// Opens the full app at Remote. The first status reply is [status] (the
/// status steps repeat the last one when they run out).
Future<_Harness> _pumpApp(
  WidgetTester tester, {
  required List<FakeStatusStep> status,
  required FakePowerRepository power,
}) async {
  tester.view.physicalSize = const Size(412, 892);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  final prefs = (await tester.runAsync(() async {
    SharedPreferences.setMockInitialValues({});
    return SharedPreferences.getInstance();
  }))!;
  final scheduler = FakePollScheduler();
  final haptics = RecordingHapticSink();

  await tester.pumpWidget(
    ProviderScope(
      overrides: _overrides(
        prefs: prefs,
        status: status,
        power: power,
        scheduler: scheduler,
        haptics: haptics,
      ),
      child: const RemottoApp(),
    ),
  );
  await _settle(tester);

  return _Harness(
    container: ProviderScope.containerOf(
      tester.element(find.byType(RemottoApp)),
    ),
    scheduler: scheduler,
    haptics: haptics,
  );
}

/// Fakes shared by the app and the host-only test.
List<Override> _overrides({
  required SharedPreferences prefs,
  required List<FakeStatusStep> status,
  required FakePowerRepository power,
  required FakePollScheduler scheduler,
  required RecordingHapticSink haptics,
}) {
  return [
    sharedPreferencesProvider.overrideWithValue(prefs),
    initialPairingProvider.overrideWithValue(_pairing),
    connectionStorageProvider.overrideWithValue(
      InMemoryConnectionStorage(_pairing),
    ),
    statusRepositoryProvider.overrideWithValue(FakeStatusRepository(status)),
    pollSchedulerProvider.overrideWithValue(scheduler),
    volumeOverride(),
    powerRepositoryProvider.overrideWithValue(power),
    wakelockControllerProvider.overrideWithValue(_FakeWakelock()),
    hapticSinkProvider.overrideWithValue(haptics),
  ];
}

Future<void> _tap(WidgetTester tester, String text) async {
  await tester.tap(find.text(text));
  await _settle(tester);
}

/// Text of the countdown, in the countdown screen only.
Finder _countNumber(String n) =>
    find.descendant(of: find.byType(CountdownScreen), matching: find.text(n));

/// Loads the bundled Geist font, so label widths match the app and not the
/// test font (Ahem, one em per glyph).
Future<void> _loadGeist() async {
  final loader = FontLoader('Geist');
  for (final name in ['Geist-Regular', 'Geist-Medium', 'Geist-SemiBold']) {
    final bytes = File('assets/fonts/$name.ttf').readAsBytesSync();
    loader.addFont(
      Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)),
    );
  }
  await loader.load();
}

void main() {
  setUpAll(_loadGeist);

  testWidgets(
    'FR-4.9: pending sisa 3000 ms saat app dibuka langsung P13 dengan angka 3, haptic medium',
    (tester) async {
      final power = FakePowerRepository();
      final h = await _pumpApp(
        tester,
        power: power,
        status: [_status(_pending(action: 'shutdown', remainingMs: 3000))],
      );

      expect(find.byType(CountdownScreen), findsOneWidget);
      expect(find.text(PowerStrings.countdownTitleShutdown), findsOneWidget);
      expect(_countNumber('3'), findsOneWidget);
      // 5 s delay, 3 s left: 2 s already passed.
      expect(find.text(PowerStrings.since(2)), findsOneWidget);
      expect(find.byType(ResultScreen), findsNothing);
      expect(find.byType(RemoteScreen), findsOneWidget);
      expect(h.haptics.calls, ['medium']);
      expect(power.scheduleCalls, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'FR-4.13: label "dari HP ini" tampil bila lastPowerCommand cocok',
    (tester) async {
      final power = FakePowerRepository();
      final h = await _pumpApp(
        tester,
        power: power,
        status: [
          const FakeTransportFailure(UnreachableFailure()),
          _status(_pending(action: 'shutdown', remainingMs: 3000)),
        ],
      );

      // The first poll failed, so the phone is still connecting and nothing
      // is resumed yet. The command was sent from this phone earlier.
      expect(find.byType(CountdownScreen), findsNothing);
      h.container
          .read(lastPowerCommandProvider.notifier)
          .record(LastPowerCommand(action: 'shutdown', sentAt: DateTime.now()));

      await h.pollStatus(tester);

      expect(find.byType(CountdownScreen), findsOneWidget);
      expect(
        find.text(PowerStrings.since(2, fromThisPhone: true)),
        findsOneWidget,
      );
      expect(find.text(PowerStrings.since(2)), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'FR-4.13: tanpa lastPowerCommand yang cocok, frasa "dari HP ini" tidak tampil',
    (tester) async {
      final h = await _pumpApp(
        tester,
        power: FakePowerRepository(),
        status: [
          const FakeTransportFailure(UnreachableFailure()),
          _status(_pending(action: 'shutdown', remainingMs: 3000)),
        ],
      );
      // This phone sent a sleep, not the shutdown on the laptop.
      h.container
          .read(lastPowerCommandProvider.notifier)
          .record(LastPowerCommand(action: 'sleep', sentAt: DateTime.now()));

      await h.pollStatus(tester);

      expect(find.byType(CountdownScreen), findsOneWidget);
      expect(find.text(PowerStrings.since(2)), findsOneWidget);
      expect(
        find.text(PowerStrings.since(2, fromThisPhone: true)),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final remainingMs in [800, 0]) {
    testWidgets(
      'FR-4.10: pending sisa $remainingMs ms langsung P14 tanpa tombol Batal',
      (tester) async {
        final power = FakePowerRepository();
        final h = await _pumpApp(
          tester,
          power: power,
          status: [
            _status(_pending(action: 'shutdown', remainingMs: remainingMs)),
          ],
        );

        expect(find.byType(CountdownScreen), findsNothing);
        expect(find.byType(ResultScreen), findsOneWidget);
        expect(find.text(PowerStrings.lateTitle), findsOneWidget);
        expect(find.text(PowerStrings.lateAction), findsOneWidget);
        expect(find.text(PowerStrings.countdownCancel), findsNothing);
        expect(find.text(PowerStrings.countdownCancelAgain), findsNothing);
        expect(power.cancelCalls, 0);
        expect(h.haptics.calls, isNot(contains('medium')));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'P14 ditutup, poll berikutnya dengan jadwal yang sama tidak membuka P14 lagi',
    (tester) async {
      final power = FakePowerRepository();
      final h = await _pumpApp(
        tester,
        power: power,
        status: [
          _status(_pending(action: 'shutdown', remainingMs: 800)),
          // Same schedule, time has passed.
          _status(_pending(action: 'shutdown', remainingMs: 0)),
          _status(_pending(action: 'shutdown', remainingMs: 0)),
        ],
      );
      expect(find.byType(ResultScreen), findsOneWidget);

      await _tap(tester, PowerStrings.lateAction);
      expect(find.byType(ResultScreen), findsNothing);

      await h.pollStatus(tester);
      expect(find.byType(ResultScreen), findsNothing);
      expect(find.byType(CountdownScreen), findsNothing);

      await h.pollStatus(tester);
      expect(find.byType(ResultScreen), findsNothing);
      expect(find.byType(CountdownScreen), findsNothing);
      expect(find.byType(RemoteScreen), findsOneWidget);
      expect(power.scheduleCalls, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'jadwal lain (scheduledAt beda) setelah P14 ditutup tetap dibuka sebagai P13',
    (tester) async {
      final h = await _pumpApp(
        tester,
        power: FakePowerRepository(),
        status: [
          _status(_pending(action: 'shutdown', remainingMs: 800)),
          _status(
            _pending(
              action: 'sleep',
              remainingMs: 3000,
              scheduledAt: _otherScheduledAt,
            ),
          ),
        ],
      );
      expect(find.byType(ResultScreen), findsOneWidget);

      await _tap(tester, PowerStrings.lateAction);
      await h.pollStatus(tester);

      expect(find.byType(CountdownScreen), findsOneWidget);
      expect(find.text(PowerStrings.countdownTitleSleep), findsOneWidget);
      expect(_countNumber('3'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'pending muncul saat Remote sudah terbuka (dari HP lain) langsung P13',
    (tester) async {
      final h = await _pumpApp(
        tester,
        power: FakePowerRepository(),
        status: [
          _status(),
          _status(_pending(action: 'shutdown', remainingMs: 3000)),
        ],
      );
      expect(find.byType(CountdownScreen), findsNothing);
      expect(find.byType(RemoteScreen), findsOneWidget);

      await h.pollStatus(tester);

      expect(find.byType(CountdownScreen), findsOneWidget);
      expect(_countNumber('3'), findsOneWidget);
      expect(h.haptics.calls, ['medium']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('pending null tidak melakukan apa pun', (tester) async {
    final power = FakePowerRepository();
    final h = await _pumpApp(
      tester,
      power: power,
      status: [_status(), _status()],
    );

    expect(find.byType(CountdownScreen), findsNothing);
    expect(find.byType(ResultScreen), findsNothing);
    expect(find.byType(RemoteScreen), findsOneWidget);

    await h.pollStatus(tester);

    expect(find.byType(CountdownScreen), findsNothing);
    expect(find.byType(ResultScreen), findsNothing);
    expect(h.haptics.calls, isEmpty);
    expect(power.scheduleCalls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'restart dari P13 saat hitung mundur habis mengaktifkan polling cepat (FR-4.12)',
    (tester) async {
      final h = await _pumpApp(
        tester,
        power: FakePowerRepository(),
        status: [_status(_pending(action: 'restart', remainingMs: 3000))],
      );
      expect(find.byType(CountdownScreen), findsOneWidget);
      expect(find.text(PowerStrings.countdownTitleRestart), findsOneWidget);

      await h.tickCountdown(tester, times: 3);

      expect(find.byType(ResultScreen), findsOneWidget);
      expect(find.text(PowerStrings.doneRestartTitle), findsOneWidget);
      final fast = h.scheduler.jobs.lastWhere(
        (job) => job.live && job.periodic,
      );
      expect(fast.delay, RBehavior.fastPoll);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'restart dengan sisa 800 ms: P14 dan polling cepat langsung aktif',
    (tester) async {
      final h = await _pumpApp(
        tester,
        power: FakePowerRepository(),
        status: [_status(_pending(action: 'restart', remainingMs: 800))],
      );

      expect(find.byType(ResultScreen), findsOneWidget);
      final fast = h.scheduler.jobs.lastWhere(
        (job) => job.live && job.periodic,
      );
      expect(fast.delay, RBehavior.fastPoll);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'host dipasang saat status sudah berisi pending: P13 langsung tanpa menunggu poll baru',
    (tester) async {
      tester.view.physicalSize = const Size(412, 892);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final prefs = (await tester.runAsync(() async {
        SharedPreferences.setMockInitialValues({});
        return SharedPreferences.getInstance();
      }))!;
      final scheduler = FakePollScheduler();
      final haptics = RecordingHapticSink();
      final container = ProviderContainer(
        overrides: _overrides(
          prefs: prefs,
          status: [_status(_pending(action: 'shutdown', remainingMs: 3000))],
          power: FakePowerRepository(),
          scheduler: scheduler,
          haptics: haptics,
        ),
      );
      addTearDown(container.dispose);

      // The status is read before any screen is mounted, as an earlier
      // Remote session would have left it.
      container.read(connectionControllerProvider.notifier).start();
      await tester.runAsync(() => pumpEventQueue());
      expect(
        container.read(connectionControllerProvider).phase,
        ConnectionPhase.online,
      );
      expect(haptics.calls, isEmpty);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            home: PowerFlowHost(
              builder: (context, onSelected) =>
                  const Scaffold(body: SizedBox.shrink()),
            ),
          ),
        ),
      );
      await _settle(tester);

      expect(find.byType(CountdownScreen), findsOneWidget);
      expect(_countNumber('3'), findsOneWidget);
      expect(haptics.calls, ['medium']);
      expect(tester.takeException(), isNull);
    },
  );
}
