import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:remotto/core/haptics/r_haptics.dart';
import 'package:remotto/core/storage/app_preferences.dart';
import 'package:remotto/core/storage/storage_providers.dart';
import 'package:remotto/ui/glass_key.dart';
import 'package:remotto/ui/pairing_scaffold.dart';
import 'package:remotto/ui/r_icon.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes.dart';
import '../support/test_app.dart';

const _title = 'Pinjem kamera bentar';
const _primary = 'Izinkan kamera';
const _secondary = 'Isi manual aja';
const _back = 'Kembali';
const _tips = ['HP dan laptop harus di WiFi yang sama.', 'Agent jalan.'];

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

PairingScaffold _scaffold({
  VoidCallback? onPrimary,
  VoidCallback? onBack,
  VoidCallback? onSecondary,
  List<String> tips = const [],
}) => PairingScaffold(
  title: _title,
  primaryLabel: _primary,
  onPrimary: onPrimary,
  onBack: onBack,
  backLabel: onBack == null ? null : _back,
  kicker: 'PERMISI',
  body: 'Cuma buat scan QR dari layar laptop.',
  tips: tips,
  secondaryLabel: _secondary,
  onSecondary: onSecondary,
  leading: const SizedBox(width: 80, height: 80),
);

void main() {
  testWidgets('shows title, body, primary and secondary actions', (
    tester,
  ) async {
    final sink = RecordingHapticSink();
    await pumpApp(
      tester,
      _scaffold(onPrimary: () {}, onSecondary: () {}),
      overrides: await _overrides(sink),
    );

    expect(find.text(_title), findsOneWidget);
    expect(find.text('PERMISI'), findsOneWidget);
    expect(find.text('Cuma buat scan QR dari layar laptop.'), findsOneWidget);
    expect(find.text(_primary), findsOneWidget);
    expect(find.text(_secondary), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('title is a semantics header', (tester) async {
    final sink = RecordingHapticSink();
    await pumpApp(
      tester,
      _scaffold(onPrimary: () {}),
      overrides: await _overrides(sink),
    );

    final node = tester.getSemantics(find.text(_title));
    expect(node.flagsCollection.isHeader, isTrue);
  });

  testWidgets('primary action fires onPrimary and is disabled when null', (
    tester,
  ) async {
    final sink = RecordingHapticSink();
    var taps = 0;
    await pumpApp(
      tester,
      _scaffold(onPrimary: () => taps++),
      overrides: await _overrides(sink),
    );
    await tester.tap(find.text(_primary));
    await tester.pump();
    expect(taps, 1);

    await pumpApp(tester, _scaffold(), overrides: await _overrides(sink));
    final node = tester.getSemantics(find.bySemanticsLabel(_primary));
    expect(node.flagsCollection.isEnabled, Tristate.isFalse);
  });

  testWidgets('back button appears only when onBack is set', (tester) async {
    final sink = RecordingHapticSink();
    await pumpApp(
      tester,
      _scaffold(onPrimary: () {}),
      overrides: await _overrides(sink),
    );
    expect(find.byType(RIcon), findsNothing);

    var backs = 0;
    await pumpApp(
      tester,
      _scaffold(onPrimary: () {}, onBack: () => backs++),
      overrides: await _overrides(sink),
    );
    expect(find.byType(RIcon), findsWidgets);
    expect(find.bySemanticsLabel(_back), findsOneWidget);
    await tester.tap(find.bySemanticsLabel(_back));
    await tester.pump();
    expect(backs, 1);
  });

  testWidgets('tips are numbered 1..n in a glass group', (tester) async {
    final sink = RecordingHapticSink();
    await pumpApp(
      tester,
      _scaffold(onPrimary: () {}, tips: _tips),
      overrides: await _overrides(sink),
    );

    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text(_tips[0]), findsOneWidget);
    expect(find.text(_tips[1]), findsOneWidget);
  });

  testWidgets('renders in dark mode without exceptions', (tester) async {
    final sink = RecordingHapticSink();
    await pumpApp(
      tester,
      _scaffold(onPrimary: () {}, onBack: () {}, tips: _tips),
      dark: true,
      overrides: await _overrides(sink),
    );
    expect(tester.takeException(), isNull);
    expect(find.text(_title), findsOneWidget);
  });

  testWidgets('narrow 360 dp with text scale 1.3 has no overflow', (
    tester,
  ) async {
    final sink = RecordingHapticSink();
    await pumpApp(
      tester,
      Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.3)),
          child: _scaffold(onPrimary: () {}, onBack: () {}, tips: _tips),
        ),
      ),
      size: const Size(360, 640),
      overrides: await _overrides(sink),
    );

    expect(tester.takeException(), isNull);
    expect(find.text(_primary), findsOneWidget);
  });

  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';
    testWidgets('title and actions render in $mode theme', (tester) async {
      final sink = RecordingHapticSink();
      await pumpApp(
        tester,
        _scaffold(onPrimary: () {}, onBack: () {}, onSecondary: () {}),
        dark: dark,
        overrides: await _overrides(sink),
      );

      expect(find.text(_title), findsOneWidget);
      expect(find.text(_primary), findsOneWidget);
      expect(find.text(_secondary), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('back key and primary action reach 48 dp touch target', (
    tester,
  ) async {
    final sink = RecordingHapticSink();
    await pumpApp(
      tester,
      _scaffold(onPrimary: () {}, onBack: () {}, onSecondary: () {}),
      overrides: await _overrides(sink),
    );

    // Tombol back adalah GlassKey pertama (sebelum aksi utama).
    final back = tester.getSize(find.byType(GlassKey).first);
    expect(back.height, greaterThanOrEqualTo(48));
    expect(back.width, greaterThanOrEqualTo(48));

    final primary = tester.getSize(find.widgetWithText(GlassKey, _primary));
    expect(primary.height, greaterThanOrEqualTo(48));
  });

  testWidgets('primary action has a button label in semantics', (tester) async {
    final handle = tester.ensureSemantics();
    final sink = RecordingHapticSink();
    await pumpApp(
      tester,
      _scaffold(onPrimary: () {}),
      overrides: await _overrides(sink),
    );

    final data = tester
        .getSemantics(find.bySemanticsLabel(_primary))
        .getSemanticsData();
    expect(data.flagsCollection.isButton, isTrue);
    handle.dispose();
  });
}
