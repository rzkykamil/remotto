/// Data sambungan ke laptop hasil pairing.
///
/// [token] tidak pernah ikut di [toString] supaya tidak bocor ke log.
final class PairingData {
  const PairingData({
    required this.host,
    required this.port,
    required this.token,
    required this.laptopName,
  });

  final String host;
  final int port;
  final String token;
  final String laptopName;

  @override
  bool operator ==(Object other) =>
      other is PairingData &&
      other.host == host &&
      other.port == port &&
      other.token == token &&
      other.laptopName == laptopName;

  @override
  int get hashCode => Object.hash(host, port, token, laptopName);

  @override
  String toString() =>
      'PairingData(host: $host, port: $port, token: ***, laptopName: $laptopName)';
}
