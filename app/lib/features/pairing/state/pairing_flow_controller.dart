import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/haptics/r_haptics.dart';
import '../../../core/network/api_failure.dart';
import '../../../core/network/network_providers.dart';
import '../../../core/storage/pairing_data.dart';
import '../../../core/storage/storage_providers.dart';
import '../../../core/theme/r_behavior.dart';
import '../data/camera_permission_service.dart';
import '../data/qr_scanner_source.dart';
import '../domain/manual_input_validator.dart';
import '../domain/pairing_target.dart';
import '../domain/qr_payload_validator.dart';
import 'pairing_flow_state.dart';

/// System clock. Overridden in tests so the 2 second window can be tested.
final pairingClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

/// Limit for each connection test step. Overridden in tests with a small value.
final pairingStepTimeoutProvider = Provider<Duration>(
  (ref) => RBehavior.stepTimeout,
);

final cameraPermissionServiceProvider = Provider<CameraPermissionService>(
  (ref) => const PermissionHandlerCameraService(),
);

/// Must be overridden with the `mobile_scanner` implementation (scan screen, T11).
final qrScannerSourceProvider = Provider<QrScannerSource>(
  (ref) => throw UnimplementedError('override qrScannerSourceProvider'),
);

final pairingFlowProvider =
    NotifierProvider<PairingFlowController, PairingFlowState>(
      PairingFlowController.new,
    );

/// Manages the pairing flow Q01 to Q12. Not autoDispose so state remains
/// when the router moves the user to `/pairing` from outside the screen.
/// Re-pairing from Settings calls [PairingFlowController.reset].
final class PairingFlowController extends Notifier<PairingFlowState> {
  /// Test attempt number. Results of old attempts are ignored.
  int _attempt = 0;

  StreamSubscription<String>? _codes;
  String? _lastCode;
  DateTime? _lastCodeAt;

  @override
  PairingFlowState build() {
    ref.onDispose(_stopScanning);
    return const PairingFlowState();
  }

  /// Q01 "Scan QR", and "Scan ulang QR" from Q10, Q11, Q12. Checks permission first.
  Future<void> onScanPressed() async {
    final permission = await ref.read(cameraPermissionServiceProvider).status();
    _routeByPermission(permission);
  }

  /// Q02 "Izinkan kamera". Shows the OS dialog.
  Future<void> requestCamera() async {
    final permission = await ref
        .read(cameraPermissionServiceProvider)
        .request();
    _routeByPermission(permission);
  }

  /// Q05 "Buka pengaturan HP".
  Future<void> openAppSettings() async {
    await ref.read(cameraPermissionServiceProvider).openSettings();
  }

  /// Called when the app becomes active again. At Q05, moves to scan if permission was
  /// granted via settings. Otherwise stays at Q05.
  Future<void> onResumed() async {
    if (state.step != PairingStep.permissionBlocked) return;
    final permission = await ref.read(cameraPermissionServiceProvider).status();
    if (permission == CameraPermission.granted) _enterScan();
  }

  /// QR code from the camera. Only processed at the scan step.
  void onCodeScanned(String raw) {
    if (state.step != PairingStep.scan) return;

    final now = ref.read(pairingClockProvider)();
    final lastAt = _lastCodeAt;
    if (raw == _lastCode &&
        lastAt != null &&
        now.difference(lastAt) < RBehavior.qrDuplicateIgnore) {
      return;
    }
    _lastCode = raw;
    _lastCodeAt = now;

    final result = validateQrPayload(raw);
    switch (result) {
      case PairingInvalid(:final reason):
        _emit(state.copyWith(qrError: reason, qrErrorId: state.qrErrorId + 1));
      case PairingValid(:final target):
        ref.read(hapticsProvider).qrScanned();
        unawaited(_startTest(target, PairingTestOrigin.scan));
    }
  }

  /// Closes the QR banner after [RBehavior.qrErrorBanner] (scheduled by the UI).
  void dismissQrError() {
    if (state.qrError == null) return;
    _emit(state.copyWith(qrError: null));
  }

  /// Opens the manual form. The initial value is used by "Ubah alamat".
  void openManual({String address = '', String token = ''}) {
    _emit(
      state.copyWith(
        step: PairingStep.manual,
        qrError: null,
        manualError: null,
        manualAddress: address,
        manualToken: token,
      ),
    );
  }

  /// Q06 "Sambungkan". A wrong format stays on the form with [PairingFlowState.manualError].
  Future<void> submitManual({
    required String address,
    required String token,
  }) async {
    final result = validateManualInput(address: address, token: token);
    switch (result) {
      case PairingInvalid(:final reason):
        _emit(state.copyWith(manualError: reason));
      case PairingValid(:final target):
        await _startTest(target, PairingTestOrigin.manual);
    }
  }

  /// Q10 "Coba lagi": rerun the test with the same target.
  Future<void> retryTest() async {
    final target = state.target;
    if (state.step != PairingStep.timeout || target == null) return;
    await _startTest(target, state.testOrigin);
  }

  /// Q10 "Ubah alamat": manual form filled with the last address and token.
  void editAddress() {
    _openManualFromTarget();
  }

  /// Q08 "Batal": return to the origin screen, and a test still running is discarded.
  void cancelTest() {
    if (state.step != PairingStep.testing) return;
    _attempt++;
    _returnToOrigin();
  }

  /// Token rejected when used from another screen (Q12).
  void showExpired() {
    _attempt++;
    _emit(const PairingFlowState(step: PairingStep.expired));
  }

  /// Return to intro and discard old state. Used for re-pairing.
  void reset() {
    _attempt++;
    _emit(const PairingFlowState());
  }

  /// System back button. Returns false if there is no previous step,
  /// so the screen may exit the app.
  bool handleBack() {
    switch (state.step) {
      case PairingStep.intro:
        return false;
      case PairingStep.success:
        // The user is using "Mulai pakai". Back here does nothing.
        return true;
      case PairingStep.testing:
        cancelTest();
        return true;
      case PairingStep.timeout:
      case PairingStep.rejected:
        _returnToOrigin();
        return true;
      case PairingStep.expired:
      case PairingStep.scan:
      case PairingStep.manual:
      case PairingStep.permission:
      case PairingStep.permissionBlocked:
        reset();
        return true;
    }
  }

  void _routeByPermission(CameraPermission permission) {
    switch (permission) {
      case CameraPermission.granted:
        _enterScan();
      case CameraPermission.permanentlyDenied:
      case CameraPermission.restricted:
        _emit(state.copyWith(step: PairingStep.permissionBlocked));
      case CameraPermission.denied:
        _emit(state.copyWith(step: PairingStep.permission));
    }
  }

  void _enterScan() {
    _emit(state.copyWith(step: PairingStep.scan, qrError: null));
  }

  void _returnToOrigin() {
    switch (state.testOrigin) {
      case PairingTestOrigin.scan:
        _enterScan();
      case PairingTestOrigin.manual:
        _openManualFromTarget();
    }
  }

  void _openManualFromTarget() {
    final target = state.target;
    if (target == null) {
      openManual();
      return;
    }
    final address = target.port == AgentDefaults.port
        ? target.host
        : '${target.host}:${target.port}';
    openManual(address: address, token: target.token);
  }

  Future<void> _startTest(
    PairingTarget target,
    PairingTestOrigin origin,
  ) async {
    final attempt = ++_attempt;
    _emit(
      state.copyWith(
        step: PairingStep.testing,
        target: target,
        testStep: PairingTestStep.found,
        testOrigin: origin,
        qrError: null,
        manualError: null,
      ),
    );

    final timeout = ref.read(pairingStepTimeoutProvider);
    try {
      final status = await ref
          .read(pairingRepositoryProvider)
          .testConnection(target)
          .timeout(timeout);
      if (attempt != _attempt) return;

      _emit(state.copyWith(testStep: PairingTestStep.checkToken));
      _emit(state.copyWith(testStep: PairingTestStep.save));

      // The old connection is only replaced after the new pairing succeeds (BR-9).
      await ref
          .read(pairingProvider.notifier)
          .save(
            PairingData(
              host: target.host,
              port: target.port,
              token: target.token,
              laptopName: status.name,
            ),
          );
      if (attempt != _attempt) return;

      _emit(state.copyWith(step: PairingStep.success, laptopName: status.name));
    } on UnauthorizedFailure {
      if (attempt != _attempt) return;
      _fail(PairingStep.rejected);
    } catch (_) {
      // Timeout, agent unreachable, 403/429/500, or save failure.
      // All are shown as Q10.
      if (attempt != _attempt) return;
      _fail(PairingStep.timeout);
    }
  }

  void _fail(PairingStep step) {
    _emit(state.copyWith(step: step));
    ref.read(hapticsProvider).failure();
  }

  /// The only way to change state. Adjusts the scanner subscription: active
  /// only at the scan step.
  void _emit(PairingFlowState next) {
    state = next;
    if (next.step == PairingStep.scan) {
      _codes ??= ref.read(qrScannerSourceProvider).codes.listen(onCodeScanned);
    } else {
      _stopScanning();
    }
  }

  void _stopScanning() {
    _codes?.cancel();
    _codes = null;
  }
}
