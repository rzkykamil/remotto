import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:remotto/core/haptics/r_haptics.dart';
import 'package:remotto/core/storage/app_preferences.dart';
import 'package:remotto/core/storage/storage_providers.dart';
import 'package:remotto/features/remote/widgets/offline_content.dart';
import 'package:remotto/ui/glass_key.dart';
import 'package:remotto/ui/link_button.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/fakes.dart';
import '../../../support/test_app.dart';

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

OfflineContent _content({
  VoidCallback? onRetry,
  VoidCallback? onRepair,
  bool retrying = false,
  bool poweredOff = false,
}) => OfflineContent(
  onRetry: onRetry ?? () {},
  onRepair: onRepair ?? () {},
  retrying: retrying,
  poweredOff: poweredOff,
);

void main() {
  testWidgets('shows title, body, retry and repair actions in light and dark', (
    tester,
  ) async {
    final sink = RecordingHapticSink();
    for (final dark in [false, true]) {
      await pumpApp(
        tester,
        _content(),
        dark: dark,
        overrides: await _overrides(sink),
      );
      expect(find.text('Laptop nggak kejangkau'), findsOneWidget);
      expect(
        find.text('Pastikan HP dan laptop satu WiFi, dan laptop lagi nyala.'),
        findsOneWidget,
      );
      expect(find.text('Coba lagi'), findsOneWidget);
      expect(find.text('Pairing ulang'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('retry and repair fire their callbacks', (tester) async {
    final sink = RecordingHapticSink();
    var retried = 0;
    var repaired = 0;
    await pumpApp(
      tester,
      _content(onRetry: () => retried++, onRepair: () => repaired++),
      overrides: await _overrides(sink),
    );

    await tester.tap(find.text('Coba lagi'));
    await tester.pump();
    await tester.tap(find.text('Pairing ulang'));
    await tester.pump();

    expect(retried, 1);
    expect(repaired, 1);
  });

  testWidgets('retrying shows Nyoba… and disables the retry key', (
    tester,
  ) async {
    final sink = RecordingHapticSink();
    var retried = 0;
    await pumpApp(
      tester,
      _content(retrying: true, onRetry: () => retried++),
      overrides: await _overrides(sink),
    );

    expect(find.text('Nyoba…'), findsOneWidget);
    expect(find.text('Coba lagi'), findsNothing);

    final key = tester.widget<GlassKey>(find.byType(GlassKey));
    expect(key.onPressed, isNull);

    await tester.tap(find.text('Nyoba…'));
    await tester.pump();
    expect(retried, 0);
  });

  testWidgets('powered-off state shows its title instead of offline title', (
    tester,
  ) async {
    final sink = RecordingHapticSink();
    await pumpApp(
      tester,
      _content(poweredOff: true),
      overrides: await _overrides(sink),
    );

    expect(find.text('Laptop lagi mati'), findsOneWidget);
    expect(find.text('Laptop nggak kejangkau'), findsNothing);
  });

  testWidgets('retry key and repair link reach 48 dp touch target', (
    tester,
  ) async {
    final sink = RecordingHapticSink();
    await pumpApp(tester, _content(), overrides: await _overrides(sink));

    expect(
      tester.getSize(find.byType(GlassKey)).height,
      greaterThanOrEqualTo(48),
    );
    expect(
      tester.getSize(find.byType(RLinkButton)).height,
      greaterThanOrEqualTo(48),
    );
  });

  testWidgets('title is a semantics header', (tester) async {
    final sink = RecordingHapticSink();
    await pumpApp(tester, _content(), overrides: await _overrides(sink));

    final node = tester.getSemantics(find.text('Laptop nggak kejangkau'));
    expect(node.flagsCollection.isHeader, isTrue);
  });

  testWidgets('no overflow at 360 dp with 130 percent text scale', (
    tester,
  ) async {
    final sink = RecordingHapticSink();
    await pumpApp(
      tester,
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
        child: _content(),
      ),
      size: const Size(360, 800),
      overrides: await _overrides(sink),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Pairing ulang'), findsOneWidget);
  });
}
