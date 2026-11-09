import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotto/core/theme/tokens.g.dart';
import 'package:remotto/ui/r_icon.dart';
import 'package:remotto/ui/r_icons_data.dart';

import '../support/test_app.dart';

const _all = <RIconData>[
  RIcons.back,
  RIcons.flashlight,
  RIcons.camera,
  RIcons.cameraOff,
  RIcons.wifi,
  RIcons.wifiOff,
  RIcons.key,
  RIcons.plug,
  RIcons.check,
  RIcons.alertTriangle,
  RIcons.alertCircle,
  RIcons.eye,
  RIcons.settingsSliders,
  RIcons.power,
  RIcons.skipPrev,
  RIcons.skipNext,
  RIcons.play,
  RIcons.pause,
];

void main() {
  for (final dark in [false, true]) {
    testWidgets('paints every icon in ${dark ? 'dark' : 'light'} theme', (
      tester,
    ) async {
      final tokens = dark ? kDarkTokens : kLightTokens;
      await pumpApp(
        tester,
        Wrap(
          children: [
            for (final icon in _all)
              RIcon(icon, size: 24, color: tokens.fg.primary, strokeWidth: 2),
          ],
        ),
        dark: dark,
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(RIcon), findsNWidgets(_all.length));
      expect(find.byType(CustomPaint), findsWidgets);
    });
  }

  testWidgets('RIcon takes the requested size', (tester) async {
    await pumpApp(
      tester,
      RIcon(RIcons.check, size: 48, color: kLightTokens.fg.primary),
    );
    expect(tester.getSize(find.byType(RIcon)), const Size(48, 48));
  });

  testWidgets('RIcon filled renders and stays excluded from Semantics', (
    tester,
  ) async {
    await pumpApp(
      tester,
      RIcon(
        RIcons.play,
        size: 36,
        color: kLightTokens.fg.primary,
        strokeWidth: 0,
        filled: true,
      ),
    );
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(RIcon)), const Size(36, 36));
    expect(
      find.descendant(
        of: find.byType(RIcon),
        matching: find.byType(ExcludeSemantics),
      ),
      findsOneWidget,
    );
  });

  testWidgets('RIcon is decorative and excluded from Semantics', (
    tester,
  ) async {
    await pumpApp(
      tester,
      RIcon(RIcons.power, size: 24, color: kLightTokens.fg.primary),
    );
    expect(
      find.descendant(
        of: find.byType(RIcon),
        matching: find.byType(ExcludeSemantics),
      ),
      findsOneWidget,
    );
  });
}
