import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:remotto/app.dart';
import 'package:remotto/core/connection/connection_controller.dart';
import 'package:remotto/core/connection/connection_providers.dart';
import 'package:remotto/core/connection/connection_state.dart';
import 'package:remotto/core/connection/status_repository.dart';
import 'package:remotto/core/network/api_failure.dart';
import 'package:remotto/core/network/network_providers.dart';
import 'package:remotto/core/router/app_router.dart';
import 'package:remotto/core/storage/connection_storage.dart';
import 'package:remotto/core/storage/pairing_data.dart';
import 'package:remotto/core/storage/storage_providers.dart';
import 'package:remotto/core/strings/strings.dart';
import 'package:remotto/features/pairing/state/pairing_flow_controller.dart';
import 'package:remotto/features/pairing/state/pairing_flow_state.dart';
import 'package:remotto/features/remote/remote_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_status_repository.dart';
import '../../support/fakes.dart';

const _pairing = PairingData(
  host: '192.168.1.10',
  port: 8765,
  token: 'test-token',
  laptopName: 'Laptop Uji',
);

/// Scheduler that never runs timers. Polling only via `pollOnce`.
final class _SilentScheduler implements PollScheduler {
  @override
  ScheduledJob every(Duration interval, void Function() tick) => _NoopJob();

  @override
  ScheduledJob after(Duration delay, void Function() callback) => _NoopJob();
}

final class _NoopJob implements ScheduledJob {
  @override
  void cancel() {}
}

Future<ProviderContainer> _pumpRouter(
  WidgetTester tester, {
  PairingData? initial,
  required ConnectionStorage storage,
  StatusRepository? repo,
  List<Override> extra = const [],
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
        // A poll from the Remote screen must not use a timer or the real mock.
        statusRepositoryProvider.overrideWithValue(
          repo ?? FakeStatusRepository([fakeStatusOk()]),
        ),
        pollSchedulerProvider.overrideWithValue(_SilentScheduler()),
        ...extra,
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

    // push does not update currentConfiguration, so check the screen shown.
    unawaited(router.push(AppRoutes.settings));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.placeholderSettings), findsOneWidget);
    expect(router.canPop(), isTrue);

    router.pop();
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.placeholderSettings), findsNothing);
    expect(find.byType(RemoteScreen), findsOneWidget);
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

  testWidgets('(h) 401 dari Remote: Q12, polling berhenti, data lama tetap', (
    tester,
  ) async {
    final storage = InMemoryConnectionStorage(_pairing);
    // The first poll (when the Remote screen opens) succeeds, later polls get 401.
    final repo = FakeStatusRepository([
      fakeStatusOk(),
      fakeErrorReply(401, 'unauthorized'),
    ]);
    final container = await _pumpRouter(
      tester,
      initial: _pairing,
      storage: storage,
      repo: repo,
    );
    expect(_path(container), AppRoutes.remote);

    await tester.runAsync(
      () => container.read(connectionControllerProvider.notifier).pollOnce(),
    );
    await tester.pumpAndSettle();

    expect(
      container.read(connectionControllerProvider).phase,
      ConnectionPhase.tokenRejected,
    );
    expect(container.read(pairingFlowProvider).step, PairingStep.expired);
    expect(_path(container), AppRoutes.pairing);
    expect(container.read(routerProvider).canPop(), isFalse);
    expect(storage.data, _pairing);

    // Polling has stopped: the next poll does not call the repository.
    await tester.runAsync(
      () => container.read(connectionControllerProvider.notifier).pollOnce(),
    );
    expect(repo.calls, 2);
  });

  testWidgets('(i) gagal jaringan biasa tidak memindahkan ke Q12', (
    tester,
  ) async {
    final repo = FakeStatusRepository([
      const FakeTransportFailure(TimeoutFailure()),
    ]);
    final container = await _pumpRouter(
      tester,
      initial: _pairing,
      storage: InMemoryConnectionStorage(_pairing),
      repo: repo,
    );

    await tester.runAsync(
      () => container.read(connectionControllerProvider.notifier).pollOnce(),
    );
    await tester.pumpAndSettle();

    expect(
      container.read(connectionControllerProvider).phase,
      isNot(ConnectionPhase.tokenRejected),
    );
    expect(_path(container), AppRoutes.remote);
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
