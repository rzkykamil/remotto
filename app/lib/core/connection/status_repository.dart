import '../network/agent_status.dart';

/// Source of `GET /status`. HTTP implementation in the app; tests use a fake.
abstract interface class StatusRepository {
  /// Failure throws [ApiFailure] (see `api_failure.dart`).
  Future<AgentStatus> fetchStatus();
}
