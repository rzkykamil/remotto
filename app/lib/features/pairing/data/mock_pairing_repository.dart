import '../../../core/connection/mock_status_repository.dart';
import '../../../core/network/agent_status.dart';
import '../../../core/network/api_failure.dart';
import '../domain/pairing_target.dart';
import 'pairing_repository.dart';

/// Host that always times out in the mock.
const mockPairingTimeoutHost = '10.0.0.1';

/// Token that is always rejected (401) in the mock.
final mockPairingRejectedToken = '0' * 64;

/// Laptop name the mock returns for a successful pairing.
const mockPairingLaptopName = 'Laptop-Kamil';

/// Pairing test mock. The result is built as a fake HTTP reply then parsed
/// by the same parser as the later HTTP.
final class MockPairingRepository implements PairingRepository {
  const MockPairingRepository({this.delay = const Duration(milliseconds: 600)});

  /// Simulated delay. Zero in tests.
  final Duration delay;

  @override
  Future<AgentStatus> testConnection(PairingTarget target) async {
    if (delay > Duration.zero) await Future<void>.delayed(delay);

    if (target.host == mockPairingTimeoutHost) {
      throw const TimeoutFailure();
    }

    final reply = target.token == mockPairingRejectedToken
        ? mockErrorReply(401, 'invalid_token')
        : mockStatusOk(name: mockPairingLaptopName);

    return parseStatusResponse(
      reply.statusCode,
      reply.body,
      headers: reply.headers,
    );
  }
}
