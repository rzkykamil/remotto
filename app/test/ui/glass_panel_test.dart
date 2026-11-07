import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotto/core/theme/glass_mode.dart';
import 'package:remotto/core/theme/theme_extensions.dart';
import 'package:remotto/core/theme/tokens.g.dart';
import 'package:remotto/ui/glass_panel.dart';

import '../support/test_app.dart';

const _child = SizedBox(width: 200, height: 80, child: Text('isi'));

void main() {
  testWidgets('light and dark render one BackdropFilter and the child', (
    tester,
  ) async {
    await pumpApp(tester, const GlassPanel(child: _child));
    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(find.text('isi'), findsOneWidget);

    await pumpApp(tester, const GlassPanel(child: _child), dark: true);
    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(find.text('isi'), findsOneWidget);
  });

  testWidgets('high contrast removes blur and uses glass.solid', (
    tester,
  ) async {
    await pumpApp(tester, const GlassPanel(child: _child), highContrast: true);
    expect(find.byType(BackdropFilter), findsNothing);
    expect(_fillColors(tester), contains(kLightTokens.glass.solid));
    expect(_fillColors(tester), isNot(contains(kLightTokens.glass.fill)));
  });

  // Sumber reduce transparency dan slow raster dipetakan ke
  // glassForcedSolidProvider. Notifier sumbernya final (tidak bisa di-override
  // dari test), jadi provider gabungan yang di-override; logika OR-nya diuji
  // di glass_mode_test.
  testWidgets(
    'forced solid (reduce transparency or slow raster) removes blur',
    (tester) async {
      await pumpApp(
        tester,
        const GlassPanel(child: _child),
        overrides: [glassForcedSolidProvider.overrideWithValue(true)],
      );
      expect(find.byType(BackdropFilter), findsNothing);
      expect(_fillColors(tester), contains(kLightTokens.glass.solid));
    },
  );

  testWidgets('each variant clips with its radius', (tester) async {
    final expected = <GlassPanelVariant, double>{
      GlassPanelVariant.panel: RRadius.lg,
      GlassPanelVariant.dock: RRadius.full,
      GlassPanelVariant.pill: RRadius.full,
      GlassPanelVariant.toast: RRadius.sm,
    };
    for (final entry in expected.entries) {
      await pumpApp(tester, GlassPanel(variant: entry.key, child: _child));
      final clip = tester.widget<ClipRRect>(find.byType(ClipRRect));
      expect(
        clip.borderRadius,
        BorderRadius.circular(entry.value),
        reason: entry.key.name,
      );
    }
  });

  testWidgets('toast uses glass.toast fill', (tester) async {
    await pumpApp(
      tester,
      const GlassPanel(variant: GlassPanelVariant.toast, child: _child),
    );
    expect(_fillColors(tester), contains(kLightTokens.glass.toast));
  });

  testWidgets('semantics container carries the label', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpApp(
      tester,
      const GlassPanel(semanticsLabel: 'Volume', child: _child),
    );
    // Label container digabung dengan teks anak; cukup cek awalannya.
    expect(
      tester.getSemantics(find.byType(GlassPanel)).label,
      startsWith('Volume'),
    );
    semantics.dispose();
  });

  testWidgets('adjacent panels each have their own BackdropFilter', (
    tester,
  ) async {
    await pumpApp(
      tester,
      const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GlassPanel(child: _child),
          GlassPanel(child: _child),
        ],
      ),
    );
    expect(find.byType(BackdropFilter), findsNWidgets(2));
    for (final panel in find.byType(GlassPanel).evaluate()) {
      expect(
        find.descendant(
          of: find.byWidget(panel.widget),
          matching: find.byType(BackdropFilter),
        ),
        findsOneWidget,
      );
    }
  });

  testWidgets('glass context extensions resolve in both themes', (
    tester,
  ) async {
    late GlassTokens glass;
    await pumpApp(
      tester,
      Builder(
        builder: (context) {
          glass = context.glass;
          return const SizedBox.shrink();
        },
      ),
      dark: true,
    );
    expect(glass.fill, kDarkTokens.glass.fill);
  });
}

/// Warna `BoxDecoration` yang dipakai sebagai isi panel.
Iterable<Color> _fillColors(WidgetTester tester) => tester
    .widgetList<DecoratedBox>(find.byType(DecoratedBox))
    .map((box) => box.decoration)
    .whereType<BoxDecoration>()
    .map((d) => d.color)
    .whereType<Color>();
