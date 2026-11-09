import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:remotto/core/haptics/r_haptics.dart';
import 'package:remotto/core/storage/app_preferences.dart';
import 'package:remotto/core/storage/storage_providers.dart';
import 'package:remotto/core/theme/tokens.g.dart';
import 'package:remotto/ui/link_button.dart';
import 'package:remotto/ui/pressable.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes.dart';
import '../support/test_app.dart';

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

void main() {
  testWidgets('touch target is at least 48 dp', (tester) async {
    final sink = RecordingHapticSink();
    await pumpApp(
      tester,
      RLinkButton(
        label: 'Isi manual',
        semanticsLabel: 'Isi manual',
        onPressed: () {},
      ),
      overrides: await _overrides(sink),
    );

    final hit = tester.getSize(find.byType(Pressable));
    expect(hit.height, greaterThanOrEqualTo(RSize.touchMin));
    expect(hit.width, greaterThanOrEqualTo(RSize.touchMin));
  });

  testWidgets('label uses accent.text semibold in light and dark mode', (
    tester,
  ) async {
    final sink = RecordingHapticSink();
    for (final dark in [false, true]) {
      await tester.pumpWidget(const SizedBox());
      await pumpApp(
        tester,
        RLinkButton(
          label: 'Pairing ulang',
          semanticsLabel: 'Pairing ulang',
          onPressed: () {},
        ),
        dark: dark,
        overrides: await _overrides(sink),
      );
      final text = tester.widget<Text>(find.text('Pairing ulang'));
      expect(
        text.style?.color,
        dark ? kDarkTokens.accent.text : kLightTokens.accent.text,
        reason: 'dark=$dark',
      );
      expect(text.style?.fontWeight, FontWeight.w600);
    }
  });

  testWidgets('tap calls onPressed and fires no haptic', (tester) async {
    final sink = RecordingHapticSink();
    var taps = 0;
    await pumpApp(
      tester,
      RLinkButton(
        label: 'Isi manual',
        semanticsLabel: 'Isi manual',
        onPressed: () => taps++,
      ),
      overrides: await _overrides(sink),
    );

    await tester.tap(find.byType(RLinkButton));
    await tester.pump();
    expect(taps, 1);
    expect(sink.calls, isEmpty);
  });

  testWidgets('disabled: disabled text and semantics, no callback', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final sink = RecordingHapticSink();
    await pumpApp(
      tester,
      const RLinkButton(label: 'Isi manual', semanticsLabel: 'Isi manual'),
      overrides: await _overrides(sink),
    );

    final text = tester.widget<Text>(find.text('Isi manual'));
    expect(text.style?.color, kLightTokens.fg.disabled);

    final data = tester
        .getSemantics(find.bySemanticsLabel('Isi manual'))
        .getSemanticsData();
    expect(data.flagsCollection.isEnabled, Tristate.isFalse);
    expect(data.hasAction(SemanticsAction.tap), isFalse);
    handle.dispose();
  });

  testWidgets('semantics: button with the given label', (tester) async {
    final handle = tester.ensureSemantics();
    final sink = RecordingHapticSink();
    await pumpApp(
      tester,
      RLinkButton(
        label: 'Isi manual',
        semanticsLabel: 'Isi token secara manual',
        onPressed: () {},
      ),
      overrides: await _overrides(sink),
    );

    final data = tester
        .getSemantics(find.bySemanticsLabel('Isi token secara manual'))
        .getSemanticsData();
    expect(data.flagsCollection.isButton, isTrue);
    handle.dispose();
  });

  testWidgets('text scale 1.3 does not overflow', (tester) async {
    final sink = RecordingHapticSink();
    await pumpApp(
      tester,
      Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.3)),
          child: RLinkButton(
            label: 'Pairing ulang',
            semanticsLabel: 'Pairing ulang',
            onPressed: () {},
          ),
        ),
      ),
      overrides: await _overrides(sink),
    );

    expect(tester.takeException(), isNull);
  });
}
