import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotto/app.dart';
import 'package:remotto/core/router/app_router.dart';
import 'package:remotto/core/storage/pairing_data.dart';
import 'package:remotto/core/storage/storage_providers.dart';
import 'package:remotto/core/strings/strings.dart';
import 'package:remotto/ui/light_backdrop.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

const _pairing = PairingData(
  host: '192.168.1.10',
  port: 8765,
  token: 'test-token',
  laptopName: 'Laptop Uji',
);

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  Map<String, Object> prefValues = const {},
}) async {
  tester.view.physicalSize = const Size(412, 892);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  final prefs = (await tester.runAsync(() async {
    SharedPreferences.setMockInitialValues(prefValues);
    return SharedPreferences.getInstance();
  }))!;

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        initialPairingProvider.overrideWithValue(_pairing),
        connectionStorageProvider.overrideWithValue(
          InMemoryConnectionStorage(_pairing),
        ),
      ],
      child: const RemottoApp(),
    ),
  );
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(RemottoApp)));
}

Brightness _brightness(WidgetTester tester) =>
    Theme.of(tester.element(find.byType(LightBackdrop))).brightness;

void main() {
  testWidgets('RemottoApp render dengan latar, placeholder /remote tampil', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.byType(LightBackdrop), findsOneWidget);
    expect(find.text(AppStrings.placeholderRemote), findsOneWidget);
  });

  testWidgets('tema default mengikuti sistem (light di test)', (tester) async {
    await _pump(tester);
    expect(_brightness(tester), Brightness.light);
  });

  testWidgets('preferensi dark dibaca saat start', (tester) async {
    await _pump(tester, prefValues: {'themeMode': 'dark'});
    expect(_brightness(tester), Brightness.dark);
  });

  testWidgets('themeModeProvider set dark mengubah brightness', (tester) async {
    final container = await _pump(tester);
    expect(_brightness(tester), Brightness.light);

    await tester.runAsync(
      () => container.read(themeModeProvider.notifier).set(ThemeMode.dark),
    );
    await tester.pumpAndSettle();

    expect(_brightness(tester), Brightness.dark);
  });

  testWidgets('placeholder Pengaturan belum tampil di rute awal', (
    tester,
  ) async {
    final container = await _pump(tester);
    expect(
      container
          .read(routerProvider)
          .routerDelegate
          .currentConfiguration
          .uri
          .path,
      AppRoutes.remote,
    );
    expect(find.text(AppStrings.placeholderSettings), findsNothing);
  });
}
