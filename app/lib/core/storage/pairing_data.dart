/// Data sambungan ke laptop hasil pairing.
///
/// [token] tidak pernah ikut di [toString] supaya tidak bocor ke log.
/// [agentId] bersifat publik; null berarti pairing lama (sebelum M7).
final class PairingData {
  const PairingData({
    required this.host,
    required this.port,
    required this.token,
    required this.laptopName,
    this.agentId,
  });

  final String host;
  final int port;
  final String token;
  final String laptopName;

  /// 32 hex huruf kecil (data-design §3). Null = belum terisi (legacy).
  final String? agentId;

  @override
  bool operator ==(Object other) =>
      other is PairingData &&
      other.host == host &&
      other.port == port &&
      other.token == token &&
      other.laptopName == laptopName &&
      other.agentId == agentId;

  @override
  int get hashCode => Object.hash(host, port, token, laptopName, agentId);

  @override
  String toString() =>
      'PairingData(host: $host, port: $port, token: ***, laptopName: $laptopName, '
      'agentId: $agentId)';
}
