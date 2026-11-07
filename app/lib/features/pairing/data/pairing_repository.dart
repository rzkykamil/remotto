import '../../../core/network/agent_status.dart';
import '../domain/pairing_target.dart';

/// Pairing connection test. Mock implementation for now, HTTP in the Integration phase.
abstract interface class PairingRepository {
  /// Reads `GET /status` at [target]. Failure throws `ApiFailure`.
  Future<AgentStatus> testConnection(PairingTarget target);
}
