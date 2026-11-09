import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:remotto/core/haptics/r_haptics.dart';
import 'package:remotto/core/strings/pairing_strings.dart';
import 'package:remotto/core/storage/app_preferences.dart';
import 'package:remotto/core/storage/storage_providers.dart';
import 'package:remotto/features/pairing/data/camera_permission_service.dart';
import 'package:remotto/features/pairing/data/qr_scanner_source.dart';
import 'package:remotto/features/pairing/pairing_screen.dart';
import 'package:remotto/features/pairing/state/pairing_flow_controller.dart';
import 'package:remotto/features/pairing/state/pairing_flow_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fakes.dart';
import '../../support/test_app.dart';

final class _FakePermission implements CameraPermissionService {
  CameraPermission current = CameraPermission.denied;
  CameraPermission requestResult = CameraPermission.granted;
  int settingsOpened = 0;

  @override
  Future<CameraPermission> status() async => current;

  @override
  Future<CameraPermission> request() async {
    current = requestResult;
    return requestResult;
  }

  @override
  Future<bool> openSettings() async {
    settingsOpened++;
    return true;
  }
}

final class _FakeScanner implements QrScannerSource {
  final _controller = StreamController<String>.broadcast();

  @override
  Stream<String> get codes => _controller.stream;
}

Future<({_FakePermission permission, List<Override> overrides})>
_setup() async {
  SharedPreferences.setMockInitialValues({
    AppPreferences.keyHapticEnabled: true,
  });
  final prefs = await SharedPreferences.getInstance();
  final permission = _FakePermission();
  return (
    permission: permission,
    overrides: [
      hapticSinkProvider.overrideWithValue(RecordingHapticSink()),
      sharedPreferencesProvider.overrideWithValue(prefs),
      cameraPermissionServiceProvider.overrideWithValue(permission),
      qrScannerSourceProvider.overrideWithValue(_FakeScanner()),
    ],
  );
}

PairingFlowState _flow(WidgetTester tester) {
  final container = ProviderScope.containerOf(
    tester.element(find.byType(PairingScreen)),
  );
  return container.read(pairingFlowProvider);
}

Future<void> _tap(WidgetTester tester, String label) async {
  await tester.tap(find.bySemanticsLabel(label));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Q01 shows intro copy, Scan QR and Isi manual', (tester) async {
    final setup = await _setup();
    await pumpApp(tester, const PairingScreen(), overrides: setup.overrides);

    expect(find.text(PairingStrings.introTagline), findsOneWidget);
    expect(find.text(PairingStrings.introStep1), findsOneWidget);
    expect(find.text(PairingStrings.introStep2), findsOneWidget);
    expect(find.text(PairingStrings.introStep3), findsOneWidget);
    expect(find.text(PairingStrings.scanQr), findsOneWidget);
    expect(find.text(PairingStrings.manualLink), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Scan QR with undecided permission goes to Q02', (tester) async {
    final setup = await _setup();
    await pumpApp(tester, const PairingScreen(), overrides: setup.overrides);

    await _tap(tester, PairingStrings.scanQr);

    expect(_flow(tester).step, PairingStep.permission);
    expect(find.text(PairingStrings.permTitle), findsOneWidget);
    expect(find.text(PairingStrings.permBody), findsOneWidget);
  });

  testWidgets('Scan QR with permanently denied permission goes to Q05', (
    tester,
  ) async {
    final setup = await _setup();
    setup.permission.current = CameraPermission.permanentlyDenied;
    await pumpApp(tester, const PairingScreen(), overrides: setup.overrides);

    await _tap(tester, PairingStrings.scanQr);

    expect(_flow(tester).step, PairingStep.permissionBlocked);
    expect(find.text(PairingStrings.deniedTitle), findsOneWidget);
    expect(find.text(PairingStrings.deniedOpenSettings), findsOneWidget);
  });

  testWidgets('Q02 Izinkan kamera granted moves to scan', (tester) async {
    final setup = await _setup();
    await pumpApp(tester, const PairingScreen(), overrides: setup.overrides);
    await _tap(tester, PairingStrings.scanQr);

    await _tap(tester, PairingStrings.permAllow);

    expect(_flow(tester).step, PairingStep.scan);
  });

  testWidgets('Q02 Izinkan kamera denied again stays on Q02', (tester) async {
    final setup = await _setup();
    setup.permission.requestResult = CameraPermission.denied;
    await pumpApp(tester, const PairingScreen(), overrides: setup.overrides);
    await _tap(tester, PairingStrings.scanQr);

    await _tap(tester, PairingStrings.permAllow);

    expect(_flow(tester).step, PairingStep.permission);
  });

  testWidgets('Q05 Buka pengaturan HP opens app settings', (tester) async {
    final setup = await _setup();
    setup.permission.current = CameraPermission.permanentlyDenied;
    await pumpApp(tester, const PairingScreen(), overrides: setup.overrides);
    await _tap(tester, PairingStrings.scanQr);

    await _tap(tester, PairingStrings.deniedOpenSettings);

    expect(setup.permission.settingsOpened, 1);
  });

  testWidgets('Q05 returns to scan on resume once permission is granted', (
    tester,
  ) async {
    final setup = await _setup();
    setup.permission.current = CameraPermission.permanentlyDenied;
    await pumpApp(tester, const PairingScreen(), overrides: setup.overrides);
    await _tap(tester, PairingStrings.scanQr);

    setup.permission.current = CameraPermission.granted;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(_flow(tester).step, PairingStep.scan);
  });

  testWidgets('Isi manual from Q01 opens the manual step', (tester) async {
    final setup = await _setup();
    await pumpApp(tester, const PairingScreen(), overrides: setup.overrides);

    await _tap(tester, PairingStrings.manualLink);

    expect(_flow(tester).step, PairingStep.manual);
  });

  testWidgets('back on Q02 returns to Q01', (tester) async {
    final setup = await _setup();
    await pumpApp(tester, const PairingScreen(), overrides: setup.overrides);
    await _tap(tester, PairingStrings.scanQr);
    expect(_flow(tester).step, PairingStep.permission);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(_flow(tester).step, PairingStep.intro);
    expect(find.text(PairingStrings.introTagline), findsOneWidget);
  });

  testWidgets('back on Q01 asks the system to leave the app', (tester) async {
    final setup = await _setup();
    final calls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        calls.add(call.method);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await pumpApp(tester, const PairingScreen(), overrides: setup.overrides);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(calls, contains('SystemNavigator.pop'));
  });
}
