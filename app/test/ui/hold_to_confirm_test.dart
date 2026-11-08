import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:remotto/core/haptics/r_haptics.dart';
import 'package:remotto/core/storage/app_preferences.dart';
import 'package:remotto/core/storage/storage_providers.dart';
import 'package:remotto/core/theme/tokens.g.dart';
import 'package:remotto/ui/hold_to_confirm.dart';
import 'package:remotto/ui/r_icons_data.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes.dart';
import '../support/test_app.dart';

const _label = 'Tahan buat matiin';
const _idle = 'Tahan sampai penuh, sekitar 1 detik';
const _holding = 'Terus tahan…';
const _released = 'Kelepasan. Tahan sampai penuh ya.';
const _customAction = 'Matikan sekarang';

Future<List<Override>> _overrides(RecordingHapticSink sink) async {
  SharedPreferences.setMockInitialValues({
    AppPreferences.keyHapticEnabled: true,
  });
  final prefs = await SharedPreferences.getInstance();
  return [
    hapticSinkProvider.overrideWithValue(sink),
    sharedPreferencesProvider.overrideWithValue(prefs),
  ];
}

HoldToConfirm _control({required VoidCallback onCompleted}) => HoldToConfirm(
  key: UniqueKey(),
  label: _label,
  icon: RIcons.power,
  idleHint: _idle,
  holdingHint: _holding,
  releasedHint: _released,
  semanticsLabel: _label,
  semanticsHint: 'tahan',
  customActionLabel: _customAction,
  onCompleted: onCompleted,
);

Finder get _capsule => find.byType(HoldToConfirm);

double _fillFactor(WidgetTester tester) => tester
    .widget<FractionallySizedBox>(find.byType(FractionallySizedBox).first)
    .widthFactor!;

TextStyle _hintStyle(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text)).style!;

void main() {
  testWidgets('holding for the full duration calls onCompleted once', (
    tester,
  ) async {
    final sink = RecordingHapticSink();
    var completed = 0;
    await pumpApp(
      tester,
      _control(onCompleted: () => completed++),
      overrides: await _overrides(sink),
    );

    final gesture = await tester.startGesture(tester.getCenter(_capsule));
    await tester.pump();
    await tester.pump(RMotion.hold);
    expect(_fillFactor(tester), 1, reason: 'fill at ${RMotion.hold}');
    expect(completed, 1);

    await tester.pump(RMotion.hold);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(completed, 1, reason: 'locked after completion');
  });

  testWidgets('releasing at 600 ms does not complete and rewinds to 0', (
    tester,
  ) async {
    final sink = RecordingHapticSink();
    var completed = 0;
    await pumpApp(
      tester,
      _control(onCompleted: () => completed++),
      overrides: await _overrides(sink),
    );

    final gesture = await tester.startGesture(tester.getCenter(_capsule));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(_fillFactor(tester), closeTo(0.5, 0.01));

    await gesture.up();
    await tester.pump();
    await tester.pump(RMotion.holdRewind);
    await tester.pumpAndSettle();

    expect(completed, 0);
    expect(_fillFactor(tester), closeTo(0, 0.001));
    expect(find.text(_released), findsOneWidget);
    expect(_hintStyle(tester, _released).fontWeight, FontWeight.w600);
  });

  testWidgets('plain tap does nothing and fires no haptic', (tester) async {
    final sink = RecordingHapticSink();
    var completed = 0;
    await pumpApp(
      tester,
      _control(onCompleted: () => completed++),
      overrides: await _overrides(sink),
    );

    await tester.tap(_capsule);
    await tester.pumpAndSettle();

    expect(completed, 0);
    expect(sink.calls, isEmpty);
    expect(_fillFactor(tester), closeTo(0, 0.001));
  });

  testWidgets('selection haptic at 50 % and heavy haptic at 100 %', (
    tester,
  ) async {
    final sink = RecordingHapticSink();
    await pumpApp(
      tester,
      _control(onCompleted: () {}),
      overrides: await _overrides(sink),
    );

    final gesture = await tester.startGesture(tester.getCenter(_capsule));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(sink.calls, isEmpty);

    await tester.pump(const Duration(milliseconds: 100));
    expect(sink.calls, ['selection']);

    await tester.pump(RMotion.hold);
    expect(sink.calls, ['selection', 'heavy']);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(sink.calls, ['selection', 'heavy']);
  });

  testWidgets('moving the pointer out of the area resets without completing', (
    tester,
  ) async {
    final sink = RecordingHapticSink();
    var completed = 0;
    await pumpApp(
      tester,
      _control(onCompleted: () => completed++),
      overrides: await _overrides(sink),
    );

    final center = tester.getCenter(_capsule);
    final gesture = await tester.startGesture(center);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.moveBy(const Offset(0, 500));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(completed, 0);
    expect(_fillFactor(tester), closeTo(0, 0.001));
    expect(find.text(_released), findsNothing);
    expect(find.text(_idle), findsOneWidget);
  });

  testWidgets('custom Semantics action calls onCompleted at once', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final sink = RecordingHapticSink();
    var completed = 0;
    await pumpApp(
      tester,
      _control(onCompleted: () => completed++),
      overrides: await _overrides(sink),
    );

    final node = find.semantics.byLabel(_label);
    final data = tester
        .getSemantics(find.bySemanticsLabel(_label))
        .getSemanticsData();
    expect(data.hint, 'tahan');
    expect(data.customSemanticsActionIds, isNotEmpty);

    tester.semantics.performAction(
      node,
      SemanticsAction.customAction,
      args: CustomSemanticsAction.getIdentifier(
        const CustomSemanticsAction(label: _customAction),
      ),
      checkForAction: false,
    );
    await tester.pump();

    expect(completed, 1);
    expect(_fillFactor(tester), closeTo(1, 0.001));
    handle.dispose();
  });

  testWidgets('light and dark themes render without error at 130 % text', (
    tester,
  ) async {
    for (final dark in [false, true]) {
      final sink = RecordingHapticSink();
      await pumpApp(
        tester,
        MediaQuery(
          data: const MediaQueryData(
            size: Size(412, 892),
            textScaler: TextScaler.linear(1.3),
          ),
          child: _control(onCompleted: () {}),
        ),
        dark: dark,
        overrides: await _overrides(sink),
      );

      expect(_capsule, findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}
