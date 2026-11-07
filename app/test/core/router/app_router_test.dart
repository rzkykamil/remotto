import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotto/app.dart';
import 'package:remotto/core/router/app_router.dart';
import 'package:remotto/core/storage/connection_storage.dart';
import 'package:remotto/core/storage/pairing_data.dart';
import 'package:remotto/core/storage/storage_providers.dart';
import 'package:remotto/core/strings/strings.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fakes.dart';

const _pairing = PairingData(
  host: '192.168.1.10',
  port: 8765,
  token: 'test-token',
  laptopName: 'Laptop Uji',
);

Future<ProviderContainer> _pumpRouter(
  WidgetTester tester, {
  PairingData? initial,
  required ConnectionStorage storage,
}) async {
  tester.view.physicalSize = const Size(412, 892);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  final prefs = (await tester.runAsync(() async {
    SharedPreferences.setMockInitialValues({});
    return SharedPreferences.getInstance();
  }))!;

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        initialPairingProvider.overrideWithValue(initial),
        connectionStorageProvider.overrideWithValue(storage),
      ],
      child: const RemottoApp(),
    ),
  );
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(RemottoApp)));
}

String _path(ProviderContainer container) =>
    container.read(routerProvider).routerDelegate.currentConfiguration.uri.path;

void main() {
  group('redirectFor (murni)', () {
    test('/ mengarah ke /remote bila ada data, /pairing bila tidak', () {
      expect(
        redirectFor(hasPairing: true, location: AppRoutes.home),
        AppRoutes.remote,
      );
      expect(
        redirectFor(hasPairing: false, location: AppRoutes.home),
        AppRoutes.pairing,
      );
    });

    test('tanpa data, /remote dan /settings dialihkan ke /pairing', () {
      expect(
        redirectFor(hasPairing: false, location: AppRoutes.remote),
        AppRoutes.pairing,
      );
      expect(
        redirectFor(hasPairing: false, location: AppRoutes.settings),
        AppRoutes.pairing,
      );
    });

    test('lokasi lain tidak diubah', () {
      expect(
        redirectFor(hasPairing: true, location: AppRoutes.pairing),
        isNull,
      );
      expect(
        redirectFor(hasPairing: false, location: AppRoutes.pairing),
        isNull,
      );
    });
  });

  testWidgets('(a) tanpa data, lokasi akhir /pairing', (tester) async {
    final container = await _pumpRouter(
      tester,
      storage: InMemoryConnectionStorage(),
    );
    expect(_path(container), AppRoutes.pairing);
  });

  testWidgets('(b) dengan data, lokasi akhir /remote', (tester) async {
    final container = await _pumpRouter(
      tester,
      initial: _pairing,
      storage: InMemoryConnectionStorage(_pairing),
    );
    expect(_path(container), AppRoutes.remote);
  });

  testWidgets('(c) tanpa data, membuka /remote dialihkan ke /pairing', (
    tester,
  ) async {
    final container = await _pumpRouter(
      tester,
      storage: InMemoryConnectionStorage(),
    );
    container.read(routerProvider).go(AppRoutes.remote);
    await tester.pumpAndSettle();
    expect(_path(container), AppRoutes.pairing);
  });

  testWidgets('(d) dengan data, /pairing tetap /pairing', (tester) async {
    final container = await _pumpRouter(
      tester,
      initial: _pairing,
      storage: InMemoryConnectionStorage(_pairing),
    );
    container.read(routerProvider).go(AppRoutes.pairing);
    await tester.pumpAndSettle();
    expect(_path(container), AppRoutes.pairing);
  });

  testWidgets('(e) push /settings dari /remote lalu pop kembali ke /remote', (
    tester,
  ) async {
    final container = await _pumpRouter(
      tester,
      initial: _pairing,
      storage: InMemoryConnectionStorage(_pairing),
    );
    final router = container.read(routerProvider);

    // push tidak memperbarui currentConfiguration, jadi cek layar yang tampil.
    unawaited(router.push(AppRoutes.settings));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.placeholderSettings), findsOneWidget);
    expect(router.canPop(), isTrue);

    router.pop();
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.placeholderSettings), findsNothing);
    expect(find.text(AppStrings.placeholderRemote), findsOneWidget);
    expect(router.canPop(), isFalse);
  });

  testWidgets('(f) /remote sebagai akar: canPop false (back keluar app)', (
    tester,
  ) async {
    final container = await _pumpRouter(
      tester,
      initial: _pairing,
      storage: InMemoryConnectionStorage(_pairing),
    );
    expect(container.read(routerProvider).canPop(), isFalse);
  });

  testWidgets('(g) clear pairing saat di /remote berpindah ke /pairing', (
    tester,
  ) async {
    final storage = InMemoryConnectionStorage(_pairing);
    final container = await _pumpRouter(
      tester,
      initial: _pairing,
      storage: storage,
    );
    expect(_path(container), AppRoutes.remote);

    await tester.runAsync(
      () => container.read(pairingProvider.notifier).clear(),
    );
    await tester.pumpAndSettle();

    expect(_path(container), AppRoutes.pairing);
    expect(storage.data, isNull);
  });

  Future<(double, double)> slideProbe(WidgetTester tester) async {
    final container = await _pumpRouter(
      tester,
      initial: _pairing,
      storage: InMemoryConnectionStorage(_pairing),
    );
    unawaited(container.read(routerProvider).push(AppRoutes.settings));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    final finder = find.text(AppStrings.placeholderSettings);
    final during = tester.getTopLeft(finder).dy;
    await tester.pumpAndSettle();
    return (during, tester.getTopLeft(finder).dy);
  }

  testWidgets('transisi layar menggeser saat motion normal', (tester) async {
    final (during, settled) = await slideProbe(tester);
    expect(during, isNot(settled));
  });

  testWidgets('reduced motion: transisi layar tanpa geser (fade saja)', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final (during, settled) = await slideProbe(tester);
    expect(during, settled);
  });
}
