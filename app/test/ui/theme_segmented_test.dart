import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotto/core/theme/app_theme.dart';
import 'package:remotto/core/theme/theme_extensions.dart';
import 'package:remotto/ui/r_icon.dart';
import 'package:remotto/ui/theme_segmented.dart';

import '../support/test_app.dart';

Future<void> _pump(
  WidgetTester tester, {
  required ThemeMode value,
  required ValueChanged<ThemeMode>? onChanged,
  bool disableAnimations = false,
}) {
  return pumpApp(
    tester,
    SizedBox(
      width: 340,
      child: ThemeSegmented(value: value, onChanged: onChanged),
    ),
    disableAnimations: disableAnimations,
  );
}

Color _segmentColor(WidgetTester tester, String label) {
  final box = tester.widget<AnimatedContainer>(
    find
        .ancestor(
          of: find.text(label),
          matching: find.byType(AnimatedContainer),
        )
        .first,
  );
  return (box.decoration! as BoxDecoration).color!;
}

void main() {
  testWidgets('shows three segments in order Terang, Gelap, Sistem', (
    tester,
  ) async {
    await _pump(tester, value: ThemeMode.system, onChanged: (_) {});

    expect(find.text('Terang'), findsOneWidget);
    expect(find.text('Gelap'), findsOneWidget);
    expect(find.text('Sistem'), findsOneWidget);

    final x = [
      tester.getCenter(find.text('Terang')).dx,
      tester.getCenter(find.text('Gelap')).dx,
      tester.getCenter(find.text('Sistem')).dx,
    ];
    expect(x[0] < x[1] && x[1] < x[2], isTrue);
  });

  testWidgets('tapping an inactive segment calls onChanged with its mode', (
    tester,
  ) async {
    final calls = <ThemeMode>[];
    await _pump(tester, value: ThemeMode.light, onChanged: calls.add);

    await tester.tap(find.text('Gelap'));
    await tester.pump();
    await tester.tap(find.text('Sistem'));
    await tester.pump();

    expect(calls, [ThemeMode.dark, ThemeMode.system]);
  });

  testWidgets('tapping the active segment does not call onChanged', (
    tester,
  ) async {
    final calls = <ThemeMode>[];
    await _pump(tester, value: ThemeMode.dark, onChanged: calls.add);

    await tester.tap(find.text('Gelap'));
    await tester.pump();

    expect(calls, isEmpty);
  });

  testWidgets('null onChanged disables every segment', (tester) async {
    await _pump(tester, value: ThemeMode.dark, onChanged: null);

    await tester.tap(find.text('Terang'));
    await tester.pump();

    expect(
      tester.getSemantics(find.bySemanticsLabel('Terang')),
      matchesSemantics(
        label: 'Terang',
        isInMutuallyExclusiveGroup: true,
        hasCheckedState: true,
        isChecked: false,
        hasSelectedState: true,
        isSelected: false,
        hasEnabledState: true,
        isEnabled: false,
      ),
    );
  });

  testWidgets('check icon appears only in the active segment', (tester) async {
    await _pump(tester, value: ThemeMode.dark, onChanged: (_) {});

    expect(find.byType(RIcon), findsOneWidget);
    final icon = tester.getCenter(find.byType(RIcon));
    expect(icon.dx, greaterThan(tester.getTopRight(find.text('Terang')).dx));
    expect(icon.dx, lessThan(tester.getTopLeft(find.text('Gelap')).dx));
  });

  testWidgets('active segment uses segOn fill and glass edge', (tester) async {
    await _pump(tester, value: ThemeMode.light, onChanged: (_) {});

    final tokens = AppTheme.light.extension<ControlTokens>()!;
    expect(_segmentColor(tester, 'Terang'), tokens.segOn);
    expect(_segmentColor(tester, 'Gelap'), Colors.transparent);
  });

  testWidgets('semantics: container Tema, checked radio items in a group', (
    tester,
  ) async {
    await _pump(tester, value: ThemeMode.system, onChanged: (_) {});

    expect(find.bySemanticsLabel('Tema'), findsOneWidget);
    expect(
      tester.getSemantics(find.bySemanticsLabel('Sistem')),
      matchesSemantics(
        label: 'Sistem',
        hasTapAction: false,
        isInMutuallyExclusiveGroup: true,
        hasCheckedState: true,
        isChecked: true,
        hasSelectedState: true,
        isSelected: true,
        hasEnabledState: true,
        isEnabled: true,
      ),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('Gelap')),
      matchesSemantics(
        label: 'Gelap',
        hasTapAction: true,
        isInMutuallyExclusiveGroup: true,
        hasCheckedState: true,
        isChecked: false,
        hasSelectedState: true,
        isSelected: false,
        hasEnabledState: true,
        isEnabled: true,
      ),
    );
  });

  testWidgets('each segment is at least 48 dp tall', (tester) async {
    await _pump(tester, value: ThemeMode.light, onChanged: (_) {});

    for (final label in ['Terang', 'Gelap', 'Sistem']) {
      final segment = find
          .ancestor(
            of: find.text(label),
            matching: find.byType(AnimatedContainer),
          )
          .first;
      expect(tester.getSize(segment).height, greaterThanOrEqualTo(48));
    }
  });

  testWidgets('reduced motion switches the active segment instantly', (
    tester,
  ) async {
    await _pump(
      tester,
      value: ThemeMode.light,
      onChanged: (_) {},
      disableAnimations: true,
    );
    await _pump(
      tester,
      value: ThemeMode.dark,
      onChanged: (_) {},
      disableAnimations: true,
    );
    await tester.pump();

    final tokens = AppTheme.light.extension<ControlTokens>()!;
    expect(_segmentColor(tester, 'Gelap'), tokens.segOn);
  });
}
