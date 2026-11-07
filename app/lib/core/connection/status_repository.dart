import '../network/agent_status.dart';

/// Source of `GET /status`. Mock and HTTP implementations.
abstract interface class StatusRepository {
  /// Failure throws [ApiFailure] (see `api_failure.dart`).
  Future<AgentStatus> fetchStatus();
}
