import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:remotto/core/haptics/r_haptics.dart';
import 'package:remotto/core/network/agent_status.dart';
import 'package:remotto/core/network/network_providers.dart';
import 'package:remotto/core/storage/storage_providers.dart';
import 'package:remotto/core/strings/pairing_strings.dart';
import 'package:remotto/core/theme/r_behavior.dart';
import 'package:remotto/features/pairing/data/camera_permission_service.dart';
import 'package:remotto/features/pairing/data/pairing_repository.dart';
import 'package:remotto/features/pairing/data/qr_scanner_source.dart';
import 'package:remotto/features/pairing/domain/pairing_target.dart';
import 'package:remotto/features/pairing/state/pairing_flow_controller.dart';
import 'package:remotto/features/pairing/state/pairing_flow_state.dart';
import 'package:remotto/features/pairing/widgets/qr_viewfinder.dart';
import 'package:remotto/features/pairing/widgets/scan_view.dart';

import '../../../support/fakes.dart';
import '../../../support/test_app.dart';

final class _FakePermission implements CameraPermissionService {
  CameraPermission current = CameraPermission.granted;

  @override
  Future<CameraPermission> status() async => current;

  @override
  Future<CameraPermission> request() async => current;

  @override
  Future<bool> openSettings() async => true;
}

final class _FakeScanner implements QrScannerSource {
  final controller = StreamController<String>.broadcast();

  @override
  Stream<String> get codes => controller.stream;
}

/// Controller without a platform. Start can be made to fail, the flashlight can be tested.
final class _FakeController extends MobileScannerController {
  _FakeController({this.startError}) : super(autoStart: false) {
    value = value.copyWith(torchState: TorchState.off);
  }

  MobileScannerException? startError;
  int starts = 0;
  int stops = 0;
  int torchToggles = 0;

  @override
  Future<void> start({
    CameraFacing? cameraDirection,
    CameraLensType? cameraLensType,
  }) async {
    starts++;
    final error = startError;
    if (error != null) throw error;
  }

  @override
  Future<void> stop() async {
    stops++;
  }

  @override
  Future<void> toggleTorch() async {
    torchToggles++;
    value = value.copyWith(
      torchState: value.torchState == TorchState.on
          ? TorchState.off
          : TorchState.on,
    );
  }
}

/// Test is held until [complete] is called, so the Q08 step can be observed.
final class _HoldRepository implements PairingRepository {
  final _completer = Completer<AgentStatus>();

  void complete() => _completer.complete(_status);

  @override
  Future<AgentStatus> testConnection(PairingTarget target) => _completer.future;
}

const _status = AgentStatus(
  name: 'Laptop-Kamil',
  version: '1.0.0',
  uptimeSeconds: 0,
  volume: null,
  pending: null,
);

const _validQr =
    '{"v":1,"name":"Laptop-Kamil","host":"192.168.1.20","port":8765,'
    '"token":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}';

final class _Harness {
  _Harness({
    required this.controller,
    required this.scanner,
    required this.permission,
    required this.sink,
    required this.repository,
  });

  final _FakeController controller;
  final _FakeScanner scanner;
  final _FakePermission permission;
  final RecordingHapticSink sink;
  final _HoldRepository repository;
}

Future<_Harness> _pump(
  WidgetTester tester, {
  MobileScannerException? startError,
}) async {
  final controller = _FakeController(startError: startError);
  final scanner = _FakeScanner();
  final permission = _FakePermission();
  final sink = RecordingHapticSink();
  final repository = _HoldRepository();
  final overrides = <Override>[
    mobileScannerControllerProvider.overrideWithValue(controller),
    qrScannerSourceProvider.overrideWithValue(scanner),
    cameraPermissionServiceProvider.overrideWithValue(permission),
    hapticsProvider.overrideWithValue(
      RHaptics(sink: sink, enabled: () => true),
    ),
    pairingRepositoryProvider.overrideWithValue(repository),
    connectionStorageProvider.overrideWithValue(InMemoryConnectionStorage()),
  ];

  await pumpApp(
    tester,
    const SizedBox.expand(child: ScanView()),
    overrides: overrides,
    dark: true,
  );

  return _Harness(
    controller: controller,
    scanner: scanner,
    permission: permission,
    sink: sink,
    repository: repository,
  );
}

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(ScanView)));

/// Enters the scan step via the normal path (permission already granted).
Future<void> _enterScan(WidgetTester tester) async {
  await _container(tester).read(pairingFlowProvider.notifier).onScanPressed();
  await tester.pump();
}

void main() {
  group('ScanView (Q03, Q04)', () {
    testWidgets('shows hint, back, torch and manual link', (tester) async {
      await _pump(tester);

      expect(find.text(PairingStrings.scanHint), findsOneWidget);
      expect(find.bySemanticsLabel(PairingStrings.scanBack), findsOneWidget);
      expect(find.bySemanticsLabel(PairingStrings.scanTorch), findsOneWidget);
      expect(find.text(PairingStrings.manualLink), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('starts the camera and stops it when disposed', (tester) async {
      final h = await _pump(tester);
      expect(h.controller.starts, 1);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(h.controller.stops, 1);
    });

    testWidgets('invalid QR shows banner and hides it after 3 s (Q04)', (
      tester,
    ) async {
      final h = await _pump(tester);
      await _enterScan(tester);

      h.scanner.controller.add('bukan-remotto');
      // Stream events are processed after the first frame, so a second pump is needed.
      await tester.pump();
      await tester.pump();

      expect(find.text(PairingStrings.scanInvalidBanner), findsOneWidget);

      await tester.pump(RBehavior.qrErrorBanner);
      await tester.pump();

      expect(find.text(PairingStrings.scanInvalidBanner), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('valid QR moves to connection test (Q08)', (tester) async {
      final h = await _pump(tester);
      await _enterScan(tester);

      h.scanner.controller.add(_validQr);
      await tester.pump();

      expect(
        _container(tester).read(pairingFlowProvider).step,
        PairingStep.testing,
      );
      expect(h.sink.calls, contains('medium'));

      // Finish the test so the step timer is not left behind.
      h.repository.complete();
      await tester.pump();
    });

    testWidgets('back returns to intro (Q01)', (tester) async {
      await _pump(tester);
      await _enterScan(tester);

      await tester.tap(find.bySemanticsLabel(PairingStrings.scanBack));
      await tester.pump();

      expect(
        _container(tester).read(pairingFlowProvider).step,
        PairingStep.intro,
      );
    });

    testWidgets('"Isi manual" opens the manual form (Q06)', (tester) async {
      await _pump(tester);
      await _enterScan(tester);

      await tester.tap(find.text(PairingStrings.manualLink));
      await tester.pump();

      expect(
        _container(tester).read(pairingFlowProvider).step,
        PairingStep.manual,
      );
    });

    testWidgets('torch key toggles the torch', (tester) async {
      final h = await _pump(tester);
      await _enterScan(tester);

      await tester.tap(find.bySemanticsLabel(PairingStrings.scanTorch));
      await tester.pump();

      expect(h.controller.torchToggles, 1);
      expect(h.controller.value.torchState, TorchState.on);
    });

    testWidgets('permission denied at start routes to Q02', (tester) async {
      final error = const MobileScannerException(
        errorCode: MobileScannerErrorCode.permissionDenied,
      );
      final h = await _pump(tester, startError: error);
      h.permission.current = CameraPermission.denied;

      // Start fails when the view appears; the flow checks permission and moves to Q02.
      await _container(tester)
          .read(pairingFlowProvider.notifier)
          .onScanPressed();
      await tester.pump();

      expect(
        _container(tester).read(pairingFlowProvider).step,
        PairingStep.permission,
      );
    });
  });
}
