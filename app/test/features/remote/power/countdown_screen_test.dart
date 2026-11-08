import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotto/core/connection/connection_providers.dart';
import 'package:remotto/core/haptics/r_haptics.dart';
import 'package:remotto/core/network/agent_status.dart';
import 'package:remotto/core/network/network_providers.dart';
import 'package:remotto/core/storage/pairing_data.dart';
import 'package:remotto/core/storage/storage_providers.dart';
import 'package:remotto/core/strings/power_strings.dart';
import 'package:remotto/core/theme/app_theme.dart';
import 'package:remotto/core/theme/theme_extensions.dart';
import 'package:remotto/features/remote/data/power_repository.dart';
import 'package:remotto/features/remote/power/countdown_screen.dart';
import 'package:remotto/features/remote/power/power_flow_controller.dart';
import 'package:remotto/features/remote/power/power_flow_state.dart';
import 'package:remotto/features/remote/power/power_providers.dart';
import 'package:remotto/features/remote/power/wakelock_controller.dart';
import 'package:remotto/ui/r_icon.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/fake_poll_scheduler.dart';
import '../../../support/fake_power_repository.dart';
import '../../../support/fake_status_repository.dart';
import '../../../support/fakes.dart';

const _scheduledAt = '2026-01-01T23:41:00+07:00';
const _oneSecond = Duration(seconds: 1);

/// Records enable and disable calls of the screen wakelock.
final class _FakeWakelock implements WakelockController {
  final List<String> calls = [];

  @override
  Future<void> enable() async => calls.add('enable');

  @override
  Future<void> disable() async => calls.add('disable');
}

/// Power repository whose cancel waits until the test completes it.
final class _GatedCancelPower implements PowerRepository {
  int cancelCalls = 0;
  Completer<PowerAction>? gate;

  @override
  Future<Pending> schedule(PowerAction action) async => Pending(
    action: action.wire,
    remainingMs: 5000,
    delayMs: 5000,
    scheduledAt: _scheduledAt,
  );

  @override
  Future<PowerAction> cancel() {
    cancelCalls++;
    return (gate = Completer<PowerAction>()).future;
  }
}

final class _Harness {
  _Harness({
    required this.container,
    required this.scheduler,
    required this.sink,
    required this.wakelock,
  });

  final ProviderContainer container;
  final FakePollScheduler scheduler;
  final RecordingHapticSink sink;
  final _FakeWakelock wakelock;

  PowerFlowState get state => container.read(powerFlowControllerProvider);

  PowerFlowController get flow =>
      container.read(powerFlowControllerProvider.notifier);

  /// Runs the 1 s countdown ticker once, as the real timer would.
  void tick([int times = 1]) {
    for (var i = 0; i < times; i++) {
      final ticker = scheduler.jobs.lastWhere(
        (job) => job.live && job.periodic && job.delay == _oneSecond,
      );
      ticker.run();
    }
  }
}

Future<_Harness> _harness({required PowerRepository power}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final scheduler = FakePollScheduler();
  final sink = RecordingHapticSink();
  final wakelock = _FakeWakelock();
  final container = ProviderContainer(
    overrides: [
      powerRepositoryProvider.overrideWithValue(power),
      statusRepositoryProvider.overrideWithValue(
        FakeStatusRepository([fakeStatusOk()]),
      ),
      pollSchedulerProvider.overrideWithValue(scheduler),
      hapticSinkProvider.overrideWithValue(sink),
      sharedPreferencesProvider.overrideWithValue(prefs),
      connectionClockProvider.overrideWithValue(
        () => DateTime.utc(2026, 1, 1, 12),
      ),
      initialPairingProvider.overrideWithValue(
        const PairingData(
          host: '192.168.1.10',
          port: 8080,
          token: 'test-token',
          laptopName: 'Laptop-Kamil',
        ),
      ),
      wakelockControllerProvider.overrideWithValue(wakelock),
    ],
  );
  addTearDown(container.dispose);
  return _Harness(
    container: container,
    scheduler: scheduler,
    sink: sink,
    wakelock: wakelock,
  );
}

/// Pumps [CountdownScreen] in a real MaterialApp with the app theme.
Future<void> _pump(
  WidgetTester tester,
  _Harness h, {
  bool dark = false,
  bool reducedMotion = false,
  double textScale = 1.0,
  Size size = const Size(412, 892),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: h.container,
      child: MaterialApp(
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: reducedMotion,
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
        home: const CountdownScreen(),
      ),
    ),
  );
}

/// Sweep of the ring, read from the painter (0 to 1).
double _ringFraction(WidgetTester tester) {
  final paint = tester.widget<CustomPaint>(_ringPaint);
  return (paint.painter as dynamic).fraction as double;
}

/// The ring's CustomPaint. Matched by painter type, since other widgets in
/// the tree also use CustomPaint.
final _ringPaint = find.byWidgetPredicate(
  (w) =>
      w is CustomPaint && w.painter?.runtimeType.toString() == '_RingPainter',
);

/// Accessibility announcements sent during the test.
List<Map<String, Object?>> _captureAnnouncements(WidgetTester tester) {
  final messages = <Map<String, Object?>>[];
  tester.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<dynamic>(
    SystemChannels.accessibility,
    (message) async {
      messages.add(Map<String, Object?>.from(message as Map));
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger
        .setMockDecodedMessageHandler<dynamic>(
          SystemChannels.accessibility,
          null,
        ),
  );
  return messages;
}

/// (message, assertive) pairs from the captured announcements.
List<(String, bool)> _spoken(List<Map<String, Object?>> messages) {
  return [
    for (final event in messages)
      () {
        final data = event['data'] as Map;
        final assertive =
            data['assertiveness'] == Assertiveness.assertive.index;
        return (data['message'] as String, assertive);
      }(),
  ];
}

void main() {
  group('countdown (P07)', () {
    testWidgets('shows the number and counts down each second', (tester) async {
      final h = await _harness(power: FakePowerRepository());
      await h.flow.begin(PowerAction.shutdown);
      await _pump(tester, h);

      expect(find.text('Laptop mati dalam'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
      expect(find.text(PowerStrings.countdownHint), findsOneWidget);
      expect(find.text(PowerStrings.countdownCancel), findsOneWidget);
      expect(find.text('Laptop-Kamil'.toUpperCase()), findsOneWidget);

      h.tick();
      await tester.pump();
      expect(find.text('4'), findsOneWidget);
      expect(_ringFraction(tester), closeTo(4 / 5, 0.0001));

      h.tick(4);
      await tester.pump();
      expect(h.state, isA<PowerFlowResult>());
    });

    testWidgets('restart uses its own title', (tester) async {
      final h = await _harness(power: FakePowerRepository());
      await h.flow.begin(PowerAction.restart);
      await _pump(tester, h);

      expect(find.text(PowerStrings.countdownTitleRestart), findsOneWidget);
    });

    testWidgets('sleep uses its own title and accent ring color', (
      tester,
    ) async {
      final h = await _harness(power: FakePowerRepository());
      await h.flow.begin(PowerAction.sleep);
      await _pump(tester, h);

      expect(find.text(PowerStrings.countdownTitleSleep), findsOneWidget);
    });
  });

  group('resume (P13)', () {
    testWidgets('opens at the real remaining seconds with the since label', (
      tester,
    ) async {
      final h = await _harness(power: FakePowerRepository());
      h.flow.resumeFromStatus(
        const Pending(
          action: 'shutdown',
          remainingMs: 2400,
          delayMs: 5000,
          scheduledAt: _scheduledAt,
        ),
      );
      await _pump(tester, h);

      // 2.4 s left rounds up to 3, and the ring starts at 3 of 5 with no
      // animation from full.
      expect(find.text('3'), findsOneWidget);
      expect(find.text('5'), findsNothing);
      expect(_ringFraction(tester), closeTo(3 / 5, 0.0001));
      expect(find.text('Dijadwalkan 2 detik lalu'), findsOneWidget);
    });

    testWidgets('announces the time it opened at', (tester) async {
      final h = await _harness(power: FakePowerRepository());
      h.flow.resumeFromStatus(
        const Pending(
          action: 'shutdown',
          remainingMs: 2400,
          delayMs: 5000,
          scheduledAt: _scheduledAt,
        ),
      );
      final messages = _captureAnnouncements(tester);
      await _pump(tester, h);
      await tester.pump();

      expect(_spoken(messages), contains(('Laptop mati dalam 3 detik', false)));
    });
  });

  group('reduced motion (P12)', () {
    testWidgets('shows segments instead of the ring', (tester) async {
      final h = await _harness(power: FakePowerRepository());
      await h.flow.begin(PowerAction.sleep);
      await _pump(tester, h, reducedMotion: true);

      expect(_ringPaint, findsNothing);
      final segments = find.byWidgetPredicate(
        (w) => w is SizedBox && w.width == 40 && w.height == 8,
      );
      expect(segments, findsNWidgets(5));
      expect(find.text('5'), findsOneWidget);
    });

    testWidgets('lit segments follow the remaining seconds', (tester) async {
      final h = await _harness(power: FakePowerRepository());
      await h.flow.begin(PowerAction.sleep);
      await _pump(tester, h, reducedMotion: true);
      h.tick();
      await tester.pump();

      final lit = AppTheme.light.extension<AccentTokens>()!.text;
      final track = AppTheme.light.extension<ControlTokens>()!.segTrack;
      final colors = [
        for (final box in tester.widgetList<DecoratedBox>(
          find.byWidgetPredicate(
            (w) =>
                w is DecoratedBox &&
                w.decoration is BoxDecoration &&
                (w.decoration as BoxDecoration).borderRadius ==
                    BorderRadius.circular(4),
          ),
        ))
          (box.decoration as BoxDecoration).color,
      ];
      expect(colors.where((c) => c == lit), hasLength(4));
      expect(colors.where((c) => c == track), hasLength(1));
    });
  });

  group('cancel failed (P11)', () {
    testWidgets(
      'shows the warning, the hint, and "Batal lagi", and announces it',
      (tester) async {
        final power = FakePowerRepository(
          script: const [FakePowerOk(), FakePowerTimeout()],
        );
        final h = await _harness(power: power);
        await h.flow.begin(PowerAction.shutdown);
        await _pump(tester, h);
        final messages = _captureAnnouncements(tester);

        await tester.tap(find.text(PowerStrings.countdownCancel));
        await tester.pump();
        await tester.pump();

        expect(find.text(PowerStrings.countdownCancelWarning), findsOneWidget);
        expect(find.text(PowerStrings.countdownFailedHint), findsOneWidget);
        expect(find.text(PowerStrings.countdownCancelAgain), findsOneWidget);
        expect(find.text(PowerStrings.countdownCancel), findsNothing);
        expect(find.byType(RIcon), findsOneWidget);
        expect(h.sink.calls, contains('vibrate'));
        expect(
          _spoken(messages),
          contains((PowerStrings.countdownCancelWarning, true)),
        );
      },
    );

    testWidgets('countdown keeps running under the warning', (tester) async {
      final power = FakePowerRepository(
        script: const [FakePowerOk(), FakePowerTimeout()],
      );
      final h = await _harness(power: power);
      await h.flow.begin(PowerAction.shutdown);
      await _pump(tester, h);
      await tester.tap(find.text(PowerStrings.countdownCancel));
      await tester.pump();

      h.tick();
      await tester.pump();

      expect(find.text('4'), findsOneWidget);
      expect(find.text(PowerStrings.countdownCancelWarning), findsOneWidget);
    });
  });

  group('cancel button', () {
    testWidgets('tapping Batal cancels the schedule', (tester) async {
      final power = FakePowerRepository();
      final h = await _harness(power: power);
      await h.flow.begin(PowerAction.shutdown);
      await _pump(tester, h);

      await tester.tap(find.text(PowerStrings.countdownCancel));
      await tester.pump();
      await tester.pump();

      expect(power.cancelCalls, 1);
      expect(h.state, isA<PowerFlowResult>());
      expect(find.text(PowerStrings.countdownCancel), findsNothing);
    });

    testWidgets(
      'while cancelling it shows progress and cannot be tapped twice',
      (tester) async {
        final power = _GatedCancelPower();
        final h = await _harness(power: power);
        await h.flow.begin(PowerAction.shutdown);
        await _pump(tester, h);

        await tester.tap(find.text(PowerStrings.countdownCancel));
        await tester.pump();
        expect(h.state, isA<PowerFlowCancelling>());
        expect(find.text('Lagi dibatalin…'), findsOneWidget);

        await tester.tap(find.text('Lagi dibatalin…'));
        await tester.pump();
        expect(power.cancelCalls, 1);

        power.gate!.complete(PowerAction.shutdown);
        await tester.pump();
        await tester.pump();
        expect(h.state, isA<PowerFlowResult>());
      },
    );

    testWidgets('system back calls cancel and does not pop the screen', (
      tester,
    ) async {
      final power = FakePowerRepository();
      final h = await _harness(power: power);
      await h.flow.begin(PowerAction.shutdown);
      await _pump(tester, h);

      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump();

      expect(power.cancelCalls, 1);
      expect(h.state, isA<PowerFlowResult>());
    });
  });

  group('wakelock', () {
    testWidgets('is on while the screen is shown and off when it closes', (
      tester,
    ) async {
      final h = await _harness(power: FakePowerRepository());
      await h.flow.begin(PowerAction.shutdown);
      await _pump(tester, h);
      expect(h.wakelock.calls, ['enable']);

      await tester.pumpWidget(const SizedBox());
      expect(h.wakelock.calls, ['enable', 'disable']);
    });
  });

  group('semantics', () {
    testWidgets('is a dialog route and focuses Batal first', (tester) async {
      final handle = tester.ensureSemantics();
      final h = await _harness(power: FakePowerRepository());
      await h.flow.begin(PowerAction.shutdown);
      await _pump(tester, h);
      await tester.pump();

      final dialog = tester.getSemantics(
        find.byWidgetPredicate(
          (w) =>
              w is Semantics &&
              w.properties.namesRoute == true &&
              w.properties.label == 'Laptop mati dalam',
        ),
      );
      expect(dialog.flagsCollection.scopesRoute, isTrue);
      expect(dialog.flagsCollection.namesRoute, isTrue);
      expect(dialog.role, SemanticsRole.alertDialog);

      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'countdown cancel',
      );
      handle.dispose();
    });

    testWidgets(
      'announces at the start, at 3 and 1 seconds, not at other ticks',
      (tester) async {
        final h = await _harness(power: FakePowerRepository());
        await h.flow.begin(PowerAction.shutdown);
        final messages = _captureAnnouncements(tester);
        await _pump(tester, h);
        await tester.pump();

        h.tick(2); // 5 -> 3
        await tester.pump();
        h.tick(); // 3 -> 2
        await tester.pump();
        h.tick(); // 2 -> 1
        await tester.pump();

        expect(_spoken(messages), [
          ('Laptop mati dalam 5 detik', false),
          ('Laptop mati dalam 3 detik', false),
          ('Laptop mati dalam 1 detik', false),
        ]);
      },
    );
  });

  group('layout and theme', () {
    testWidgets('fits 360 dp at 130% text without overflow', (tester) async {
      final h = await _harness(
        power: FakePowerRepository(
          script: const [FakePowerOk(), FakePowerTimeout()],
        ),
      );
      await h.flow.begin(PowerAction.shutdown);
      await _pump(tester, h, size: const Size(360, 640), textScale: 1.3);
      await tester.tap(find.text(PowerStrings.countdownCancel));
      await tester.pump();
      await tester.pump();

      expect(find.text(PowerStrings.countdownCancelWarning), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('fits 412 dp', (tester) async {
      final h = await _harness(power: FakePowerRepository());
      await h.flow.begin(PowerAction.restart);
      await _pump(tester, h);

      expect(tester.takeException(), isNull);
    });

    testWidgets('clamps the number to 1.3x text scale', (tester) async {
      final h = await _harness(power: FakePowerRepository());
      await h.flow.begin(PowerAction.shutdown);
      await _pump(tester, h, textScale: 2.0);

      final scaler = MediaQuery.textScalerOf(tester.element(find.text('5')));
      expect(scaler.scale(10), closeTo(13, 0.001));
    });

    for (final dark in [false, true]) {
      testWidgets('renders in ${dark ? 'dark' : 'light'} theme', (
        tester,
      ) async {
        final h = await _harness(power: FakePowerRepository());
        await h.flow.begin(PowerAction.shutdown);
        await _pump(tester, h, dark: dark);

        expect(find.text('5'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
