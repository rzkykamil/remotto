/// QR code source from the camera. The real implementation wraps `mobile_scanner`
/// in the scan screen (the only place that package is imported). Tests use a fake.
abstract interface class QrScannerSource {
  /// Raw value of every code read. Must be a broadcast stream because
  /// the controller subscribes again each time it returns to the scan step.
  ///
  /// Its content is untrusted and must not be logged.
  Stream<String> get codes;
}
