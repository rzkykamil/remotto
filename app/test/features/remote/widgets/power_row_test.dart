import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:remotto/core/haptics/r_haptics.dart';
import 'package:remotto/core/storage/app_preferences.dart';
import 'package:remotto/core/storage/storage_providers.dart';
import 'package:remotto/core/strings/power_strings.dart';
import 'package:remotto/core/theme/app_theme.dart';
import 'package:remotto/features/remote/data/power_repository.dart';
import 'package:remotto/features/remote/widgets/power_row.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/fakes.dart';
import '../../../support/test_app.dart';

Finder _semantics(String label) => find.bySemanticsLabel(label);

/// Loads the bundled Geist font, so label widths match the app and not the
/// test font (Ahem, one em per glyph).
Future<void> _loadGeist() async {
  final loader = FontLoader('Geist');
  for (final name in ['Geist-Regular', 'Geist-Medium', 'Geist-SemiBold']) {
    final bytes = File('assets/fonts/$name.ttf').readAsBytesSync();
    loader.addFont(
      Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)),
    );
  }
  await loader.load();
}

void main() {
  setUpAll(_loadGeist);

  late List<PowerAction> selected;
  late RecordingHapticSink sink;

  setUp(() {
    selected = [];
    sink = RecordingHapticSink();
  });

  Future<List<Override>> overrides() async {
    SharedPreferences.setMockInitialValues({
      AppPreferences.keyHapticEnabled: true,
    });
    final prefs = await SharedPreferences.getInstance();
    return [
      hapticSinkProvider.overrideWithValue(sink),
      sharedPreferencesProvider.overrideWithValue(prefs),
    ];
  }

  Future<void> pumpRow(
    WidgetTester tester, {
    bool enabled = true,
    bool dark = false,
    double textScale = 1.0,
    Size size = const Size(412, 892),
  }) async {
    final row = PowerRow(enabled: enabled, onSelected: selected.add);
    if (textScale == 1.0) {
      await pumpApp(
        tester,
        row,
        overrides: await overrides(),
        dark: dark,
        size: size,
      );
      return;
    }

    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: await overrides(),
        child: MaterialApp(
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: dark ? ThemeMode.dark : ThemeMode.light,
          builder: (context, widget) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: widget!,
          ),
          home: Scaffold(body: Center(child: row)),
        ),
      ),
    );
  }

  testWidgets('shows Sleep, Restart, and Matikan', (tester) async {
    await pumpRow(tester);

    expect(find.text(PowerStrings.rowSleep), findsOneWidget);
    expect(find.text(PowerStrings.rowRestart), findsOneWidget);
    expect(find.text(PowerStrings.rowShutdown), findsOneWidget);
  });

  testWidgets('each tap reports the matching action', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpRow(tester);

    await tester.tap(_semantics(PowerStrings.semSleep));
    await tester.pumpAndSettle();
    await tester.tap(_semantics(PowerStrings.semRestart));
    await tester.pumpAndSettle();
    await tester.tap(_semantics(PowerStrings.semShutdown));
    await tester.pumpAndSettle();

    expect(selected, [
      PowerAction.sleep,
      PowerAction.restart,
      PowerAction.shutdown,
    ]);
    handle.dispose();
  });

  testWidgets('tap is ignored when disabled', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpRow(tester, enabled: false);

    await tester.tap(_semantics(PowerStrings.semSleep));
    await tester.tap(_semantics(PowerStrings.semRestart));
    await tester.tap(_semantics(PowerStrings.semShutdown));
    await tester.pumpAndSettle();

    expect(selected, isEmpty);
    handle.dispose();
  });

  testWidgets('each key has its Semantics label', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpRow(tester);

    expect(_semantics(PowerStrings.semSleep), findsOneWidget);
    expect(_semantics(PowerStrings.semRestart), findsOneWidget);
    expect(_semantics(PowerStrings.semShutdown), findsOneWidget);
    handle.dispose();
  });

  testWidgets('labels stay on one line at 360 dp with screen margins', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: await overrides(),
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Center(
                child: PowerRow(enabled: true, onSelected: selected.add),
              ),
            ),
          ),
        ),
      ),
    );

    for (final label in [
      PowerStrings.rowSleep,
      PowerStrings.rowRestart,
      PowerStrings.rowShutdown,
    ]) {
      final style = tester.widget<Text>(find.text(label)).style;
      final painter = TextPainter(
        text: TextSpan(text: label, style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      final oneLine = painter.height;
      expect(
        tester.getSize(find.text(label)).height,
        closeTo(oneLine, 0.5),
        reason: '$label wraps',
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('fits 360 dp without overflow', (tester) async {
    await pumpRow(tester, size: const Size(360, 780));

    expect(tester.takeException(), isNull);
  });

  testWidgets('fits 412 dp without overflow', (tester) async {
    await pumpRow(tester);

    expect(tester.takeException(), isNull);
  });

  testWidgets('fits 360 dp with text scale 1.3 without overflow', (
    tester,
  ) async {
    await pumpRow(tester, size: const Size(360, 780), textScale: 1.3);

    expect(tester.takeException(), isNull);
    expect(find.text(PowerStrings.rowRestart), findsOneWidget);
  });

  testWidgets('renders in dark theme without overflow', (tester) async {
    await pumpRow(tester, dark: true);

    expect(tester.takeException(), isNull);
    expect(find.text(PowerStrings.rowSleep), findsOneWidget);
  });
}
