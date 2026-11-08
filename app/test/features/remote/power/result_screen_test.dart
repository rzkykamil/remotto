import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotto/core/haptics/r_haptics.dart';
import 'package:remotto/core/storage/app_preferences.dart';
import 'package:remotto/core/storage/storage_providers.dart';
import 'package:remotto/core/strings/power_strings.dart';
import 'package:remotto/core/theme/app_theme.dart';
import 'package:remotto/features/remote/data/power_repository.dart';
import 'package:remotto/features/remote/power/power_flow_state.dart';
import 'package:remotto/features/remote/power/result_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/fakes.dart';

const _laptop = 'Laptop-Kamil';

/// Callbacks recorded by one pumped [ResultScreen].
final class _Calls {
  final RecordingHapticSink sink = RecordingHapticSink();
  int primary = 0;
  int close = 0;
}

Future<_Calls> _pump(
  WidgetTester tester,
  PowerResult result, {
  bool dark = false,
  double textScale = 1,
  Size size = const Size(412, 892),
}) async {
  final calls = _Calls();
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
        hapticSinkProvider.overrideWithValue(calls.sink),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        builder: (context, widget) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: widget!,
        ),
        home: ResultScreen(
          result: result,
          laptopName: _laptop,
          onPrimary: () => calls.primary++,
          onClose: () => calls.close++,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return calls;
}

void main() {
  group('P09 sent', () {
    testWidgets('shutdown shows its title, body, and only "Oke"', (
      tester,
    ) async {
      final calls = await _pump(tester, const PowerSent(PowerAction.shutdown));

      expect(find.text(PowerStrings.doneShutdownTitle), findsOneWidget);
      expect(find.text(PowerStrings.doneShutdownBody(_laptop)), findsOneWidget);
      expect(find.text(PowerStrings.doneAction), findsOneWidget);
      expect(find.text(PowerStrings.scheduleFailedClose), findsNothing);
      expect(find.text(PowerStrings.cancelAction), findsNothing);
      expect(find.text(PowerStrings.countdownCancel), findsNothing);

      await tester.tap(find.text(PowerStrings.doneAction));
      await tester.pump();
      expect(calls.primary, 1);
      expect(calls.close, 0);
    });

    testWidgets('sleep uses the sleep title and body', (tester) async {
      await _pump(tester, const PowerSent(PowerAction.sleep));

      expect(find.text(PowerStrings.doneSleepTitle), findsOneWidget);
      expect(find.text(PowerStrings.doneSleepBody(_laptop)), findsOneWidget);
    });

    testWidgets('restart uses the restart title and fixed body', (
      tester,
    ) async {
      await _pump(tester, const PowerSent(PowerAction.restart));

      expect(find.text(PowerStrings.doneRestartTitle), findsOneWidget);
      expect(find.text(PowerStrings.doneRestartBody), findsOneWidget);
    });

    testWidgets('back runs the primary action', (tester) async {
      final calls = await _pump(tester, const PowerSent(PowerAction.shutdown));

      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(calls.primary, 1);
      expect(calls.close, 0);
    });
  });

  group('P10 not scheduled', () {
    testWidgets('shows retry and close, and each calls its own callback', (
      tester,
    ) async {
      final calls = await _pump(
        tester,
        const PowerNotScheduled(PowerAction.shutdown),
      );

      expect(find.text(PowerStrings.scheduleFailedTitle), findsOneWidget);
      expect(find.text(PowerStrings.scheduleFailedBody), findsOneWidget);
      expect(find.text(PowerStrings.scheduleFailedRetry), findsOneWidget);
      expect(find.text(PowerStrings.scheduleFailedClose), findsOneWidget);
      expect(find.text(PowerStrings.doneAction), findsNothing);

      await tester.tap(find.text(PowerStrings.scheduleFailedRetry));
      await tester.pump();
      expect(calls.primary, 1);
      expect(calls.close, 0);

      await tester.tap(find.text(PowerStrings.scheduleFailedClose));
      await tester.pump();
      expect(calls.primary, 1);
      expect(calls.close, 1);
    });

    testWidgets('back runs close, not retry', (tester) async {
      final calls = await _pump(
        tester,
        const PowerNotScheduled(PowerAction.sleep),
      );

      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(calls.close, 1);
      expect(calls.primary, 0);
    });
  });

  group('P14 too late', () {
    testWidgets('shows only "Oke" with no cancel action (BR-19)', (
      tester,
    ) async {
      final calls = await _pump(
        tester,
        const PowerTooLate(
          action: PowerAction.shutdown,
          elapsed: 6,
          fromThisPhone: true,
        ),
      );

      expect(find.text(PowerStrings.lateTitle), findsOneWidget);
      expect(
        find.text(
          PowerStrings.lateShutdownBody(_laptop, 6, fromThisPhone: true),
        ),
        findsOneWidget,
      );
      expect(find.text(PowerStrings.lateAction), findsOneWidget);
      expect(find.text(PowerStrings.cancelAction), findsNothing);
      expect(find.text(PowerStrings.countdownCancel), findsNothing);
      expect(find.text(PowerStrings.scheduleFailedClose), findsNothing);

      await tester.tap(find.text(PowerStrings.lateAction));
      await tester.pump();
      expect(calls.primary, 1);
    });

    testWidgets('restart and sleep use their own late body', (tester) async {
      await _pump(
        tester,
        const PowerTooLate(
          action: PowerAction.restart,
          elapsed: 3,
          fromThisPhone: false,
        ),
      );
      expect(
        find.text(PowerStrings.lateRestartBody(_laptop, 3)),
        findsOneWidget,
      );
    });

    testWidgets('back runs the primary action', (tester) async {
      final calls = await _pump(
        tester,
        const PowerTooLate(
          action: PowerAction.sleep,
          elapsed: 4,
          fromThisPhone: false,
        ),
      );

      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(calls.primary, 1);
      expect(calls.close, 0);
    });
  });

  group('semantics and focus', () {
    testWidgets('title is a live header and takes initial focus', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, const PowerSent(PowerAction.shutdown));

      final node = tester.getSemantics(
        find.text(PowerStrings.doneShutdownTitle),
      );
      expect(node.flagsCollection.isHeader, isTrue);
      expect(node.flagsCollection.isLiveRegion, isTrue);

      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'result screen title',
      );
      handle.dispose();
    });
  });

  group('layout and themes', () {
    for (final result in <PowerResult>[
      const PowerSent(PowerAction.restart),
      const PowerNotScheduled(PowerAction.shutdown),
      const PowerTooLate(
        action: PowerAction.shutdown,
        elapsed: 6,
        fromThisPhone: true,
      ),
    ]) {
      testWidgets('${result.runtimeType} fits 360 dp at 130% text', (
        tester,
      ) async {
        await _pump(tester, result, size: const Size(360, 640), textScale: 1.3);
        expect(tester.takeException(), isNull);
      });

      testWidgets('${result.runtimeType} renders in dark theme', (
        tester,
      ) async {
        await _pump(tester, result, dark: true);
        expect(tester.takeException(), isNull);
        expect(find.byType(ResultScreen), findsOneWidget);
      });
    }

    testWidgets('P10 at 360 dp, 130% text keeps both actions reachable', (
      tester,
    ) async {
      await _pump(
        tester,
        const PowerNotScheduled(PowerAction.shutdown),
        size: const Size(360, 640),
        textScale: 1.3,
      );
      expect(tester.takeException(), isNull);
      expect(find.text(PowerStrings.scheduleFailedRetry), findsOneWidget);
      expect(find.text(PowerStrings.scheduleFailedClose), findsOneWidget);
    });
  });

  test('cancelled result is rejected', () {
    expect(
      () => ResultScreen(
        result: const PowerCancelled(PowerAction.sleep),
        laptopName: _laptop,
        onPrimary: () {},
      ),
      throwsA(isA<AssertionError>()),
    );
  });
}
