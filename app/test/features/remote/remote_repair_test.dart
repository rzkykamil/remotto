import 'dart:ui' show Size;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotto/app.dart';
import 'package:remotto/core/connection/connection_providers.dart';
import 'package:remotto/core/connection/status_repository.dart';
import 'package:remotto/core/network/api_failure.dart';
import 'package:remotto/core/network/network_providers.dart';
import 'package:remotto/core/router/app_router.dart';
import 'package:remotto/core/storage/pairing_data.dart';
import 'package:remotto/core/storage/storage_providers.dart';
import 'package:remotto/core/strings/settings_strings.dart';
import 'package:remotto/features/remote/power/power_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_poll_scheduler.dart';
import '../../support/fake_power_repository.dart';
import '../../support/fake_status_repository.dart';
import '../../support/fakes.dart';
import '../../support/volume_overrides.dart';

const _pairing = PairingData(
  host: '192.168.1.10',
  port: 8765,
  token: 'test-token',
  laptopName: 'Laptop Uji',
);

/// Remote dibuka dengan laptop offline (dua polling gagal, S10), lalu
/// menampilkan tombol "Pairing ulang" dari C08.
Future<(ProviderContainer, InMemoryConnectionStorage, FakePollScheduler)>
_pumpOffline(WidgetTester tester) async {
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
  final storage = InMemoryConnectionStorage(_pairing);
  final scheduler = FakePollScheduler();
  final StatusRepository repo = FakeStatusRepository([
    const FakeTransportFailure(UnreachableFailure()),
  ]);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        initialPairingProvider.overrideWithValue(_pairing),
        connectionStorageProvider.overrideWithValue(storage),
        statusRepositoryProvider.overrideWithValue(repo),
        pollSchedulerProvider.overrideWithValue(scheduler),
        volumeOverride(),
        powerRepositoryProvider.overrideWithValue(FakePowerRepository()),
      ],
      child: const RemottoApp(),
    ),
  );
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await tester.pumpAndSettle();
  scheduler.tick();
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await tester.pumpAndSettle();

  final container = ProviderScope.containerOf(
    tester.element(find.byType(RemottoApp)),
  );
  return (container, storage, scheduler);
}

String _path(ProviderContainer container) =>
    container.read(routerProvider).routerDelegate.currentConfiguration.uri.path;

void main() {
  testWidgets(
    'offline: "Pairing ulang" -> konfirmasi menghapus data dan pindah ke /pairing',
    (tester) async {
      final (container, storage, _) = await _pumpOffline(tester);
      expect(find.text('Pairing ulang'), findsOneWidget);

      await tester.tap(find.text('Pairing ulang'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(SettingsStrings.repairSheetConfirm));
      await tester.pumpAndSettle();

      expect(storage.data, isNull);
      expect(container.read(pairingProvider), isNull);
      expect(_path(container), AppRoutes.pairing);
      expect(container.read(lastPowerCommandProvider), isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'offline: "Nggak jadi" tidak mengubah data dan tetap di /remote',
    (tester) async {
      final (container, storage, _) = await _pumpOffline(tester);

      await tester.tap(find.text('Pairing ulang'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(SettingsStrings.repairSheetCancel));
      await tester.pumpAndSettle();

      expect(storage.data, _pairing);
      expect(container.read(pairingProvider), _pairing);
      expect(_path(container), AppRoutes.remote);
    },
  );
}
