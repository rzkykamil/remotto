import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotto/core/haptics/r_haptics.dart';
import 'package:remotto/core/network/agent_status.dart';
import 'package:remotto/core/network/api_failure.dart';
import 'package:remotto/core/network/network_providers.dart';
import 'package:remotto/core/storage/storage_providers.dart';
import 'package:remotto/features/pairing/data/camera_permission_service.dart';
import 'package:remotto/features/pairing/data/pairing_repository.dart';
import 'package:remotto/features/pairing/data/qr_scanner_source.dart';
import 'package:remotto/features/pairing/domain/pairing_target.dart';
import 'package:remotto/features/pairing/state/pairing_flow_controller.dart';
import 'package:remotto/features/pairing/state/pairing_flow_state.dart';

import '../../../support/fakes.dart';

final class FakePermission implements CameraPermissionService {
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

final class FakeScanner implements QrScannerSource {
  final controller = StreamController<String>.broadcast();

  @override
  Stream<String> get codes => controller.stream;
}

/// Repository with behavior that can be set per call.
final class ScriptedRepository implements PairingRepository {
  Future<AgentStatus> Function(PairingTarget target) handler = (_) async =>
      okStatus;
  int calls = 0;

  @override
  Future<AgentStatus> testConnection(PairingTarget target) {
    calls++;
    return handler(target);
  }
}

const okStatus = AgentStatus(
  name: 'Laptop-Kamil',
  version: '1.0.0',
  uptimeSeconds: 0,
  volume: null,
  pending: null,
);

final _token = 'ab' * 32;

String validQr({String host = '192.168.1.20', int port = 8765}) => jsonEncode({
  'v': 1,
  'name': 'Laptop-Kamil',
  'host': host,
  'port': port,
  'token': _token,
});

final class Harness {
  Harness() {
    container = ProviderContainer(
      overrides: [
        connectionStorageProvider.overrideWithValue(storage),
        hapticsProvider.overrideWithValue(
          RHaptics(sink: sink, enabled: () => true),
        ),
        cameraPermissionServiceProvider.overrideWithValue(permission),
        qrScannerSourceProvider.overrideWithValue(scanner),
        pairingRepositoryProvider.overrideWithValue(repo),
        pairingClockProvider.overrideWithValue(() => now),
        pairingStepTimeoutProvider.overrideWithValue(
          const Duration(milliseconds: 20),
        ),
      ],
    );
    addTearDown(() async {
      await scanner.controller.close();
      container.dispose();
    });
  }

  final storage = InMemoryConnectionStorage();
  final sink = RecordingHapticSink();
  final permission = FakePermission();
  final scanner = FakeScanner();
  final repo = ScriptedRepository();
  DateTime now = DateTime(2026, 11, 8, 10);
  late final ProviderContainer container;

  PairingFlowController get flow =>
      container.read(pairingFlowProvider.notifier);
  PairingFlowState get state => container.read(pairingFlowProvider);
  PairingStep get step => state.step;

  /// Gives microtasks and streams a chance to run.
  Future<void> settle() => Future<void>.delayed(Duration.zero);
}

void main() {
  group('izin dan Q01/Q02/Q05', () {
    test('Scan QR dengan izin diberikan langsung ke scan', () async {
      final h = Harness()..permission.current = CameraPermission.granted;
      await h.flow.onScanPressed();
      expect(h.step, PairingStep.scan);
    });

    test('belum ditanya atau ditolak sekali pindah ke Q02', () async {
      final h = Harness()..permission.current = CameraPermission.denied;
      await h.flow.onScanPressed();
      expect(h.step, PairingStep.permission);
    });

    test('ditolak permanen atau dibatasi pindah ke Q05', () async {
      final h = Harness()
        ..permission.current = CameraPermission.permanentlyDenied;
      await h.flow.onScanPressed();
      expect(h.step, PairingStep.permissionBlocked);

      h.permission.current = CameraPermission.restricted;
      await h.flow.onScanPressed();
      expect(h.step, PairingStep.permissionBlocked);
    });

    test('Q02 izin diberikan masuk ke scan', () async {
      final h = Harness();
      await h.flow.onScanPressed();
      h.permission.requestResult = CameraPermission.granted;
      await h.flow.requestCamera();
      expect(h.step, PairingStep.scan);
    });

    test('Q02 ditolak sekali tetap di Q02', () async {
      final h = Harness();
      await h.flow.onScanPressed();
      h.permission.requestResult = CameraPermission.denied;
      await h.flow.requestCamera();
      expect(h.step, PairingStep.permission);
    });

    test('Q02 ditolak permanen pindah ke Q05', () async {
      final h = Harness();
      await h.flow.onScanPressed();
      h.permission.requestResult = CameraPermission.permanentlyDenied;
      await h.flow.requestCamera();
      expect(h.step, PairingStep.permissionBlocked);
    });

    test(
      'Q05 membuka pengaturan dan saat resume masuk scan bila diizinkan',
      () async {
        final h = Harness()
          ..permission.current = CameraPermission.permanentlyDenied;
        await h.flow.onScanPressed();

        await h.flow.openAppSettings();
        expect(h.permission.settingsOpened, 1);

        await h.flow.onResumed();
        expect(h.step, PairingStep.permissionBlocked);

        h.permission.current = CameraPermission.granted;
        await h.flow.onResumed();
        expect(h.step, PairingStep.scan);
      },
    );

    test('resume di luar Q05 tidak mengubah langkah', () async {
      final h = Harness()..permission.current = CameraPermission.granted;
      await h.flow.onResumed();
      expect(h.step, PairingStep.intro);
    });
  });

  group('scan QR', () {
    test(
      'QR valid lolos tes, tersimpan setelah sukses, haptic medium',
      () async {
        final h = Harness()..permission.current = CameraPermission.granted;
        await h.flow.onScanPressed();

        h.scanner.controller.add(validQr());
        await h.settle();

        expect(h.step, PairingStep.success);
        expect(h.state.laptopName, 'Laptop-Kamil');
        expect(h.repo.calls, 1);
        expect(h.storage.data?.host, '192.168.1.20');
        expect(h.storage.data?.laptopName, 'Laptop-Kamil');
        expect(h.sink.calls, contains('medium'));
      },
    );

    test('QR tidak valid menampilkan banner dan tetap di scan', () async {
      final h = Harness()..permission.current = CameraPermission.granted;
      await h.flow.onScanPressed();

      h.scanner.controller.add('bukan json');
      await h.settle();

      expect(h.step, PairingStep.scan);
      expect(h.state.qrError, PairingInvalidReason.notJsonObject);
      expect(h.state.qrErrorId, 1);
      expect(h.repo.calls, 0);
    });

    test('kode sama dalam 2 detik diabaikan, lewat 2 detik diproses', () async {
      final h = Harness()..permission.current = CameraPermission.granted;
      await h.flow.onScanPressed();

      h.scanner.controller.add('bukan json');
      await h.settle();
      h.now = h.now.add(const Duration(seconds: 1));
      h.scanner.controller.add('bukan json');
      await h.settle();
      expect(h.state.qrErrorId, 1);

      h.now = h.now.add(const Duration(milliseconds: 1500));
      h.scanner.controller.add('bukan json');
      await h.settle();
      expect(h.state.qrErrorId, 2);
    });

    test('kode di luar langkah scan diabaikan', () async {
      final h = Harness();
      h.flow.onCodeScanned(validQr());
      await h.settle();
      expect(h.step, PairingStep.intro);
      expect(h.repo.calls, 0);
    });

    test('langganan scanner aktif hanya saat di scan', () async {
      final h = Harness()..permission.current = CameraPermission.granted;
      expect(h.scanner.controller.hasListener, isFalse);

      await h.flow.onScanPressed();
      expect(h.scanner.controller.hasListener, isTrue);

      h.scanner.controller.add(validQr());
      await h.settle();
      expect(h.step, PairingStep.success);
      expect(h.scanner.controller.hasListener, isFalse);
    });

    test('dismissQrError membersihkan banner', () async {
      final h = Harness()..permission.current = CameraPermission.granted;
      await h.flow.onScanPressed();
      h.scanner.controller.add('bukan json');
      await h.settle();

      h.flow.dismissQrError();
      expect(h.state.qrError, isNull);
      expect(h.state.qrErrorId, 1);
    });
  });

  group('tes koneksi', () {
    test('401 pindah ke Q11 dan tidak menyimpan data', () async {
      final h = Harness()
        ..repo.handler = (_) async => throw const UnauthorizedFailure();
      h.flow.openManual();
      await h.flow.submitManual(address: '192.168.1.20', token: _token);
      expect(h.step, PairingStep.rejected);
      expect(h.storage.data, isNull);
      expect(h.sink.calls, contains('vibrate'));
    });

    test('timeout dari repository pindah ke Q10', () async {
      final h = Harness()
        ..repo.handler = (_) async => throw const TimeoutFailure();
      await h.flow.submitManual(address: '192.168.1.20', token: _token);
      expect(h.step, PairingStep.timeout);
      expect(h.storage.data, isNull);
    });

    test('tidak terjangkau pindah ke Q10', () async {
      final h = Harness()
        ..repo.handler = (_) async => throw const UnreachableFailure();
      await h.flow.submitManual(address: '192.168.1.20', token: _token);
      expect(h.step, PairingStep.timeout);
    });

    test('melewati batas langkah pindah ke Q10', () async {
      final h = Harness()
        ..repo.handler = (_) => Completer<AgentStatus>().future;
      await h.flow.submitManual(address: '192.168.1.20', token: _token);
      expect(h.step, PairingStep.timeout);
      expect(h.storage.data, isNull);
    });

    test('Coba lagi dari Q10 mengulang tes dan berhasil', () async {
      final h = Harness()
        ..repo.handler = (_) async => throw const UnreachableFailure();
      await h.flow.submitManual(address: '192.168.1.20', token: _token);
      expect(h.step, PairingStep.timeout);

      h.repo.handler = (_) async => okStatus;
      await h.flow.retryTest();
      expect(h.step, PairingStep.success);
      expect(h.repo.calls, 2);
    });

    test('Ubah alamat membuka manual terisi dengan port non-default', () async {
      final h = Harness()
        ..repo.handler = (_) async => throw const UnreachableFailure();
      await h.flow.submitManual(address: '10.1.2.3:9000', token: _token);
      h.flow.editAddress();

      expect(h.step, PairingStep.manual);
      expect(h.state.manualAddress, '10.1.2.3:9000');
      expect(h.state.manualToken, _token);
    });

    test('Ubah alamat dengan port default hanya menampilkan host', () async {
      final h = Harness()
        ..repo.handler = (_) async => throw const UnreachableFailure();
      await h.flow.submitManual(address: '192.168.1.20', token: _token);
      h.flow.editAddress();
      expect(h.state.manualAddress, '192.168.1.20');
    });

    test('Batal dari Q08 yang berasal dari scan kembali ke scan', () async {
      final h = Harness()
        ..permission.current = CameraPermission.granted
        ..repo.handler = (_) => Completer<AgentStatus>().future;
      await h.flow.onScanPressed();
      h.scanner.controller.add(validQr());
      await h.settle();
      expect(h.step, PairingStep.testing);

      h.flow.cancelTest();
      expect(h.step, PairingStep.scan);
      expect(h.scanner.controller.hasListener, isTrue);
    });

    test('Batal dari Q08 yang berasal dari manual kembali ke manual', () async {
      final h = Harness()
        ..repo.handler = (_) => Completer<AgentStatus>().future;
      h.flow.openManual();
      final pending = h.flow.submitManual(
        address: '192.168.1.20',
        token: _token,
      );
      await h.settle();
      expect(h.step, PairingStep.testing);

      h.flow.cancelTest();
      expect(h.step, PairingStep.manual);
      expect(h.state.manualAddress, '192.168.1.20');
      unawaited(pending);
    });

    test('hasil tes setelah Batal diabaikan dan tidak disimpan', () async {
      final h = Harness();
      final completer = Completer<AgentStatus>();
      h.repo.handler = (_) => completer.future;
      h.permission.current = CameraPermission.granted;
      await h.flow.onScanPressed();
      h.scanner.controller.add(validQr());
      await h.settle();

      h.flow.cancelTest();
      completer.complete(okStatus);
      await h.settle();

      expect(h.step, PairingStep.scan);
      expect(h.storage.data, isNull);
    });

    test('manual dengan format salah tetap di manual dengan error', () async {
      final h = Harness();
      h.flow.openManual();
      await h.flow.submitManual(address: '8.8.8.8', token: _token);
      expect(h.step, PairingStep.manual);
      expect(h.state.manualError, PairingInvalidReason.invalidHost);
      expect(h.repo.calls, 0);
    });
  });

  group('expired, back, reset', () {
    test('showExpired masuk Q12 dan membatalkan tes yang berjalan', () async {
      final h = Harness();
      final completer = Completer<AgentStatus>();
      h.repo.handler = (_) => completer.future;
      final pending = h.flow.submitManual(
        address: '192.168.1.20',
        token: _token,
      );
      await h.settle();

      h.flow.showExpired();
      completer.complete(okStatus);
      await pending;
      expect(h.step, PairingStep.expired);
      expect(h.storage.data, isNull);
    });

    test('back dari intro mengembalikan false supaya app keluar', () {
      final h = Harness();
      expect(h.flow.handleBack(), isFalse);
      expect(h.step, PairingStep.intro);
    });

    test('back dari Q02 dan Q03 kembali ke intro', () async {
      final h = Harness();
      await h.flow.onScanPressed();
      expect(h.flow.handleBack(), isTrue);
      expect(h.step, PairingStep.intro);

      h.permission.current = CameraPermission.granted;
      await h.flow.onScanPressed();
      expect(h.flow.handleBack(), isTrue);
      expect(h.step, PairingStep.intro);
    });

    test('back dari Q10 kembali ke layar asal', () async {
      final h = Harness()
        ..repo.handler = (_) async => throw const UnreachableFailure();
      h.flow.openManual();
      await h.flow.submitManual(address: '192.168.1.20', token: _token);
      expect(h.step, PairingStep.timeout);

      expect(h.flow.handleBack(), isTrue);
      expect(h.step, PairingStep.manual);
    });

    test('back di Q09 tidak mengubah langkah', () async {
      final h = Harness();
      await h.flow.submitManual(address: '192.168.1.20', token: _token);
      expect(h.step, PairingStep.success);
      expect(h.flow.handleBack(), isTrue);
      expect(h.step, PairingStep.success);
    });

    test('reset mengembalikan intro dan membuang state lama', () async {
      final h = Harness();
      h.flow.showExpired();
      h.flow.reset();
      expect(h.state.step, PairingStep.intro);
      expect(h.state.target, isNull);
    });
  });
}
