import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotto/core/haptics/r_haptics.dart';
import 'package:remotto/core/storage/app_preferences.dart';
import 'package:remotto/core/storage/storage_providers.dart';
import 'package:remotto/core/strings/settings_strings.dart';
import 'package:remotto/core/theme/app_theme.dart';
import 'package:remotto/features/settings/widgets/repair_confirm.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes.dart';

const _trigger = 'buka';
const _laptop = 'Laptop-Kamil';

/// Hasil satu kali sheet dibuka.
final class _Harness {
  bool closed = false;
  bool? result;
}

/// Menampilkan layar dengan pemicu yang membuka konfirmasi pairing ulang.
Future<_Harness> _open(WidgetTester tester) async {
  final harness = _Harness();
  SharedPreferences.setMockInitialValues({
    AppPreferences.keyHapticEnabled: true,
  });
  final prefs = await SharedPreferences.getInstance();

  tester.view.physicalSize = const Size(360, 780);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        hapticSinkProvider.overrideWithValue(RecordingHapticSink()),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: GestureDetector(
                onTap: () async {
                  harness.result = await showRepairConfirmSheet(
                    context,
                    laptopName: _laptop,
                  );
                  harness.closed = true;
                },
                child: const Text(_trigger),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text(_trigger));
  await tester.pumpAndSettle();
  return harness;
}

void main() {
  testWidgets('"Hapus & pairing ulang" completes with true', (tester) async {
    final harness = await _open(tester);

    await tester.tap(find.text(SettingsStrings.repairSheetConfirm));
    await tester.pumpAndSettle();

    expect(harness.closed, isTrue);
    expect(harness.result, isTrue);
  });

  testWidgets('"Nggak jadi" completes with false', (tester) async {
    final harness = await _open(tester);

    await tester.tap(find.text(SettingsStrings.repairSheetCancel));
    await tester.pumpAndSettle();

    expect(harness.closed, isTrue);
    expect(harness.result, isFalse);
  });

  testWidgets('tap on the scrim completes with false', (tester) async {
    final harness = await _open(tester);

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(harness.closed, isTrue);
    expect(harness.result, isFalse);
  });

  testWidgets('system back completes with false', (tester) async {
    final harness = await _open(tester);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(harness.closed, isTrue);
    expect(harness.result, isFalse);
  });

  testWidgets('sheet exposes a named route with the question', (tester) async {
    await _open(tester);

    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Semantics &&
            w.properties.scopesRoute == true &&
            w.properties.namesRoute == true &&
            w.properties.label == SettingsStrings.repairSheetTitle,
      ),
      findsOneWidget,
    );
    expect(find.text(SettingsStrings.repairSheetBody(_laptop)), findsOneWidget);
  });
}
