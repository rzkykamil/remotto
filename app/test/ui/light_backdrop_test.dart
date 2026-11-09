import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotto/core/theme/app_theme.dart';
import 'package:remotto/core/theme/glass_mode.dart';
import 'package:remotto/ui/light_backdrop.dart';

import '../support/test_app.dart';

LightBackdropPainter _painterOf(WidgetTester tester) {
  final paint = tester.widget<CustomPaint>(
    find.descendant(
      of: find.byType(LightBackdrop),
      matching: find.byType(CustomPaint),
    ),
  );
  return paint.painter! as LightBackdropPainter;
}

void main() {
  testWidgets('renders in light and dark without exception', (tester) async {
    await pumpApp(tester, const LightBackdrop(child: Text('isi')));
    expect(tester.takeException(), isNull);
    expect(find.text('isi'), findsOneWidget);

    await pumpApp(tester, const LightBackdrop(child: Text('isi')), dark: true);
    expect(tester.takeException(), isNull);
    expect(find.text('isi'), findsOneWidget);
  });

  testWidgets('glows are on by default', (tester) async {
    await pumpApp(tester, const LightBackdrop(child: Text('isi')));
    expect(_painterOf(tester).glows, isTrue);
  });

  testWidgets('glows are off under high contrast', (tester) async {
    await pumpApp(
      tester,
      const LightBackdrop(child: Text('isi')),
      highContrast: true,
    );
    expect(_painterOf(tester).glows, isFalse);
  });

  testWidgets('glows are off when reduceTransparency is set', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(reduceTransparencyProvider.notifier).set(true);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(body: LightBackdrop(child: Text('isi'))),
        ),
      ),
    );
    expect(_painterOf(tester).glows, isFalse);
  });

  testWidgets('shouldRepaint is false for identical values', (tester) async {
    await pumpApp(tester, const LightBackdrop(child: Text('isi')));
    final first = _painterOf(tester);

    await pumpApp(tester, const LightBackdrop(child: Text('isi')));
    final second = _painterOf(tester);

    expect(second.shouldRepaint(first), isFalse);
  });

  testWidgets('shouldRepaint is true when the theme changes', (tester) async {
    await pumpApp(tester, const LightBackdrop(child: Text('isi')));
    final light = _painterOf(tester);

    await pumpApp(tester, const LightBackdrop(child: Text('isi')), dark: true);
    // MaterialApp menganimasikan pergantian tema; tunggu sampai selesai.
    await tester.pumpAndSettle();
    final dark = _painterOf(tester);

    expect(dark.shouldRepaint(light), isTrue);
  });

  testWidgets('shouldRepaint is true when glows flag changes', (tester) async {
    await pumpApp(tester, const LightBackdrop(child: Text('isi')));
    final glowing = _painterOf(tester);

    await pumpApp(
      tester,
      const LightBackdrop(child: Text('isi')),
      highContrast: true,
    );
    final solid = _painterOf(tester);

    expect(solid.shouldRepaint(glowing), isTrue);
  });
}
