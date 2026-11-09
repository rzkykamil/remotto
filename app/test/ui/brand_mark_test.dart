import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotto/core/strings/strings.dart';
import 'package:remotto/ui/brand_mark.dart';
import 'package:remotto/ui/glass_panel.dart';
import 'package:remotto/ui/r_icon.dart';
import 'package:remotto/ui/r_icons_data.dart';

import '../support/test_app.dart';

void main() {
  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';

    testWidgets('BrandMark shows the wordmark in $mode theme', (tester) async {
      await pumpApp(tester, const BrandMark(), dark: dark);

      expect(find.text(AppStrings.appName), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('IconDisc.glassLarge is 96 dp with a 40 dp icon in $mode', (
      tester,
    ) async {
      await pumpApp(
        tester,
        const IconDisc.glassLarge(icon: RIcons.camera),
        dark: dark,
      );

      expect(tester.getSize(find.byType(IconDisc)), const Size(96, 96));
      expect(find.byType(GlassPanel), findsOneWidget);
      expect(tester.widget<RIcon>(find.byType(RIcon)).size, 40);
      expect(tester.takeException(), isNull);
    });

    testWidgets('IconDisc.chipLarge is 80 dp, no blur, in $mode', (
      tester,
    ) async {
      await pumpApp(
        tester,
        const IconDisc.chipLarge(icon: RIcons.cameraOff),
        dark: dark,
      );

      expect(tester.getSize(find.byType(IconDisc)), const Size(80, 80));
      expect(find.byType(GlassPanel), findsNothing);
      expect(find.byType(BackdropFilter), findsNothing);
      expect(tester.widget<RIcon>(find.byType(RIcon)).size, 36);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('BrandMark gradient disc is 44 dp', (tester) async {
    await pumpApp(tester, const BrandMark());

    final disc = tester.widget<DecoratedBox>(
      find
          .descendant(
            of: find.byType(BrandMark),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    final decoration = disc.decoration as BoxDecoration;
    expect(decoration.shape, BoxShape.circle);
    expect(decoration.gradient, isNotNull);
    expect(
      tester.getSize(
        find
            .descendant(
              of: find.byType(BrandMark),
              matching: find.byType(SizedBox),
            )
            .first,
      ),
      const Size(44, 44),
    );
  });

  testWidgets('IconDisc icons are decorative and excluded from Semantics', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpApp(
      tester,
      const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconDisc.glassLarge(icon: RIcons.camera),
          IconDisc.chipLarge(icon: RIcons.cameraOff),
        ],
      ),
    );

    expect(
      find.descendant(
        of: find.byType(IconDisc),
        matching: find.byType(ExcludeSemantics),
      ),
      findsNWidgets(2),
    );
    handle.dispose();
  });

  testWidgets('BrandMark wordmark is announced as text', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpApp(tester, const BrandMark());

    expect(
      tester.getSemantics(find.text(AppStrings.appName)),
      matchesSemantics(label: AppStrings.appName),
    );
    handle.dispose();
  });
}
