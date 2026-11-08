import 'dart:io';
import 'dart:ui' show Tristate;

import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotto/app.dart';
import 'package:remotto/core/connection/connection_providers.dart';
import 'package:remotto/core/haptics/r_haptics.dart';
import 'package:remotto/core/network/network_providers.dart';
import 'package:remotto/core/storage/pairing_data.dart';
import 'package:remotto/core/storage/storage_providers.dart';
import 'package:remotto/core/strings/power_strings.dart';
import 'package:remotto/core/theme/tokens.g.dart';
import 'package:remotto/features/remote/power/power_providers.dart';
import 'package:remotto/features/remote/power/wakelock_controller.dart';
import 'package:remotto/features/remote/widgets/power_row.dart';
import 'package:remotto/ui/hold_to_confirm.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_poll_scheduler.dart';
import '../../support/fake_power_repository.dart';
import '../../support/fake_status_repository.dart';
import '../../support/fakes.dart';
import '../../support/volume_overrides.dart';

// Semantics (C09, C11, C12, C13, C14, P08) and layout gaps of the power flow
// that power_flow_test.dart and the widget tests do not cover yet. The
// helpers are local because power_flow_test.dart keeps its own private.

const _pairing = PairingData(
  host: '192.168.1.10',
  port: 8765,
  token: 'test-token',
  laptopName: 'Laptop-Kamil',
);

const _oneSecond = Duration(seconds: 1);

/// Custom Semantics actions of the hold control in the confirm sheet
/// (`design/components.md` C12).
const _shutdownNowAction = 'Matikan sekarang';
const _restartNowAction = 'Restart sekarang';

/// Records the screen wakelock calls.
final class _FakeWakelock implements WakelockController {
  @override
  Future<void> enable() async {}

  @override
  Future<void> disable() async {}
}

/// Waits for the futures of the fakes, then rebuilds the frames.
Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(() => pumpEventQueue());
  await tester.pumpAndSettle();
}

/// Opens the full app at Remote. [dark] sets the stored theme mode.
Future<FakePollScheduler> _pumpApp(
  WidgetTester tester, {
  required FakePowerRepository power,
  Size size = const Size(412, 892),
  double textScale = 1.0,
  bool dark = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });

  final prefs = (await tester.runAsync(() async {
    SharedPreferences.setMockInitialValues({
      'themeMode': dark ? 'dark' : 'light',
    });
    return SharedPreferences.getInstance();
  }))!;
  final scheduler = FakePollScheduler();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        initialPairingProvider.overrideWithValue(_pairing),
        connectionStorageProvider.overrideWithValue(
          InMemoryConnectionStorage(_pairing),
        ),
        statusRepositoryProvider.overrideWithValue(
          FakeStatusRepository([fakeStatusOk(name: 'Laptop-Kamil')]),
        ),
        pollSchedulerProvider.overrideWithValue(scheduler),
        volumeOverride(),
        powerRepositoryProvider.overrideWithValue(power),
        wakelockControllerProvider.overrideWithValue(_FakeWakelock()),
        hapticSinkProvider.overrideWithValue(RecordingHapticSink()),
      ],
      child: const RemottoApp(),
    ),
  );
  await _settle(tester);
  return scheduler;
}

Future<void> _tap(WidgetTester tester, String text) async {
  await tester.tap(find.text(text));
  await _settle(tester);
}

/// Holds the hold control with [label] until it completes, then releases.
Future<void> _hold(WidgetTester tester, String label) async {
  final center = tester.getCenter(
    find.descendant(of: find.byType(HoldToConfirm), matching: find.text(label)),
  );
  final gesture = await tester.startGesture(center);
  await tester.pump();
  await tester.pump(RMotion.hold);
  await tester.pump(const Duration(milliseconds: 50));
  await gesture.up();
  await _settle(tester);
}

/// Runs the countdown ticker [times] times, as the real 1 s timer would.
Future<void> _tickCountdown(
  WidgetTester tester,
  FakePollScheduler scheduler, {
  int times = 1,
}) async {
  for (var i = 0; i < times; i++) {
    final ticker = scheduler.jobs.lastWhere(
      (job) => job.live && job.periodic && job.delay == _oneSecond,
    );
    ticker.run();
  }
  await _settle(tester);
}

/// Semantics node of the first widget with [text] inside it, or of the
/// Semantics ancestor that carries the flag checked by the caller.
Finder _semanticsAncestorOf(String text, bool Function(Semantics) matches) {
  return find.ancestor(
    of: find.text(text),
    matching: find.byWidgetPredicate((w) => w is Semantics && matches(w)),
  );
}

void main() {
  setUpAll(() async {
    final loader = FontLoader('Geist');
    for (final name in ['Geist-Regular', 'Geist-Medium', 'Geist-SemiBold']) {
      final bytes = File('assets/fonts/$name.ttf').readAsBytesSync();
      loader.addFont(
        Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)),
      );
    }
    await loader.load();
  });

  group('semantics', () {
    testWidgets('tiga tombol daya di Remote punya label dan role tombol', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pumpApp(tester, power: FakePowerRepository());

      for (final label in [
        PowerStrings.semSleep,
        PowerStrings.semRestart,
        PowerStrings.semShutdown,
      ]) {
        final node = tester.getSemantics(find.bySemanticsLabel(label));
        expect(
          node.flagsCollection.isButton,
          isTrue,
          reason: '"$label" harus berperan sebagai tombol',
        );
        expect(node.flagsCollection.isEnabled, Tristate.isTrue, reason: label);
      }
      handle.dispose();
    });

    for (final c in [
      (
        action: PowerStrings.rowShutdown,
        hold: PowerStrings.shutdownHoldLabel,
        custom: _shutdownNowAction,
      ),
      (
        action: PowerStrings.rowRestart,
        hold: PowerStrings.restartHoldLabel,
        custom: _restartNowAction,
      ),
    ]) {
      testWidgets(
        'hold "${c.hold}" punya hint tahan dan custom action "${c.custom}"',
        (tester) async {
          final handle = tester.ensureSemantics();
          final power = FakePowerRepository();
          await _pumpApp(tester, power: power);

          await _tap(tester, c.action);
          await _tap(tester, PowerStrings.stage1Action);

          // The hold control is the only node with the hold hint.
          final holdNode = find.byWidgetPredicate(
            (w) =>
                w is Semantics &&
                w.properties.label == c.hold &&
                w.properties.hint == 'tahan',
          );
          final node = tester.getSemantics(holdNode);
          final data = node.getSemanticsData();
          expect(data.hint, 'tahan');
          expect(data.customSemanticsActionIds, isNotEmpty);

          // The custom action completes the hold at once and sends the command.
          tester.binding.renderViews.first.owner!.semanticsOwner!.performAction(
            node.id,
            SemanticsAction.customAction,
            CustomSemanticsAction.getIdentifier(
              CustomSemanticsAction(label: c.custom),
            ),
          );
          await _settle(tester);

          expect(power.scheduleCalls, 1);
          expect(find.byType(HoldToConfirm), findsNothing);
          expect(tester.takeException(), isNull);
          handle.dispose();
        },
      );
    }

    testWidgets('countdown adalah dialog dengan nama route', (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpApp(tester, power: FakePowerRepository());

      await _tap(tester, PowerStrings.rowSleep);
      await _tap(tester, PowerStrings.sleepAction);

      final dialog = tester.getSemantics(
        _semanticsAncestorOf(
          PowerStrings.countdownTitleSleep,
          (w) => w.properties.namesRoute == true,
        ),
      );
      expect(dialog.flagsCollection.scopesRoute, isTrue);
      expect(dialog.role, SemanticsRole.alertDialog);
      handle.dispose();
    });

    testWidgets('hasil P09 punya judul header', (tester) async {
      final handle = tester.ensureSemantics();
      final scheduler = await _pumpApp(tester, power: FakePowerRepository());

      await _tap(tester, PowerStrings.rowSleep);
      await _tap(tester, PowerStrings.sleepAction);
      await _tickCountdown(tester, scheduler, times: 5);

      expect(find.text(PowerStrings.doneSleepTitle), findsOneWidget);
      final title = tester.getSemantics(
        _semanticsAncestorOf(
          PowerStrings.doneSleepTitle,
          (w) => w.properties.header == true,
        ),
      );
      expect(title.flagsCollection.isHeader, isTrue);
      handle.dispose();
    });

    testWidgets('toast P08 setelah batal adalah liveRegion', (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpApp(tester, power: FakePowerRepository());

      await _tap(tester, PowerStrings.rowShutdown);
      await _tap(tester, PowerStrings.stage1Action);
      await _hold(tester, PowerStrings.shutdownHoldLabel);
      await _tap(tester, PowerStrings.countdownCancel);

      expect(find.text(PowerStrings.toastCancelledShutdown), findsOneWidget);
      final toast = tester.getSemantics(
        _semanticsAncestorOf(
          PowerStrings.toastCancelledShutdown,
          (w) => w.properties.liveRegion == true,
        ),
      );
      expect(toast.flagsCollection.isLiveRegion, isTrue);
      handle.dispose();
    });
  });

  group('layout Remote dengan PowerRow', () {
    // Kombinasi yang belum ada di power_flow_test.dart: 360x640 (layar
    // pendek, <700 dp) dan 412x892 dalam tema gelap, serta 412x892 dengan
    // teks 130%. Teks 1.0 dan 1.3 untuk 360 sudah dicakup di sana.
    final cases = <({Size size, double textScale, bool dark})>[
      (size: const Size(412, 892), textScale: 1.3, dark: false),
      (size: const Size(360, 640), textScale: 1.0, dark: true),
      (size: const Size(360, 640), textScale: 1.3, dark: true),
      (size: const Size(412, 892), textScale: 1.0, dark: true),
      (size: const Size(412, 892), textScale: 1.3, dark: true),
    ];

    for (final c in cases) {
      final name =
          '${c.size.width.toInt()}x${c.size.height.toInt()} '
          'teks ${(c.textScale * 100).round()}% '
          '${c.dark ? 'gelap' : 'terang'}';
      testWidgets('$name: baris daya tampil tanpa overflow', (tester) async {
        await _pumpApp(
          tester,
          power: FakePowerRepository(),
          size: c.size,
          textScale: c.textScale,
          dark: c.dark,
        );

        expect(find.byType(PowerRow), findsOneWidget);
        expect(find.text(PowerStrings.rowSleep), findsOneWidget);
        expect(find.text(PowerStrings.rowRestart), findsOneWidget);
        expect(find.text(PowerStrings.rowShutdown), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
