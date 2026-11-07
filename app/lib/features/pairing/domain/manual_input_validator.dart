import 'pairing_target.dart';

final _tokenPattern = RegExp(r'^[0-9a-f]{64}$');
final _portPattern = RegExp(r'^\d{1,5}$');

/// Validates manual input: an `IPv4[:port]` address (default port [AgentDefaults.port])
/// and a 64 hex character token. The token is trimmed and lowercased first.
///
/// Never throws.
PairingValidation validateManualInput({
  required String address,
  required String token,
}) {
  final parts = address.trim().split(':');
  if (parts.length > 2) {
    return const PairingInvalid(PairingInvalidReason.invalidAddress);
  }

  final host = parts[0];
  final octets = parseIpv4(host);
  if (octets == null) {
    return const PairingInvalid(PairingInvalidReason.invalidAddress);
  }
  if (!isAllowedAgentHost(octets)) {
    return const PairingInvalid(PairingInvalidReason.invalidHost);
  }

  var port = AgentDefaults.port;
  if (parts.length == 2) {
    final rawPort = parts[1];
    if (!_portPattern.hasMatch(rawPort)) {
      return const PairingInvalid(PairingInvalidReason.invalidPort);
    }
    final value = int.parse(rawPort);
    if (value < 1 || value > 65535) {
      return const PairingInvalid(PairingInvalidReason.invalidPort);
    }
    port = value;
  }

  final normalizedToken = token.trim().toLowerCase();
  if (!_tokenPattern.hasMatch(normalizedToken)) {
    return const PairingInvalid(PairingInvalidReason.invalidToken);
  }

  return PairingValid(
    PairingTarget(host: host, port: port, token: normalizedToken),
  );
}
