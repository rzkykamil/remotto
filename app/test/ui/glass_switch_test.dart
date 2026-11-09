import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:remotto/core/haptics/r_haptics.dart';
import 'package:remotto/core/storage/app_preferences.dart';
import 'package:remotto/core/storage/storage_providers.dart';
import 'package:remotto/core/theme/tokens.g.dart';
import 'package:remotto/ui/glass_switch.dart';
import 'package:remotto/ui/r_icon.dart';
import 'package:remotto/ui/r_icons_data.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes.dart';
import '../support/test_app.dart';

const _label = 'Getar saat ditekan';

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

Future<void> _pump(
  WidgetTester tester, {
  required bool value,
  ValueChanged<bool>? onChanged,
  bool disableAnimations = false,
  bool dark = false,
}) async {
  await pumpApp(
    tester,
    GlassSwitch(
      value: value,
      onChanged: onChanged ?? (_) {},
      semanticsLabel: _label,
    ),
    overrides: await _overrides(RecordingHapticSink()),
    disableAnimations: disableAnimations,
    dark: dark,
  );
}

List<RIconData> _iconsInThumb(WidgetTester tester) => [
  for (final icon in tester.widgetList<RIcon>(
    find.descendant(of: find.byType(GlassSwitch), matching: find.byType(RIcon)),
  ))
    icon.data,
];

void main() {
  testWidgets('on shows the check icon, off shows the strip', (tester) async {
    await _pump(tester, value: true);
    expect(_iconsInThumb(tester), [RIcons.check]);

    await _pump(tester, value: false);
    expect(_iconsInThumb(tester), [RIcons.minus]);
  });

  testWidgets('track is 60 x 36 and the whole hit area is at least 48 dp', (
    tester,
  ) async {
    await _pump(tester, value: false);
    expect(
      tester.getSize(
        find
            .descendant(
              of: find.byType(GlassSwitch),
              matching: find.byType(Container),
            )
            .first,
      ),
      const Size(RSize.track, 36),
    );
    final hit = tester.getSize(find.byType(GlassSwitch));
    expect(hit.width, greaterThanOrEqualTo(48));
    expect(hit.height, greaterThanOrEqualTo(48));
  });

  testWidgets('exposes a toggled button with the label', (tester) async {
    await _pump(tester, value: true);
    expect(
      tester.getSemantics(find.bySemanticsLabel(_label)),
      matchesSemantics(
        label: _label,
        isButton: true,
        hasToggledState: true,
        isToggled: true,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
        hasFocusAction: true,
        isFocusable: true,
      ),
    );

    await _pump(tester, value: false);
    expect(
      tester.getSemantics(find.bySemanticsLabel(_label)),
      matchesSemantics(
        label: _label,
        isButton: true,
        hasToggledState: true,
        isToggled: false,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
        hasFocusAction: true,
        isFocusable: true,
      ),
    );
  });

  for (final value in [false, true]) {
    testWidgets('tap calls onChanged with the opposite of $value', (
      tester,
    ) async {
      final calls = <bool>[];
      await _pump(tester, value: value, onChanged: calls.add);

      await tester.tap(find.byType(GlassSwitch));
      await tester.pump();

      expect(calls, [!value]);
    });
  }

  testWidgets('disabled switch (null onChanged) does not respond to taps', (
    tester,
  ) async {
    await pumpApp(
      tester,
      const GlassSwitch(value: false, onChanged: null, semanticsLabel: _label),
      overrides: await _overrides(RecordingHapticSink()),
    );
    await tester.tap(find.byType(GlassSwitch));
    await tester.pump();
    expect(
      tester.getSemantics(find.bySemanticsLabel(_label)),
      matchesSemantics(
        label: _label,
        isButton: true,
        hasToggledState: true,
        isToggled: false,
        hasEnabledState: true,
        isEnabled: false,
      ),
    );
  });

  testWidgets('thumb moves instantly when animations are disabled', (
    tester,
  ) async {
    await _pump(tester, value: false, disableAnimations: true);
    await _pump(tester, value: true, disableAnimations: true);
    await tester.pump();

    final thumb = tester.widget<AnimatedPositioned>(
      find.byType(AnimatedPositioned),
    );
    expect(thumb.duration, Duration.zero);
    expect(thumb.left, 27);
  });

  testWidgets('renders in dark mode without errors', (tester) async {
    await _pump(tester, value: true, dark: true);
    expect(tester.takeException(), isNull);
    expect(_iconsInThumb(tester), [RIcons.check]);
  });
}
