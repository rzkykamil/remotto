import 'dart:convert';

import 'pairing_target.dart';

/// QR text size limit in UTF-8 bytes (data-design §5).
const qrPayloadMaxBytes = 256;

final _tokenPattern = RegExp(r'^[0-9a-f]{64}$');

/// Validates pairing QR content as untrusted input (data-design §5).
///
/// Never throws. The QR content is not logged.
PairingValidation validateQrPayload(String raw) {
  if (utf8.encode(raw).length > qrPayloadMaxBytes) {
    return const PairingInvalid(PairingInvalidReason.tooLarge);
  }

  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException {
    return const PairingInvalid(PairingInvalidReason.notJsonObject);
  }
  if (decoded is! Map<String, dynamic>) {
    return const PairingInvalid(PairingInvalidReason.notJsonObject);
  }

  final version = decoded['v'];
  if (version is! int || version != 1) {
    return const PairingInvalid(PairingInvalidReason.unsupportedVersion);
  }

  final rawName = decoded['name'];
  if (rawName is! String) {
    return const PairingInvalid(PairingInvalidReason.invalidName);
  }
  final name = rawName.trim();
  if (name.isEmpty || name.length > 64) {
    return const PairingInvalid(PairingInvalidReason.invalidName);
  }

  final rawHost = decoded['host'];
  if (rawHost is! String) {
    return const PairingInvalid(PairingInvalidReason.invalidHost);
  }
  final octets = parseIpv4(rawHost);
  if (octets == null || !isAllowedAgentHost(octets)) {
    return const PairingInvalid(PairingInvalidReason.invalidHost);
  }

  final port = decoded['port'];
  if (port is! int || port < 1 || port > 65535) {
    return const PairingInvalid(PairingInvalidReason.invalidPort);
  }

  final token = decoded['token'];
  if (token is! String || !_tokenPattern.hasMatch(token)) {
    return const PairingInvalid(PairingInvalidReason.invalidToken);
  }

  return PairingValid(
    PairingTarget(host: rawHost, port: port, token: token, name: name),
  );
}
