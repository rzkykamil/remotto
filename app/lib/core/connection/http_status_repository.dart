import '../network/agent_http_client.dart';
import '../network/agent_status.dart';
import '../network/api_failure.dart';
import '../storage/pairing_data.dart';
import 'status_repository.dart';

/// `GET /status` over HTTP to the paired laptop.
///
/// [readPairing] is called on every [fetchStatus], so a new pairing (or a
/// cleared one) applies to the next poll without rebuilding the repository.
final class HttpStatusRepository implements StatusRepository {
  HttpStatusRepository(
    this._client,
    this._readPairing, {
    this.timeout = const Duration(seconds: 3),
  });

  final AgentHttpClient _client;
  final PairingData? Function() _readPairing;

  /// Per-request limit for polling (technical-spec §6).
  final Duration timeout;

  @override
  Future<AgentStatus> fetchStatus() async {
    final pairing = _readPairing();
    // No pairing means there is no laptop to reach. This is not an auth
    // failure, so it must not send the app back to pairing.
    if (pairing == null) throw const UnreachableFailure();

    return _client.getStatus(
      host: pairing.host,
      port: pairing.port,
      token: pairing.token,
      timeout: timeout,
    );
  }
}
