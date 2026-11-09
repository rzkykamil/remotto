import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:remotto/core/haptics/r_haptics.dart';
import 'package:remotto/core/storage/app_preferences.dart';
import 'package:remotto/core/storage/storage_providers.dart';
import 'package:remotto/core/theme/tokens.g.dart';
import 'package:remotto/ui/glass_key.dart';
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

const _icon = SizedBox(width: 20, height: 20);

GlassKey _key({
  VoidCallback? onPressed,
  GlassKeyVariant variant = GlassKeyVariant.glass,
  GlassKeySize size = GlassKeySize.control,
  String? label,
  Widget? icon = _icon,
  bool? toggled,
  String semantics = 'Tombol uji',
}) => GlassKey(
  semanticsLabel: semantics,
  onPressed: onPressed,
  variant: variant,
  size: size,
  label: label,
  icon: icon,
  toggled: toggled,
);

double _height(WidgetTester tester) =>
    tester.getSize(find.byType(GlassKey)).height;

/// Decoration of the outermost capsule frame inside the first [GlassKey].
BoxDecoration _capsuleDecoration(WidgetTester tester) =>
    tester
            .widget<DecoratedBox>(
              find
                  .descendant(
                    of: find.byType(GlassKey),
                    matching: find.byType(DecoratedBox),
                  )
                  .first,
            )
            .decoration
        as BoxDecoration;

void main() {
  testWidgets('every variant and size reaches at least its token height', (
    tester,
  ) async {
    final sink = RecordingHapticSink();
    final sizes = <GlassKeySize, double>{
      GlassKeySize.touch: RSize.touchMin,
      GlassKeySize.power: RSize.power,
      GlassKeySize.control: RSize.control,
      GlassKeySize.action: RSize.action,
      GlassKeySize.media: RSize.media,
      GlassKeySize.mediaCompact: RSize.mediaCompact,
      GlassKeySize.play: RSize.play,
      GlassKeySize.playCompact: RSize.playCompact,
    };
    for (final variant in GlassKeyVariant.values) {
      for (final entry in sizes.entries) {
        await pumpApp(
          tester,
          UnconstrainedBox(
            child: _key(onPressed: () {}, variant: variant, size: entry.key),
          ),
          overrides: await _overrides(sink),
        );
        expect(
          _height(tester),
          entry.value,
          reason: '${variant.name} ${entry.key.name}',
        );
      }
    }
  });

  testWidgets('only the glass variant uses a BackdropFilter', (tester) async {
    final sink = RecordingHapticSink();
    for (final variant in GlassKeyVariant.values) {
      await pumpApp(
        tester,
        _key(onPressed: () {}, variant: variant),
        overrides: await _overrides(sink),
      );
      expect(
        find.byType(BackdropFilter),
        variant == GlassKeyVariant.glass ? findsOneWidget : findsNothing,
        reason: variant.name,
      );
    }
  });

  testWidgets('tap calls onPressed once and fires a light haptic', (
    tester,
  ) async {
    final sink = RecordingHapticSink();
    var taps = 0;
    await pumpApp(
      tester,
      _key(onPressed: () => taps++, variant: GlassKeyVariant.chip),
      overrides: await _overrides(sink),
    );

    await tester.tap(find.byType(GlassKey));
    await tester.pump();
    expect(taps, 1);
    expect(sink.calls, ['light']);
  });

  testWidgets('disabled key: no callback, no haptic, semantics disabled', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final sink = RecordingHapticSink();
    await pumpApp(
      tester,
      _key(label: 'Matikan', variant: GlassKeyVariant.chip),
      overrides: await _overrides(sink),
    );

    await tester.tap(find.byType(GlassKey));
    await tester.pump();
    expect(sink.calls, isEmpty);

    final data = tester
        .getSemantics(find.bySemanticsLabel('Tombol uji'))
        .getSemanticsData();
    expect(data.flagsCollection.isEnabled, Tristate.isFalse);
    expect(data.hasAction(SemanticsAction.tap), isFalse);

    final text = tester.widget<Text>(find.text('Matikan'));
    expect(text.style?.color, kLightTokens.fg.disabled);
    handle.dispose();
  });

  testWidgets('long label wraps to two lines without overflow', (tester) async {
    final sink = RecordingHapticSink();
    await pumpApp(
      tester,
      SizedBox(
        width: 120,
        child: _key(
          onPressed: () {},
          label:
              'Teks label yang sangat panjang sekali sampai harus dibungkus '
              'ke beberapa baris',
          icon: null,
        ),
      ),
      overrides: await _overrides(sink),
    );

    expect(tester.takeException(), isNull);
    expect(_height(tester), greaterThanOrEqualTo(RSize.control));
    // Text is rendered as RichText, so the maxLines check reads that widget.
    final text = tester.widget<RichText>(
      find.textContaining('Teks label', findRichText: true),
    );
    expect(text.maxLines, 2);
  });

  testWidgets('text scale 1.3 does not overflow', (tester) async {
    final sink = RecordingHapticSink();
    await pumpApp(
      tester,
      Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.3)),
          child: _key(
            onPressed: () {},
            label: 'Pengaturan',
            variant: GlassKeyVariant.chip,
          ),
        ),
      ),
      overrides: await _overrides(sink),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('toggled true is exposed in semantics', (tester) async {
    final handle = tester.ensureSemantics();
    final sink = RecordingHapticSink();
    await pumpApp(
      tester,
      _key(onPressed: () {}, toggled: true, label: 'Bisukan'),
      overrides: await _overrides(sink),
    );

    final data = tester
        .getSemantics(find.bySemanticsLabel('Tombol uji'))
        .getSemanticsData();
    expect(data.flagsCollection.isButton, isTrue);
    expect(data.flagsCollection.isToggled, Tristate.isTrue);
    handle.dispose();
  });

  testWidgets('touch size hit area is at least 48x48', (tester) async {
    final sink = RecordingHapticSink();
    await pumpApp(
      tester,
      UnconstrainedBox(
        child: _key(
          onPressed: () {},
          size: GlassKeySize.touch,
          variant: GlassKeyVariant.ghost,
        ),
      ),
      overrides: await _overrides(sink),
    );

    final hit = tester.getSize(find.byType(Pressable));
    expect(hit.width, greaterThanOrEqualTo(RSize.touchMin));
    expect(hit.height, greaterThanOrEqualTo(RSize.touchMin));
  });

  testWidgets('asserts when neither icon nor label is given', (tester) async {
    expect(
      () => GlassKey(semanticsLabel: 'kosong', onPressed: () {}),
      throwsA(isA<AssertionError>()),
    );
  });

  testWidgets('accent enabled: gradient, accent text and shadow, both modes', (
    tester,
  ) async {
    final sink = RecordingHapticSink();
    for (final dark in [false, true]) {
      await tester.pumpWidget(const SizedBox());
      await pumpApp(
        tester,
        _key(
          onPressed: () {},
          variant: GlassKeyVariant.accent,
          size: GlassKeySize.action,
          label: 'Scan QR',
        ),
        dark: dark,
        overrides: await _overrides(sink),
      );

      final tokens = dark ? kDarkTokens : kLightTokens;
      final decoration = _capsuleDecoration(tester);
      final gradient = decoration.gradient! as LinearGradient;
      expect(gradient.colors, [
        tokens.accent.highlight,
        tokens.accent.defaultColor,
      ], reason: 'dark=$dark');
      expect(decoration.boxShadow, hasLength(1));
      expect(decoration.boxShadow!.single.color, tokens.accent.shadow);

      final text = tester.widget<Text>(find.text('Scan QR'));
      expect(text.style?.color, tokens.accent.on, reason: 'dark=$dark');
    }
  });

  testWidgets('accent disabled: no gradient, no shadow, disabled text', (
    tester,
  ) async {
    final sink = RecordingHapticSink();
    await pumpApp(
      tester,
      _key(
        variant: GlassKeyVariant.accent,
        size: GlassKeySize.action,
        label: 'Sambungkan',
      ),
      overrides: await _overrides(sink),
    );

    final decoration = _capsuleDecoration(tester);
    expect(decoration.gradient, isNull);
    expect(decoration.boxShadow, isNull);
    expect(decoration.color, kLightTokens.glass.chipDisabled);

    final text = tester.widget<Text>(find.text('Sambungkan'));
    expect(text.style?.color, kLightTokens.fg.disabled);
  });

  testWidgets('accent pressed: scales to the key press scale', (tester) async {
    final sink = RecordingHapticSink();
    await pumpApp(
      tester,
      _key(
        onPressed: () {},
        variant: GlassKeyVariant.accent,
        size: GlassKeySize.action,
        label: 'Scan QR',
      ),
      overrides: await _overrides(sink),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(GlassKey)),
    );
    await tester.pump(RMotion.pressDown);
    expect(
      tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale,
      RComponent.keyPressedScale,
    );
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('does not use InkWell', (tester) async {
    final sink = RecordingHapticSink();
    await pumpApp(
      tester,
      _key(onPressed: () {}, variant: GlassKeyVariant.strong),
      overrides: await _overrides(sink),
    );

    expect(find.byType(InkWell), findsNothing);
    expect(find.byType(InkResponse), findsNothing);
  });
}
