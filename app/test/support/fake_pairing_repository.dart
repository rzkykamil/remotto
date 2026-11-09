import 'package:remotto/core/network/agent_status.dart';
import 'package:remotto/core/network/api_failure.dart';
import 'package:remotto/features/pairing/data/pairing_repository.dart';
import 'package:remotto/features/pairing/domain/pairing_target.dart';

import 'fake_status_repository.dart';

/// Host that always times out in the fake.
const fakePairingTimeoutHost = '10.0.0.1';

/// Token that is always rejected (401) in the fake.
final fakePairingRejectedToken = '0' * 64;

/// Laptop name the fake returns for a successful pairing.
const fakePairingLaptopName = 'Laptop-Kamil';

/// Pairing test fake. The result is built as a fake HTTP reply then parsed
/// by the same parser as the HTTP path.
final class FakePairingRepository implements PairingRepository {
  const FakePairingRepository({this.delay = const Duration(milliseconds: 600)});

  /// Simulated delay. Zero in tests.
  final Duration delay;

  @override
  Future<AgentStatus> testConnection(PairingTarget target) async {
    if (delay > Duration.zero) await Future<void>.delayed(delay);

    if (target.host == fakePairingTimeoutHost) {
      throw const TimeoutFailure();
    }

    final reply = target.token == fakePairingRejectedToken
        ? fakeErrorReply(401, 'invalid_token')
        : fakeStatusOk(name: fakePairingLaptopName);

    return parseStatusResponse(
      reply.statusCode,
      reply.body,
      headers: reply.headers,
    );
  }
}
