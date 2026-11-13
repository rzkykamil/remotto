import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotto/core/haptics/r_haptics.dart';
import 'package:remotto/core/network/agent_status.dart';
import 'package:remotto/core/network/network_providers.dart';
import 'package:remotto/core/storage/storage_providers.dart';
import 'package:remotto/features/pairing/data/camera_permission_service.dart';
import 'package:remotto/features/pairing/data/pairing_repository.dart';
import 'package:remotto/features/pairing/data/qr_scanner_source.dart';
import 'package:remotto/features/pairing/domain/pairing_target.dart';
import 'package:remotto/features/pairing/state/pairing_flow_controller.dart';
import 'package:remotto/features/pairing/state/pairing_flow_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/fakes.dart';

const _agentId = 'a3f1c9e0b72d4e85916f0c2d7b4e13a8';
const _otherAgentId = '0123456789abcdef0123456789abcdef';
final _token = 'ab' * 32;

AgentStatus _status({String? agentId}) => AgentStatus(
  name: 'Laptop-Kamil',
  version: '1.0.0',
  uptimeSeconds: 0,
  volume: null,
  pending: null,
  agentId: agentId,
);

/// QR dengan atau tanpa `id` (data-design §5).
String _qr({String? id}) {
  final map = <String, Object?>{
    'v': 1,
    'name': 'Laptop-Kamil',
    'host': '192.168.1.20',
    'port': 8765,
    'token': _token,
  };
  if (id != null) map['id'] = id;
  return jsonEncode(map);
}

final class _Repo implements PairingRepository {
  _Repo(this.status);

  final AgentStatus status;

  @override
  Future<AgentStatus> testConnection(PairingTarget target) async => status;
}

final class _Scanner implements QrScannerSource {
  final controller = StreamController<String>.broadcast();

  @override
  Stream<String> get codes => controller.stream;
}

final class _Granted implements CameraPermissionService {
  @override
  Future<CameraPermission> status() async => CameraPermission.granted;

  @override
  Future<CameraPermission> request() async => CameraPermission.granted;

  @override
  Future<bool> openSettings() async => true;
}

late SharedPreferences _prefs;

final class _Harness {
  _Harness(AgentStatus status) {
    container = ProviderContainer(
      overrides: [
        connectionStorageProvider.overrideWithValue(storage),
        sharedPreferencesProvider.overrideWithValue(_prefs),
        hapticsProvider.overrideWithValue(
          RHaptics(sink: RecordingHapticSink(), enabled: () => true),
        ),
        cameraPermissionServiceProvider.overrideWithValue(_Granted()),
        qrScannerSourceProvider.overrideWithValue(scanner),
        pairingRepositoryProvider.overrideWithValue(_Repo(status)),
        pairingStepTimeoutProvider.overrideWithValue(
          const Duration(milliseconds: 50),
        ),
      ],
    );
    addTearDown(() async {
      await scanner.controller.close();
      container.dispose();
    });
  }

  final storage = InMemoryConnectionStorage();
  final scanner = _Scanner();
  late final ProviderContainer container;

  PairingFlowController get flow =>
      container.read(pairingFlowProvider.notifier);
  PairingStep get step => container.read(pairingFlowProvider).step;

  /// Masuk ke langkah scan lalu memproses satu QR, seperti kamera membacanya.
  Future<void> scanQr(String raw) async {
    await flow.onScanPressed();
    scanner.controller.add(raw);
    await _waitForStep(container, const {
      PairingStep.success,
      PairingStep.timeout,
    });
  }
}

/// Menunggu flow mencapai salah satu [steps], dengan batas waktu.
Future<void> _waitForStep(
  ProviderContainer container,
  Set<PairingStep> steps,
) async {
  final done = Completer<void>();
  final sub = container.listen(pairingFlowProvider, (_, next) {
    if (steps.contains(next.step) && !done.isCompleted) done.complete();
  }, fireImmediately: true);
  addTearDown(sub.close);
  await done.future.timeout(const Duration(seconds: 2));
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    _prefs = await SharedPreferences.getInstance();
  });

  group('PairingFlowController agentId (M7)', () {
    test('QR id sama dengan /status: sukses dan agentId disimpan', () async {
      final h = _Harness(_status(agentId: _agentId));
      await h.scanQr(_qr(id: _agentId));

      expect(h.step, PairingStep.success);
      expect(h.storage.data?.agentId, _agentId);
    });

    test('QR id beda dari /status: Q10, tidak ada yang disimpan', () async {
      final h = _Harness(_status(agentId: _otherAgentId));
      await h.scanQr(_qr(id: _agentId));

      expect(h.step, PairingStep.timeout);
      expect(h.storage.data, isNull);
    });

    test('QR tanpa id memakai agentId dari /status', () async {
      final h = _Harness(_status(agentId: _agentId));
      await h.scanQr(_qr());

      expect(h.step, PairingStep.success);
      expect(h.storage.data?.agentId, _agentId);
    });

    test('input manual (tanpa id) memakai agentId dari /status', () async {
      final h = _Harness(_status(agentId: _agentId));
      await h.flow.submitManual(address: '192.168.1.20', token: _token);

      expect(h.step, PairingStep.success);
      expect(h.storage.data?.agentId, _agentId);
    });

    test(
      'QR tanpa id dan /status tanpa agentId: tersimpan null (legacy)',
      () async {
        final h = _Harness(_status());
        await h.scanQr(_qr());

        expect(h.step, PairingStep.success);
        expect(h.storage.data, isNotNull);
        expect(h.storage.data?.agentId, isNull);
      },
    );
  });
}
