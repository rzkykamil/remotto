import '../domain/pairing_target.dart';

/// Pairing flow step. One `/pairing` route with internal steps.
enum PairingStep {
  /// Q01 intro.
  intro,

  /// Q02 camera permission explanation.
  permission,

  /// Q03 scan QR.
  scan,

  /// Q05 permission permanently denied or restricted.
  permissionBlocked,

  /// Q06 and Q07 manual form.
  manual,

  /// Q08 connection test.
  testing,

  /// Q09 success.
  success,

  /// Q10 laptop unreachable.
  timeout,

  /// Q11 token rejected.
  rejected,

  /// Q12 token rejected when used from another screen.
  expired,
}

/// Connection test step at Q08: laptop found, check token, save connection.
enum PairingTestStep { found, checkToken, save }

/// Origin screen of Q08, used for "Batal" and the back button.
enum PairingTestOrigin { scan, manual }

/// Pairing flow state. Immutable.
final class PairingFlowState {
  const PairingFlowState({
    this.step = PairingStep.intro,
    this.target,
    this.testStep = PairingTestStep.found,
    this.testOrigin = PairingTestOrigin.scan,
    this.qrError,
    this.qrErrorId = 0,
    this.manualError,
    this.manualAddress = '',
    this.manualToken = '',
    this.laptopName,
  });

  final PairingStep step;

  /// Target being tested or last tested. Null before the first test.
  final PairingTarget? target;

  /// Active step at Q08.
  final PairingTestStep testStep;

  final PairingTestOrigin testOrigin;

  /// Reason the last QR was rejected (Q04 banner). Null if there is no banner.
  final PairingInvalidReason? qrError;

  /// Increments on every rejected QR, so the UI can reset the banner timer.
  final int qrErrorId;

  /// Reason the last manual input was rejected (Q07).
  final PairingInvalidReason? manualError;

  /// Initial value of the manual form, filled on "Ubah alamat" or "Batal" from Q08.
  final String manualAddress;
  final String manualToken;

  /// Laptop name from `GET /status`, filled at Q09.
  final String? laptopName;

  static const Object _keep = Object();

  PairingFlowState copyWith({
    PairingStep? step,
    Object? target = _keep,
    PairingTestStep? testStep,
    PairingTestOrigin? testOrigin,
    Object? qrError = _keep,
    int? qrErrorId,
    Object? manualError = _keep,
    String? manualAddress,
    String? manualToken,
    Object? laptopName = _keep,
  }) {
    return PairingFlowState(
      step: step ?? this.step,
      target: identical(target, _keep) ? this.target : target as PairingTarget?,
      testStep: testStep ?? this.testStep,
      testOrigin: testOrigin ?? this.testOrigin,
      qrError: identical(qrError, _keep)
          ? this.qrError
          : qrError as PairingInvalidReason?,
      qrErrorId: qrErrorId ?? this.qrErrorId,
      manualError: identical(manualError, _keep)
          ? this.manualError
          : manualError as PairingInvalidReason?,
      manualAddress: manualAddress ?? this.manualAddress,
      manualToken: manualToken ?? this.manualToken,
      laptopName: identical(laptopName, _keep)
          ? this.laptopName
          : laptopName as String?,
    );
  }
}
