import 'dart:async';

import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:remotto/core/haptics/r_haptics.dart';
import 'package:remotto/core/storage/connection_storage.dart';
import 'package:remotto/core/storage/pairing_data.dart';
import 'package:remotto/features/pairing/data/camera_permission_service.dart';
import 'package:remotto/features/pairing/data/qr_scanner_source.dart';

/// Records the haptic pattern names requested, without real vibration.
final class RecordingHapticSink implements HapticSink {
  final List<String> calls = [];

  @override
  Future<void> light() async => calls.add('light');

  @override
  Future<void> selection() async => calls.add('selection');

  @override
  Future<void> medium() async => calls.add('medium');

  @override
  Future<void> heavy() async => calls.add('heavy');

  @override
  Future<void> vibrate() async => calls.add('vibrate');
}

/// In-memory connection storage for other tests.
final class InMemoryConnectionStorage implements ConnectionStorage {
  InMemoryConnectionStorage([this.data]);

  PairingData? data;

  @override
  Future<PairingData?> read() async => data;

  @override
  Future<void> write(PairingData value) async => data = value;

  @override
  Future<void> clear() async => data = null;
}

/// Camera permission that can be set from tests. [current] is used for status checks;
/// [requestResult] for the "Izinkan kamera" dialog.
final class FakeCameraPermission implements CameraPermissionService {
  FakeCameraPermission({
    this.current = CameraPermission.granted,
    this.requestResult = CameraPermission.granted,
  });

  CameraPermission current;
  CameraPermission requestResult;
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

/// Fake QR source. [emit] imitates the camera reading a code.
final class FakeQrScanner implements QrScannerSource {
  final _controller = StreamController<String>.broadcast();

  @override
  Stream<String> get codes => _controller.stream;

  void emit(String raw) => _controller.add(raw);
}

/// Camera controller without a platform. Does not call the `mobile_scanner` channel.
final class FakeScannerController extends MobileScannerController {
  FakeScannerController() : super(autoStart: false) {
    value = value.copyWith(torchState: TorchState.off);
  }

  @override
  Future<void> start({
    CameraFacing? cameraDirection,
    CameraLensType? cameraLensType,
  }) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> toggleTorch() async {
    value = value.copyWith(
      torchState: value.torchState == TorchState.on
          ? TorchState.off
          : TorchState.on,
    );
  }
}
