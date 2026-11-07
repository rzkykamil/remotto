import '../../../core/network/agent_http_client.dart';
import '../../../core/network/agent_status.dart';
import '../../../core/theme/r_behavior.dart';
import '../domain/pairing_target.dart';
import 'pairing_repository.dart';

/// Pairing connection test over HTTP. Uses the host, port, and token from the
/// target the user entered, not from saved pairing data.
final class HttpPairingRepository implements PairingRepository {
  HttpPairingRepository(this._client, {this.timeout = RBehavior.stepTimeout});

  final AgentHttpClient _client;

  /// Limit for one pairing test step.
  final Duration timeout;

  @override
  Future<AgentStatus> testConnection(PairingTarget target) {
    return _client.getStatus(
      host: target.host,
      port: target.port,
      token: target.token,
      timeout: timeout,
    );
  }
}
