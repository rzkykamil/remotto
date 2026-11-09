import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotto/core/haptics/r_haptics.dart';
import 'package:remotto/core/storage/app_preferences.dart';
import 'package:remotto/core/storage/storage_providers.dart';
import 'package:remotto/core/strings/power_strings.dart';
import 'package:remotto/core/theme/app_theme.dart';
import 'package:remotto/core/theme/tokens.g.dart';
import 'package:remotto/features/remote/data/power_repository.dart';
import 'package:remotto/features/remote/power/confirm_sheet_route.dart';
import 'package:remotto/features/remote/widgets/confirm_sheet.dart';
import 'package:remotto/ui/hold_to_confirm.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/fakes.dart';

const _trigger = 'buka';
const _laptop = 'Laptop-Kamil';

/// Result of one opened sheet and the haptics it fired.
final class _Harness {
  final RecordingHapticSink sink = RecordingHapticSink();
  bool closed = false;
  PowerAction? result;
}

/// Pumps a screen with a trigger that opens [showConfirmSheet].
Future<_Harness> _open(
  WidgetTester tester, {
  required PowerAction action,
  bool startAtStage2 = false,
  bool dark = false,
  bool disableAnimations = false,
  double textScale = 1,
  Size size = const Size(360, 780),
}) async {
  final harness = _Harness();
  SharedPreferences.setMockInitialValues({
    AppPreferences.keyHapticEnabled: true,
  });
  final prefs = await SharedPreferences.getInstance();

  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        hapticSinkProvider.overrideWithValue(harness.sink),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        builder: (context, widget) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: disableAnimations,
            textScaler: TextScaler.linear(textScale),
          ),
          child: widget!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: GestureDetector(
                onTap: () async {
                  harness.result = await showConfirmSheet(
                    context,
                    action: action,
                    laptopName: _laptop,
                    startAtStage2: startAtStage2,
                  );
                  harness.closed = true;
                },
                child: const Text(_trigger),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text(_trigger));
  await tester.pumpAndSettle();
  return harness;
}

/// Holds the hold control until it completes, then releases.
Future<void> _holdToCompletion(WidgetTester tester, String label) async {
  final center = tester.getCenter(
    find.descendant(of: find.byType(HoldToConfirm), matching: find.text(label)),
  );
  final gesture = await tester.startGesture(center);
  await tester.pump();
  await tester.pump(RMotion.hold);
  await tester.pump(const Duration(milliseconds: 50));
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  group('sleep', () {
    testWidgets('has one stage and Sleep-in closes with the sleep result', (
      tester,
    ) async {
      final h = await _open(tester, action: PowerAction.sleep);

      expect(find.text(PowerStrings.sleepTitle), findsOneWidget);
      expect(find.text(PowerStrings.stage1Action), findsNothing);
      expect(find.byType(HoldToConfirm), findsNothing);

      await tester.tap(find.text(PowerStrings.sleepAction));
      await tester.pumpAndSettle();

      expect(h.closed, isTrue);
      expect(h.result, PowerAction.sleep);
    });

    testWidgets('fires one light haptic when the sheet opens', (tester) async {
      final h = await _open(tester, action: PowerAction.sleep);

      expect(h.sink.calls, contains('light'));
    });
  });

  group('shutdown', () {
    testWidgets('Lanjut replaces itself with the hold control', (tester) async {
      await _open(tester, action: PowerAction.shutdown);

      expect(find.text(PowerStrings.shutdownStage1Title), findsOneWidget);
      expect(find.text(PowerStrings.stage1Kicker), findsOneWidget);
      expect(find.byType(HoldToConfirm), findsNothing);

      await tester.tap(find.text(PowerStrings.stage1Action));
      await tester.pumpAndSettle();

      expect(find.byType(HoldToConfirm), findsOneWidget);
      expect(find.text(PowerStrings.stage1Action), findsNothing);
      expect(find.text(PowerStrings.stage2Kicker), findsOneWidget);
      expect(find.text(PowerStrings.shutdownHoldBody), findsOneWidget);
    });

    testWidgets('a full hold closes with the shutdown result', (tester) async {
      final h = await _open(
        tester,
        action: PowerAction.shutdown,
        startAtStage2: true,
      );

      await _holdToCompletion(tester, PowerStrings.shutdownHoldLabel);

      expect(h.closed, isTrue);
      expect(h.result, PowerAction.shutdown);
    });

    testWidgets('startAtStage2 opens directly on the hold control', (
      tester,
    ) async {
      await _open(tester, action: PowerAction.shutdown, startAtStage2: true);

      expect(find.byType(HoldToConfirm), findsOneWidget);
      expect(find.text(PowerStrings.stage1Action), findsNothing);
    });
  });

  group('restart', () {
    testWidgets('uses restart copy and closes with the restart result', (
      tester,
    ) async {
      final h = await _open(tester, action: PowerAction.restart);

      expect(find.text(PowerStrings.restartStage1Title), findsOneWidget);
      expect(find.text(PowerStrings.stage1Body(_laptop)), findsOneWidget);

      await tester.tap(find.text(PowerStrings.stage1Action));
      await tester.pumpAndSettle();

      expect(find.text(PowerStrings.restartHoldBody), findsOneWidget);
      expect(find.text(PowerStrings.shutdownHoldBody), findsNothing);

      await _holdToCompletion(tester, PowerStrings.restartHoldLabel);

      expect(h.closed, isTrue);
      expect(h.result, PowerAction.restart);
    });
  });

  group('cancelling gives null', () {
    testWidgets('Nggak jadi at stage 1', (tester) async {
      final h = await _open(tester, action: PowerAction.shutdown);

      await tester.tap(find.text(PowerStrings.cancelAction));
      await tester.pumpAndSettle();

      expect(h.closed, isTrue);
      expect(h.result, isNull);
    });

    testWidgets('Nggak jadi at stage 2', (tester) async {
      final h = await _open(
        tester,
        action: PowerAction.restart,
        startAtStage2: true,
      );

      await tester.tap(find.text(PowerStrings.cancelAction));
      await tester.pumpAndSettle();

      expect(h.closed, isTrue);
      expect(h.result, isNull);
    });

    testWidgets('tapping the scrim', (tester) async {
      final h = await _open(tester, action: PowerAction.sleep);

      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(h.closed, isTrue);
      expect(h.result, isNull);
    });

    testWidgets('tapping the sheet body does not dismiss it', (tester) async {
      final h = await _open(tester, action: PowerAction.sleep);

      await tester.tap(find.text(PowerStrings.sleepTitle));
      await tester.pumpAndSettle();

      expect(h.closed, isFalse);
    });

    testWidgets('the system back button', (tester) async {
      final h = await _open(tester, action: PowerAction.sleep);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(h.closed, isTrue);
      expect(h.result, isNull);
    });

    testWidgets('a downward fling on the handle', (tester) async {
      final h = await _open(tester, action: PowerAction.sleep);

      final sheetTop = tester.getTopLeft(find.byType(ConfirmSheet)).dy;
      final sheetCenterX = tester.getCenter(find.byType(ConfirmSheet)).dx;
      await tester.flingFrom(
        Offset(sheetCenterX, sheetTop + RSize.touchMin / 2),
        const Offset(0, 300),
        1000,
      );
      await tester.pumpAndSettle();

      expect(h.closed, isTrue);
      expect(h.result, isNull);
    });
  });

  group('layout and themes', () {
    testWidgets('360 dp with 130% text has no overflow at stage 2', (
      tester,
    ) async {
      await _open(
        tester,
        action: PowerAction.shutdown,
        startAtStage2: true,
        textScale: 1.3,
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(HoldToConfirm), findsOneWidget);
    });

    testWidgets('short screen with 130% text scrolls instead of overflowing', (
      tester,
    ) async {
      await _open(
        tester,
        action: PowerAction.restart,
        textScale: 1.3,
        size: const Size(360, 560),
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(SingleChildScrollView), findsOneWidget);
    });

    for (final action in PowerAction.values) {
      testWidgets('dark theme renders ${action.wire}', (tester) async {
        await _open(tester, action: action, dark: true);

        expect(tester.takeException(), isNull);
        expect(find.text(PowerStrings.cancelAction), findsOneWidget);
      });
    }

    testWidgets('reduced motion keeps the stage change working', (
      tester,
    ) async {
      await _open(
        tester,
        action: PowerAction.shutdown,
        disableAnimations: true,
      );

      await tester.tap(find.text(PowerStrings.stage1Action));
      await tester.pumpAndSettle();

      expect(find.byType(HoldToConfirm), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
