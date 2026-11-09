import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotto/core/theme/glass_mode.dart';
import 'package:remotto/core/theme/tokens.g.dart';
import 'package:remotto/ui/glass_panel.dart';
import 'package:remotto/ui/settings_group.dart';

import '../support/test_app.dart';

SettingsGroup _group({VoidCallback? onAction}) => SettingsGroup(
  caption: 'Perangkat',
  children: [
    const SettingsRow(
      variant: SettingsRowVariant.info,
      label: 'Versi',
      value: '1.0.0 (1)',
    ),
    SettingsRow(
      variant: SettingsRowVariant.action,
      label: 'Pairing ulang',
      onPressed: onAction ?? () {},
    ),
    SettingsRow(
      variant: SettingsRowVariant.navigation,
      label: 'Lisensi open source',
      onPressed: () {},
    ),
    SettingsRow(
      variant: SettingsRowVariant.switchRow,
      label: 'Getar saat ditekan',
      subtitle: 'Saat tombol ditekan',
      toggled: true,
      onPressed: () {},
      trailing: const SizedBox(width: 60, height: 36, child: Text('on')),
    ),
  ],
);

void main() {
  testWidgets('each row is at least 56 dp tall', (tester) async {
    await pumpApp(tester, _group());
    final rows = find.byType(SettingsRow);
    expect(rows, findsNWidgets(4));
    for (final element in rows.evaluate()) {
      final size = tester.getSize(find.byWidget(element.widget));
      expect(size.height, greaterThanOrEqualTo(56), reason: '$element');
    }
  });

  testWidgets('each row is one Semantics node without children', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpApp(tester, _group());

    final versi = tester.getSemantics(
      find.bySemanticsLabel('Versi, 1.0.0 (1)'),
    );
    expect(versi.childrenCount, 0);
    expect(versi.flagsCollection.isButton, isFalse);

    final action = tester.getSemantics(find.bySemanticsLabel('Pairing ulang'));
    expect(action.childrenCount, 0);
    expect(action.flagsCollection.isButton, isTrue);

    final nav = tester.getSemantics(
      find.bySemanticsLabel('Lisensi open source'),
    );
    expect(nav.childrenCount, 0);

    final sw = tester.getSemantics(
      find.bySemanticsLabel('Getar saat ditekan, Saat tombol ditekan'),
    );
    expect(sw.childrenCount, 0);
    expect(sw.flagsCollection.isToggled, Tristate.isTrue);
    semantics.dispose();
  });

  testWidgets('tapping an action row calls its callback', (tester) async {
    var taps = 0;
    await pumpApp(tester, _group(onAction: () => taps++));
    await tester.tap(find.text('Pairing ulang'));
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('text scale 1.3 does not overflow', (tester) async {
    await pumpApp(
      tester,
      Builder(
        builder: (context) {
          final media = MediaQuery.of(context);
          return MediaQuery(
            data: media.copyWith(textScaler: const TextScaler.linear(1.3)),
            child: _group(),
          );
        },
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Versi'), findsOneWidget);
  });

  testWidgets('group has exactly one BackdropFilter', (tester) async {
    await pumpApp(tester, _group());
    expect(find.byType(BackdropFilter), findsOneWidget);
  });

  testWidgets('reduce transparency makes the group solid', (tester) async {
    await pumpApp(
      tester,
      _group(),
      overrides: [
        reduceTransparencyProvider.overrideWithBuild((ref, notifier) => true),
      ],
    );
    expect(find.byType(BackdropFilter), findsNothing);
    final fills = tester
        .widgetList<DecoratedBox>(find.byType(DecoratedBox))
        .map((box) => box.decoration)
        .whereType<BoxDecoration>()
        .map((d) => d.color)
        .whereType<Color>();
    expect(fills, contains(kLightTokens.glass.solid));
    expect(find.byType(GlassPanel), findsOneWidget);
  });
}
