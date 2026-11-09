/// Agent default values (data-design §5, technical-spec §4).
abstract final class AgentDefaults {
  static const port = 8765;
}

/// Pairing target that passed validation. Never built from raw data;
/// only via [validateQrPayload] or [validateManualInput].
final class PairingTarget {
  const PairingTarget({
    required this.host,
    required this.port,
    required this.token,
    this.name,
  });

  /// IPv4 in a private or Tailscale range (BR-12).
  final String host;
  final int port;

  /// 64 lowercase hex characters.
  final String token;

  /// Laptop name from the QR (already trimmed). Null for manual input.
  final String? name;
}

/// Reason validation failed. The UI maps this reason to copy in `lib/core/strings/`.
enum PairingInvalidReason {
  tooLarge,
  notJsonObject,
  unsupportedVersion,
  invalidName,
  invalidHost,
  invalidPort,
  invalidToken,
  invalidAddress,
}

sealed class PairingValidation {
  const PairingValidation();
}

final class PairingValid extends PairingValidation {
  const PairingValid(this.target);

  final PairingTarget target;
}

final class PairingInvalid extends PairingValidation {
  const PairingInvalid(this.reason);

  final PairingInvalidReason reason;
}

final _ipv4Pattern = RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$');

/// Parses dotted-decimal IPv4. Returns null if the format is invalid.
/// Octets with leading zeros (e.g. `192.168.01.1`) are rejected as ambiguous.
List<int>? parseIpv4(String input) {
  final match = _ipv4Pattern.firstMatch(input);
  if (match == null) return null;
  final octets = <int>[];
  for (var i = 1; i <= 4; i++) {
    final part = match.group(i)!;
    if (part.length > 1 && part.startsWith('0')) return null;
    final value = int.parse(part);
    if (value > 255) return null;
    octets.add(value);
  }
  return octets;
}

/// Ranges the app may contact (BR-12): 10/8, 172.16/12, 192.168/16, 100.64/10.
bool isAllowedAgentHost(List<int> o) {
  final a = o[0];
  final b = o[1];
  if (a == 10) return true;
  if (a == 172 && b >= 16 && b <= 31) return true;
  if (a == 192 && b == 168) return true;
  if (a == 100 && b >= 64 && b <= 127) return true;
  return false;
}
