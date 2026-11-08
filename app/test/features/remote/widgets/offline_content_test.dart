import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:remotto/core/connection/connection_state.dart';
import 'package:remotto/core/haptics/r_haptics.dart';
import 'package:remotto/core/storage/app_preferences.dart';
import 'package:remotto/core/storage/storage_providers.dart';
import 'package:remotto/features/remote/widgets/offline_content.dart';
import 'package:remotto/ui/glass_key.dart';
import 'package:remotto/ui/link_button.dart';
import 'package:remotto/ui/r_icon.dart';
import 'package:remotto/ui/r_icons_data.dart';
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

bool Function(Widget) _iconIs(RIconData data) =>
    (w) => w is RIcon && identical(w.data, data);

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

  testWidgets(
    'powered-off shows P15 title, body with time, and only Pairing ulang',
    (tester) async {
      final sink = RecordingHapticSink();
      final sentAt = DateTime(2026, 11, 8, 23, 41);
      await pumpApp(
        tester,
        OfflineContent(
          onRetry: () {},
          onRepair: () {},
          poweredOff: true,
          lastCommand: LastPowerCommand(action: 'shutdown', sentAt: sentAt),
        ),
        overrides: await _overrides(sink),
      );

      expect(find.text('Laptop lagi mati'), findsOneWidget);
      expect(find.text('Laptop nggak kejangkau'), findsNothing);
      expect(
        find.text(
          'Dimatiin dari HP ini jam 23.41. Nyalain laptopnya, nanti nyambung sendiri.',
        ),
        findsOneWidget,
      );
      expect(
        find.text('Pastikan HP dan laptop satu WiFi, dan laptop lagi nyala.'),
        findsNothing,
      );
      expect(find.text('Coba lagi'), findsNothing);
      expect(find.text('Pairing ulang'), findsOneWidget);
      expect(find.byWidgetPredicate(_iconIs(RIcons.power)), findsOneWidget);
      expect(find.byWidgetPredicate(_iconIs(RIcons.wifiOff)), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('powered-off renders in light and dark', (tester) async {
    final sink = RecordingHapticSink();
    for (final dark in [false, true]) {
      await pumpApp(
        tester,
        OfflineContent(
          onRetry: () {},
          onRepair: () {},
          poweredOff: true,
          lastCommand: LastPowerCommand(
            action: 'shutdown',
            sentAt: DateTime(2026, 11, 8, 23, 41),
          ),
        ),
        dark: dark,
        overrides: await _overrides(sink),
      );
      expect(find.text('Laptop lagi mati'), findsOneWidget);
      expect(find.text('Pairing ulang'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('powered-off after sleep uses the sleep body', (tester) async {
    final sink = RecordingHapticSink();
    await pumpApp(
      tester,
      OfflineContent(
        onRetry: () {},
        onRepair: () {},
        poweredOff: true,
        lastCommand: LastPowerCommand(
          action: 'sleep',
          sentAt: DateTime(2026, 11, 8, 7, 5),
        ),
      ),
      overrides: await _overrides(sink),
    );

    expect(
      find.text(
        'Di-sleep-in dari HP ini jam 07.05. Buka lagi laptopnya, nanti nyambung sendiri.',
      ),
      findsOneWidget,
    );
    expect(find.text('Coba lagi'), findsNothing);
  });

  testWidgets('powered-off without a command falls back to the offline body', (
    tester,
  ) async {
    final sink = RecordingHapticSink();
    await pumpApp(
      tester,
      _content(poweredOff: true),
      overrides: await _overrides(sink),
    );

    expect(find.text('Laptop lagi mati'), findsOneWidget);
    expect(
      find.text('Pastikan HP dan laptop satu WiFi, dan laptop lagi nyala.'),
      findsOneWidget,
    );
    expect(find.text('Pairing ulang'), findsOneWidget);
  });

  testWidgets('plain offline keeps the offline title, body and Coba lagi', (
    tester,
  ) async {
    final sink = RecordingHapticSink();
    await pumpApp(tester, _content(), overrides: await _overrides(sink));

    expect(find.text('Laptop nggak kejangkau'), findsOneWidget);
    expect(find.text('Laptop lagi mati'), findsNothing);
    expect(find.text('Coba lagi'), findsOneWidget);
    expect(find.text('Pairing ulang'), findsOneWidget);
  });

  testWidgets('powered-off at 360 dp with 130 percent text has no overflow', (
    tester,
  ) async {
    final sink = RecordingHapticSink();
    await pumpApp(
      tester,
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
        child: OfflineContent(
          onRetry: () {},
          onRepair: () {},
          poweredOff: true,
          lastCommand: LastPowerCommand(
            action: 'shutdown',
            sentAt: DateTime(2026, 11, 8, 23, 41),
          ),
        ),
      ),
      size: const Size(360, 800),
      overrides: await _overrides(sink),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Pairing ulang'), findsOneWidget);
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
