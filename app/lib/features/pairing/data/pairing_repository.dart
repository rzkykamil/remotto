import '../../../core/network/agent_status.dart';
import '../domain/pairing_target.dart';

/// Pairing connection test. HTTP implementation in the app; tests use a fake.
abstract interface class PairingRepository {
  /// Reads `GET /status` at [target]. Failure throws `ApiFailure`.
  Future<AgentStatus> testConnection(PairingTarget target);
}
