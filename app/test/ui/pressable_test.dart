import 'package:flutter/material.dart';

import 'dart:ui' show Tristate;

import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:remotto/core/haptics/r_haptics.dart';
import 'package:remotto/core/storage/app_preferences.dart';
import 'package:remotto/core/storage/storage_providers.dart';
import 'package:remotto/core/theme/tokens.g.dart';
import 'package:remotto/ui/pressable.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes.dart';
import '../support/test_app.dart';

Future<List<Override>> _overrides(
  RecordingHapticSink sink, {
  bool haptic = true,
}) async {
  SharedPreferences.setMockInitialValues({
    AppPreferences.keyHapticEnabled: haptic,
  });
  final prefs = await SharedPreferences.getInstance();
  return [
    hapticSinkProvider.overrideWithValue(sink),
    sharedPreferencesProvider.overrideWithValue(prefs),
  ];
}

Pressable _button({
  VoidCallback? onPressed,
  PressHaptic haptic = PressHaptic.light,
  String label = 'Putar',
  bool? toggled,
  String? hint,
}) => Pressable.child(
  semanticsLabel: label,
  onPressed: onPressed,
  semanticsHint: hint,
  toggled: toggled,
  haptic: haptic,
  child: const SizedBox(width: 20, height: 20),
);

void main() {
  testWidgets('tap calls onPressed once and fires light haptic on down', (
    tester,
  ) async {
    final sink = RecordingHapticSink();
    var taps = 0;
    await pumpApp(
      tester,
      _button(onPressed: () => taps++),
      overrides: await _overrides(sink),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(Pressable)),
    );
    await tester.pump();
    expect(sink.calls, ['light']);
    expect(taps, 0);

    await gesture.up();
    await tester.pump();
    expect(taps, 1);
    expect(sink.calls, ['light']);
  });

  testWidgets('disabled button: tap does nothing and no haptic', (
    tester,
  ) async {
    final sink = RecordingHapticSink();
    await pumpApp(tester, _button(), overrides: await _overrides(sink));

    await tester.tap(find.byType(Pressable));
    await tester.pump();
    expect(sink.calls, isEmpty);
  });

  testWidgets('dragging out of the area before release cancels the action', (
    tester,
  ) async {
    final sink = RecordingHapticSink();
    var taps = 0;
    await pumpApp(
      tester,
      _button(onPressed: () => taps++),
      overrides: await _overrides(sink),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(Pressable)),
    );
    await gesture.moveBy(const Offset(0, 300));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(taps, 0);
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1.0);
  });

  testWidgets('pressed scales to 0.94 and returns to 1 after release', (
    tester,
  ) async {
    final sink = RecordingHapticSink();
    await pumpApp(
      tester,
      _button(onPressed: () {}),
      overrides: await _overrides(sink),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(Pressable)),
    );
    await tester.pump();
    expect(
      tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale,
      RComponent.keyPressedScale,
    );
    expect(RComponent.keyPressedScale, 0.94);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1.0);
  });

  testWidgets('reduced motion keeps scale at 1 while pressed', (tester) async {
    final sink = RecordingHapticSink();
    await pumpApp(
      tester,
      _button(onPressed: () {}),
      overrides: await _overrides(sink),
      disableAnimations: true,
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(Pressable)),
    );
    await tester.pump();
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1.0);
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('haptic disabled in preferences: no sink call on tap', (
    tester,
  ) async {
    final sink = RecordingHapticSink();
    var taps = 0;
    await pumpApp(
      tester,
      _button(onPressed: () => taps++),
      overrides: await _overrides(sink, haptic: false),
    );

    await tester.tap(find.byType(Pressable));
    await tester.pump();
    expect(taps, 1);
    expect(sink.calls, isEmpty);
  });

  testWidgets('semantics expose label, button, enabled, toggled and hint', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final sink = RecordingHapticSink();
    await pumpApp(
      tester,
      _button(onPressed: () {}, toggled: true, hint: 'Hint uji'),
      overrides: await _overrides(sink),
    );

    final data = tester
        .getSemantics(find.bySemanticsLabel('Putar'))
        .getSemanticsData();
    expect(data.label, 'Putar');
    expect(data.hint, 'Hint uji');
    expect(data.hasAction(SemanticsAction.tap), isTrue);
    expect(data.flagsCollection.isButton, isTrue);
    expect(data.flagsCollection.isEnabled, Tristate.isTrue);
    expect(data.flagsCollection.isToggled, Tristate.isTrue);
    handle.dispose();
  });

  testWidgets('semantics report disabled state when onPressed is null', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final sink = RecordingHapticSink();
    await pumpApp(tester, _button(), overrides: await _overrides(sink));

    final data = tester
        .getSemantics(find.bySemanticsLabel('Putar'))
        .getSemanticsData();
    expect(data.label, 'Putar');
    expect(data.hasAction(SemanticsAction.tap), isFalse);
    expect(data.flagsCollection.isButton, isTrue);
    expect(data.flagsCollection.isEnabled, Tristate.isFalse);
    handle.dispose();
  });

  testWidgets('hit area is at least 48x48 for a 20x20 child', (tester) async {
    final sink = RecordingHapticSink();
    await pumpApp(
      tester,
      _button(onPressed: () {}),
      overrides: await _overrides(sink),
    );

    final size = tester.getSize(find.byType(Pressable));
    expect(size.width, greaterThanOrEqualTo(RSize.touchMin));
    expect(size.height, greaterThanOrEqualTo(RSize.touchMin));
  });

  testWidgets('keyboard Tab then Enter activates onPressed', (tester) async {
    final sink = RecordingHapticSink();
    var taps = 0;
    await pumpApp(
      tester,
      _button(onPressed: () => taps++),
      overrides: await _overrides(sink),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('does not use InkWell', (tester) async {
    final sink = RecordingHapticSink();
    await pumpApp(
      tester,
      _button(onPressed: () {}),
      overrides: await _overrides(sink),
    );

    expect(find.byType(InkWell), findsNothing);
    expect(find.byType(InkResponse), findsNothing);
  });
}
