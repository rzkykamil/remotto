import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:remotto/core/haptics/r_haptics.dart';
import 'package:remotto/core/storage/app_preferences.dart';
import 'package:remotto/core/storage/storage_providers.dart';
import 'package:remotto/core/theme/tokens.g.dart';
import 'package:remotto/ui/glass_key.dart';
import 'package:remotto/ui/play_key.dart';
import 'package:remotto/ui/r_icon.dart';
import 'package:remotto/ui/r_icons_data.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes.dart';
import '../support/test_app.dart';

const _label = 'Putar';
const _hint = 'Ngirim ke laptop';

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

PlayKey _key({
  bool playing = true,
  bool processing = false,
  bool ringVisible = false,
  VoidCallback? onPressed,
  bool compact = false,
}) => PlayKey(
  playing: playing,
  processing: processing,
  ringVisible: ringVisible,
  onPressed: onPressed,
  compact: compact,
  semanticsLabel: playing ? 'Jeda' : _label,
  processingHint: _hint,
);

bool Function(Widget) _iconIs(RIconData data) =>
    (w) => w is RIcon && identical(w.data, data);

Finder get _ring => find.byKey(const ValueKey('play-key-ring'));

void main() {
  testWidgets('shows pause while playing and play while paused', (
    tester,
  ) async {
    final sink = RecordingHapticSink();
    await pumpApp(
      tester,
      _key(playing: true),
      overrides: await _overrides(sink),
    );
    expect(find.byWidgetPredicate(_iconIs(RIcons.pause)), findsOneWidget);
    expect(find.byWidgetPredicate(_iconIs(RIcons.play)), findsNothing);

    await pumpApp(
      tester,
      _key(playing: false),
      overrides: await _overrides(sink),
    );
    expect(find.byWidgetPredicate(_iconIs(RIcons.play)), findsOneWidget);
    expect(find.byWidgetPredicate(_iconIs(RIcons.pause)), findsNothing);
  });

  testWidgets('ring is drawn only when ringVisible is true', (tester) async {
    final sink = RecordingHapticSink();
    await pumpApp(
      tester,
      _key(processing: true, ringVisible: false),
      overrides: await _overrides(sink),
    );
    expect(_ring, findsNothing);

    await pumpApp(
      tester,
      _key(processing: true, ringVisible: true),
      overrides: await _overrides(sink),
    );
    expect(_ring, findsOneWidget);
  });

  testWidgets('disabled key does not call back and has no haptic', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final sink = RecordingHapticSink();
    await pumpApp(
      tester,
      _key(onPressed: null),
      overrides: await _overrides(sink),
    );

    await tester.tap(find.byType(GlassKey));
    await tester.pump();
    expect(sink.calls, isEmpty);

    final data = tester
        .getSemantics(find.bySemanticsLabel('Jeda'))
        .getSemanticsData();
    expect(data.flagsCollection.isEnabled, Tristate.isFalse);
    handle.dispose();
  });

  testWidgets('enabled key calls onPressed once on tap', (tester) async {
    final sink = RecordingHapticSink();
    var taps = 0;
    await pumpApp(
      tester,
      _key(onPressed: () => taps++),
      overrides: await _overrides(sink),
    );

    await tester.tap(find.byType(PlayKey));
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('sizes are 96 dp on regular and 88 dp when compact', (
    tester,
  ) async {
    final sink = RecordingHapticSink();
    await pumpApp(
      tester,
      UnconstrainedBox(child: _key(onPressed: () {})),
      overrides: await _overrides(sink),
    );
    expect(tester.getSize(find.byType(GlassKey)).width, RSize.play);
    expect(tester.getSize(find.byType(GlassKey)).height, RSize.play);

    await pumpApp(
      tester,
      UnconstrainedBox(child: _key(onPressed: () {}, compact: true)),
      overrides: await _overrides(sink),
    );
    expect(tester.getSize(find.byType(GlassKey)).width, RSize.playCompact);
    expect(tester.getSize(find.byType(GlassKey)).height, RSize.playCompact);
  });

  testWidgets('semantics: label, and hint only while processing', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final sink = RecordingHapticSink();
    await pumpApp(
      tester,
      _key(onPressed: () {}, playing: false),
      overrides: await _overrides(sink),
    );
    var data = tester
        .getSemantics(find.bySemanticsLabel(_label))
        .getSemanticsData();
    expect(data.hint, isEmpty);

    await pumpApp(
      tester,
      _key(
        onPressed: () {},
        playing: false,
        processing: true,
        ringVisible: true,
      ),
      overrides: await _overrides(sink),
    );
    data = tester
        .getSemantics(find.bySemanticsLabel(_label))
        .getSemanticsData();
    expect(data.hint, _hint);
    handle.dispose();
  });

  testWidgets('renders in light and dark mode with ring', (tester) async {
    final sink = RecordingHapticSink();
    for (final dark in [false, true]) {
      await pumpApp(
        tester,
        _key(onPressed: () {}, ringVisible: true, processing: true),
        dark: dark,
        overrides: await _overrides(sink),
      );
      expect(tester.takeException(), isNull, reason: 'dark=$dark');
      expect(_ring, findsOneWidget);
    }
  });

  testWidgets('reduced motion keeps the ring static', (tester) async {
    final sink = RecordingHapticSink();
    await pumpApp(
      tester,
      _key(onPressed: () {}, ringVisible: true, processing: true),
      disableAnimations: true,
      overrides: await _overrides(sink),
    );
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('normal motion spins the ring continuously', (tester) async {
    final sink = RecordingHapticSink();
    await pumpApp(
      tester,
      _key(onPressed: () {}, ringVisible: true, processing: true),
      overrides: await _overrides(sink),
    );
    expect(tester.hasRunningAnimations, isTrue);
  });
}
