/// An agent found on the local network, already validated by
/// `parseCandidate` (discovery_candidate.dart). Not yet verified with
/// `GET /status`; the caller must do that before trusting it.
final class DiscoveredAgent {
  const DiscoveredAgent({
    required this.agentId,
    required this.host,
    required this.port,
    this.name,
  });

  /// 32 lowercase hex characters (public identifier, not a secret).
  final String agentId;

  /// IPv4 in a private range (BR-12).
  final String host;
  final int port;

  /// Laptop name from TXT, informational only. Null when absent.
  final String? name;
}

/// Finds agents advertising `_remotto._tcp` on the local network.
/// Implementations must not perform any I/O in their constructors.
abstract interface class AgentDiscovery {
  /// Collects announcements for [timeout] and returns the valid ones.
  /// Any failure yields an empty list; it never throws.
  Future<List<DiscoveredAgent>> find({required Duration timeout});
}
