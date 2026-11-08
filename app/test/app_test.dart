import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotto/app.dart';
import 'package:remotto/core/connection/connection_controller.dart';
import 'package:remotto/core/connection/connection_providers.dart';
import 'package:remotto/core/haptics/r_haptics.dart';
import 'package:remotto/core/network/agent_status.dart';
import 'package:remotto/core/network/network_providers.dart';
import 'package:remotto/core/router/app_router.dart';
import 'package:remotto/core/storage/pairing_data.dart';
import 'package:remotto/core/storage/storage_providers.dart';
import 'package:remotto/core/strings/pairing_strings.dart';
import 'package:remotto/core/strings/strings.dart';
import 'package:remotto/features/pairing/data/camera_permission_service.dart';
import 'package:remotto/features/pairing/data/pairing_repository.dart';
import 'package:remotto/features/pairing/domain/pairing_target.dart';
import 'package:remotto/features/pairing/pairing_screen.dart';
import 'package:remotto/features/pairing/state/pairing_flow_controller.dart';
import 'package:remotto/features/pairing/state/pairing_flow_state.dart';
import 'package:remotto/features/pairing/widgets/qr_viewfinder.dart';
import 'package:remotto/features/pairing/widgets/result_views.dart';
import 'package:remotto/features/pairing/widgets/scan_view.dart';
import 'package:remotto/features/pairing/widgets/testing_view.dart';
import 'package:remotto/features/remote/power/power_providers.dart';
import 'package:remotto/features/remote/remote_screen.dart';
import 'package:remotto/ui/light_backdrop.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_pairing_repository.dart';
import 'support/fake_power_repository.dart';
import 'support/fake_status_repository.dart';
import 'support/fakes.dart';
import 'support/volume_overrides.dart';

/// Scheduler without timers: the Remote poll does not run on its own in this test.
final class _NoopScheduler implements PollScheduler {
  @override
  ScheduledJob every(Duration interval, void Function() tick) => _NoopJob();

  @override
  ScheduledJob after(Duration delay, void Function() callback) => _NoopJob();
}

final class _NoopJob implements ScheduledJob {
  @override
  void cancel() {}
}

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
        statusRepositoryProvider.overrideWithValue(
          FakeStatusRepository([fakeStatusOk()]),
        ),
        pollSchedulerProvider.overrideWithValue(_NoopScheduler()),
        volumeOverride(),
        powerRepositoryProvider.overrideWithValue(FakePowerRepository()),
      ],
      child: const RemottoApp(),
    ),
  );
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(RemottoApp)));
}

Brightness _brightness(WidgetTester tester) =>
    Theme.of(tester.element(find.byType(LightBackdrop))).brightness;

/// Pairing repository that can be held: the connection test waits for [release]
/// before forwarding to the mock. Used so Q08 can be observed.
final class _GateRepository implements PairingRepository {
  final _inner = const FakePairingRepository(delay: Duration.zero);
  Completer<void>? _gate;

  void hold() => _gate = Completer<void>();

  void release() {
    _gate?.complete();
    _gate = null;
  }

  @override
  Future<AgentStatus> testConnection(PairingTarget target) async {
    await _gate?.future;
    return _inner.testConnection(target);
  }
}

final class _FlowEnv {
  _FlowEnv({
    required this.container,
    required this.permission,
    required this.scanner,
    required this.repository,
    required this.storage,
  });

  final ProviderContainer container;
  final FakeCameraPermission permission;
  final FakeQrScanner scanner;
  final _GateRepository repository;
  final InMemoryConnectionStorage storage;

  PairingFlowState get flow => container.read(pairingFlowProvider);

  String get path => container
      .read(routerProvider)
      .routerDelegate
      .currentConfiguration
      .uri
      .path;
}

/// Start the app without pairing data (redirect to `/pairing`, Q01). Camera, permission,
/// connection test, and haptic are all fake. Reduced motion is turned on so
/// `pumpAndSettle` does not wait on the spinning spinner.
Future<_FlowEnv> _pumpFlow(
  WidgetTester tester, {
  CameraPermission permissionStatus = CameraPermission.granted,
}) async {
  tester.view.physicalSize = const Size(412, 892);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

  final prefs = (await tester.runAsync(() async {
    SharedPreferences.setMockInitialValues({});
    return SharedPreferences.getInstance();
  }))!;

  final permission = FakeCameraPermission(current: permissionStatus);
  final scanner = FakeQrScanner();
  final repository = _GateRepository();
  final storage = InMemoryConnectionStorage();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        initialPairingProvider.overrideWithValue(null),
        connectionStorageProvider.overrideWithValue(storage),
        statusRepositoryProvider.overrideWithValue(
          FakeStatusRepository([fakeStatusOk()]),
        ),
        pollSchedulerProvider.overrideWithValue(_NoopScheduler()),
        volumeOverride(),
        powerRepositoryProvider.overrideWithValue(FakePowerRepository()),
        cameraPermissionServiceProvider.overrideWithValue(permission),
        qrScannerSourceProvider.overrideWithValue(scanner),
        mobileScannerControllerProvider.overrideWithValue(
          FakeScannerController(),
        ),
        pairingRepositoryProvider.overrideWithValue(repository),
        hapticSinkProvider.overrideWithValue(RecordingHapticSink()),
      ],
      child: const RemottoApp(),
    ),
  );
  await tester.pumpAndSettle();

  return _FlowEnv(
    container: ProviderScope.containerOf(
      tester.element(find.byType(RemottoApp)),
    ),
    permission: permission,
    scanner: scanner,
    repository: repository,
    storage: storage,
  );
}

Future<void> _tap(WidgetTester tester, String label) async {
  await tester.tap(find.bySemanticsLabel(label));
  await tester.pumpAndSettle();
}

/// Fill the manual form (Q06): address in field 0, token in field 1.
Future<void> _fillManual(
  WidgetTester tester, {
  required String address,
  required String token,
}) async {
  await tester.enterText(find.byType(EditableText).at(0), address);
  await tester.enterText(find.byType(EditableText).at(1), token);
  await tester.pumpAndSettle();
}

/// Valid QR with host 192.168.1.20 and a token of 64 letter a.
const _validToken =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _validQr =
    '{"v":1,"name":"Laptop-Kamil","host":"192.168.1.20","port":8765,'
    '"token":"$_validToken"}';

void main() {
  testWidgets('RemottoApp render dengan latar, layar Remote tampil', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.byType(LightBackdrop), findsOneWidget);
    expect(find.byType(RemoteScreen), findsOneWidget);
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

  group('alur pairing penuh (Q01 -> Q09 -> /remote)', () {
    testWidgets('tanpa pairing: app mulai di Q01', (tester) async {
      final env = await _pumpFlow(tester);

      expect(env.path, AppRoutes.pairing);
      expect(find.byType(PairingScreen), findsOneWidget);
      expect(find.text(PairingStrings.introTagline), findsOneWidget);
      expect(find.byType(RemoteScreen), findsNothing);
    });

    testWidgets('scan QR valid: Q03 -> Q08 -> Q09 -> Mulai pakai ke /remote', (
      tester,
    ) async {
      final env = await _pumpFlow(tester);
      env.repository.hold();

      await _tap(tester, PairingStrings.scanQr);
      expect(find.byType(ScanView), findsOneWidget);
      expect(find.byType(QrViewfinder), findsOneWidget);

      env.scanner.emit(_validQr);
      await tester.pumpAndSettle();
      expect(find.byType(TestingView), findsOneWidget);
      expect(env.flow.step, PairingStep.testing);
      expect(
        env.storage.data,
        isNull,
        reason: 'sambungan baru belum disimpan sebelum tes sukses',
      );

      env.repository.release();
      await tester.pumpAndSettle();
      expect(find.byType(SuccessView), findsOneWidget);
      expect(
        find.text(PairingStrings.successTitle(fakePairingLaptopName)),
        findsOneWidget,
      );

      await _tap(tester, PairingStrings.successStart);

      expect(env.path, AppRoutes.remote);
      expect(find.byType(RemoteScreen), findsOneWidget);
      expect(
        env.storage.data,
        const PairingData(
          host: '192.168.1.20',
          port: 8765,
          token: _validToken,
          laptopName: fakePairingLaptopName,
        ),
      );
    });

    testWidgets('jalur manual: Q01 -> Q06 -> Q08 -> Q09 -> /remote', (
      tester,
    ) async {
      final env = await _pumpFlow(tester);

      await _tap(tester, PairingStrings.manualLink);
      expect(env.flow.step, PairingStep.manual);

      await _fillManual(
        tester,
        address: '192.168.1.20:8765',
        token: _validToken,
      );
      await _tap(tester, PairingStrings.connect);

      expect(find.byType(SuccessView), findsOneWidget);
      await _tap(tester, PairingStrings.successStart);

      expect(env.path, AppRoutes.remote);
      expect(env.storage.data?.host, '192.168.1.20');
      expect(env.storage.data?.laptopName, fakePairingLaptopName);
    });

    testWidgets('Q10: laptop tidak terjangkau, data tidak disimpan', (
      tester,
    ) async {
      final env = await _pumpFlow(tester);

      await _tap(tester, PairingStrings.manualLink);
      await _fillManual(tester, address: '10.0.0.1', token: _validToken);
      await _tap(tester, PairingStrings.connect);

      expect(find.byType(TimeoutView), findsOneWidget);
      expect(find.text(PairingStrings.timeoutTitle), findsOneWidget);
      expect(env.storage.data, isNull);
      expect(env.path, AppRoutes.pairing);
    });

    testWidgets('Q11: token ditolak (401), data tidak disimpan', (
      tester,
    ) async {
      final env = await _pumpFlow(tester);

      await _tap(tester, PairingStrings.manualLink);
      await _fillManual(tester, address: '192.168.1.20', token: '0' * 64);
      await _tap(tester, PairingStrings.connect);

      expect(find.byType(RejectedView), findsOneWidget);
      expect(find.text(PairingStrings.rejectedTitle), findsOneWidget);
      expect(env.storage.data, isNull);
    });

    testWidgets('Q01 dengan izin ditolak permanen langsung ke Q05', (
      tester,
    ) async {
      final env = await _pumpFlow(
        tester,
        permissionStatus: CameraPermission.permanentlyDenied,
      );

      await _tap(tester, PairingStrings.scanQr);

      expect(env.flow.step, PairingStep.permissionBlocked);
      expect(find.text(PairingStrings.deniedTitle), findsOneWidget);
    });
  });
}
