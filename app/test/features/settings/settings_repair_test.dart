import 'dart:async';
import 'dart:ui' show Size;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:remotto/app.dart';
import 'package:remotto/core/connection/connection_providers.dart';
import 'package:remotto/core/connection/connection_state.dart';
import 'package:remotto/core/connection/status_repository.dart';
import 'package:remotto/core/network/network_providers.dart';
import 'package:remotto/core/router/app_router.dart';
import 'package:remotto/core/storage/connection_storage.dart';
import 'package:remotto/core/storage/pairing_data.dart';
import 'package:remotto/core/storage/storage_providers.dart';
import 'package:remotto/core/strings/remote_strings.dart';
import 'package:remotto/core/strings/settings_strings.dart';
import 'package:remotto/features/remote/power/power_providers.dart';
import 'package:remotto/features/settings/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_power_repository.dart';
import '../../support/fake_poll_scheduler.dart';
import '../../support/fake_status_repository.dart';
import '../../support/fakes.dart';
import '../../support/volume_overrides.dart';

const _pairing = PairingData(
  host: '192.168.1.10',
  port: 8765,
  token: 'test-token',
  laptopName: 'Laptop Uji',
);

/// Storage yang gagal saat dihapus (Q-repair gagal).
final class _FailingClearStorage implements ConnectionStorage {
  _FailingClearStorage(this.data);

  PairingData? data;

  @override
  Future<PairingData?> read() async => data;

  @override
  Future<void> write(PairingData value) async => data = value;

  @override
  Future<void> clear() async => throw StateError('clear gagal');
}

Future<ProviderContainer> _pumpApp(
  WidgetTester tester, {
  required ConnectionStorage storage,
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

  final StatusRepository repo = FakeStatusRepository([
    fakeStatusOk(name: 'Laptop-Kamil'),
  ]);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        initialPairingProvider.overrideWithValue(_pairing),
        connectionStorageProvider.overrideWithValue(storage),
        statusRepositoryProvider.overrideWithValue(repo),
        pollSchedulerProvider.overrideWithValue(FakePollScheduler()),
        volumeOverride(),
        powerRepositoryProvider.overrideWithValue(FakePowerRepository()),
        ...extra,
      ],
      child: const RemottoApp(),
    ),
  );
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await tester.pumpAndSettle();

  final container = ProviderScope.containerOf(
    tester.element(find.byType(RemottoApp)),
  );
  return container;
}

/// Membuka Pengaturan dengan push, seperti tombol di Remote.
Future<void> _openSettings(
  WidgetTester tester,
  ProviderContainer container,
) async {
  unawaited(container.read(routerProvider).push(AppRoutes.settings));
  await tester.pumpAndSettle();
  expect(find.byType(SettingsScreen), findsOneWidget);
}

String _path(ProviderContainer container) =>
    container.read(routerProvider).routerDelegate.currentConfiguration.uri.path;

void main() {
  testWidgets(
    'konfirmasi "Hapus & pairing ulang" menghapus data dan pindah ke /pairing',
    (tester) async {
      final storage = InMemoryConnectionStorage(_pairing);
      final container = await _pumpApp(tester, storage: storage);
      await _openSettings(tester, container);

      await tester.tap(find.text(SettingsStrings.repairPairing));
      await tester.pumpAndSettle();
      await tester.tap(find.text(SettingsStrings.repairSheetConfirm));
      await tester.pumpAndSettle();

      expect(storage.data, isNull);
      expect(container.read(pairingProvider), isNull);
      expect(_path(container), AppRoutes.pairing);
      expect(find.byType(SettingsScreen), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('"Nggak jadi" tidak mengubah data dan tetap di Pengaturan', (
    tester,
  ) async {
    final storage = InMemoryConnectionStorage(_pairing);
    final container = await _pumpApp(tester, storage: storage);
    await _openSettings(tester, container);

    await tester.tap(find.text(SettingsStrings.repairPairing));
    await tester.pumpAndSettle();
    await tester.tap(find.text(SettingsStrings.repairSheetCancel));
    await tester.pumpAndSettle();

    expect(storage.data, _pairing);
    expect(container.read(pairingProvider), _pairing);
    expect(find.byType(SettingsScreen), findsOneWidget);
  });

  testWidgets('clear() gagal: toast muncul dan layar tidak pindah', (
    tester,
  ) async {
    final storage = _FailingClearStorage(_pairing);
    final container = await _pumpApp(tester, storage: storage);
    await _openSettings(tester, container);

    await tester.tap(find.text(SettingsStrings.repairPairing));
    await tester.pumpAndSettle();
    await tester.tap(find.text(SettingsStrings.repairSheetConfirm));
    await tester.pumpAndSettle();

    expect(find.text(RemoteStrings.toastCommandFailed), findsOneWidget);
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(storage.data, _pairing);
    expect(container.read(pairingProvider), _pairing);
  });

  testWidgets('clear() menghapus lastPowerCommand juga', (tester) async {
    final storage = InMemoryConnectionStorage(_pairing);
    final container = await _pumpApp(tester, storage: storage);
    await _openSettings(tester, container);

    await tester.tap(find.text(SettingsStrings.repairPairing));
    await tester.pumpAndSettle();
    await tester.tap(find.text(SettingsStrings.repairSheetConfirm));
    await tester.pumpAndSettle();

    expect(container.read(lastPowerCommandProvider), isNull);
    expect(
      container.read(connectionControllerProvider).phase,
      isNot(ConnectionPhase.tokenRejected),
    );
  });
}
