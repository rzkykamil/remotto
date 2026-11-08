import '../../../core/network/agent_http_client.dart';
import '../../../core/network/agent_status.dart';
import '../../../core/network/api_failure.dart';
import '../../../core/storage/pairing_data.dart';
import '../../../core/theme/tokens.g.dart';
import 'power_repository.dart';

/// `/power` endpoints over HTTP to the paired laptop.
///
/// [readPairing] is called on every command, so a new pairing (or a cleared
/// one) applies to the next command without rebuilding the repository.
///
/// Never retries. Schedule and cancel are not idempotent: a repeated schedule
/// could queue a second command on the laptop, so only the user may repeat them.
/// Failures and logs never include the token.
final class HttpPowerRepository implements PowerRepository {
  HttpPowerRepository(
    this._client,
    this._readPairing, {
    this.timeout = RMotion.commandTimeout,
  });

  final AgentHttpClient _client;
  final PairingData? Function() _readPairing;

  /// Per-request limit for a power command.
  final Duration timeout;

  @override
  Future<Pending> schedule(PowerAction action) async {
    final pairing = _readPairing();
    // No pairing means there is no laptop to reach. This is not an auth
    // failure, so it must not send the app back to pairing.
    if (pairing == null) throw const UnreachableFailure();

    final data = await _client.postPowerSchedule(
      host: pairing.host,
      port: pairing.port,
      token: pairing.token,
      action: action.wire,
      timeout: timeout,
    );
    return parseScheduledPending(data);
  }

  @override
  Future<PowerAction> cancel() async {
    final pairing = _readPairing();
    if (pairing == null) throw const UnreachableFailure();

    final data = await _client.postPowerCancel(
      host: pairing.host,
      port: pairing.port,
      token: pairing.token,
      timeout: timeout,
    );
    return parseCancelledAction(data);
  }
}
