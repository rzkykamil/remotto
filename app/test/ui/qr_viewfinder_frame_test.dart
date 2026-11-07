import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotto/core/theme/theme_extensions.dart';
import 'package:remotto/ui/qr_viewfinder_frame.dart';

import '../support/test_app.dart';

void main() {
  group('QrViewfinderFrame', () {
    testWidgets('default size is 248 dp (C16)', (tester) async {
      await pumpApp(
        tester,
        Builder(
          builder: (context) =>
              QrViewfinderFrame(color: Theme.of(context).colorScheme.onSurface),
        ),
      );

      expect(
        tester.getSize(find.byType(QrViewfinderFrame)),
        const Size(248, 248),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('paints in light and dark themes without error', (
      tester,
    ) async {
      for (final dark in [false, true]) {
        await pumpApp(
          tester,
          Builder(
            builder: (context) => QrViewfinderFrame(
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          dark: dark,
        );
        expect(tester.takeException(), isNull, reason: 'dark=$dark');
      }
    });

    testWidgets('accent color for invalid QR paints without error', (
      tester,
    ) async {
      await pumpApp(
        tester,
        Builder(
          builder: (context) =>
              QrViewfinderFrame(color: context.accent.text, size: 200),
        ),
        dark: true,
      );

      expect(
        tester.getSize(find.byType(QrViewfinderFrame)),
        const Size(200, 200),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('is decorative and excluded from Semantics', (tester) async {
      await pumpApp(tester, const QrViewfinderFrame(color: Colors.white));

      final frame = find.byType(ExcludeSemantics);
      expect(
        find.descendant(of: find.byType(QrViewfinderFrame), matching: frame),
        findsOneWidget,
      );
    });
  });
}
