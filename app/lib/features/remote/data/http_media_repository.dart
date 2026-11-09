import '../../../core/network/agent_http_client.dart';
import '../../../core/network/api_failure.dart';
import '../../../core/storage/pairing_data.dart';
import '../../../core/theme/tokens.g.dart';
import 'media_repository.dart';

/// `POST /media/{action}` over HTTP to the paired laptop.
///
/// [readPairing] is called on every [send], so a new pairing (or a cleared
/// one) applies to the next command without rebuilding the repository.
/// Never retries: a media command is not idempotent (api-spec, §6).
final class HttpMediaRepository implements MediaRepository {
  HttpMediaRepository(
    this._client,
    this._readPairing, {
    this.timeout = RMotion.commandTimeout,
  });

  final AgentHttpClient _client;
  final PairingData? Function() _readPairing;

  /// Per-request limit for a media command.
  final Duration timeout;

  @override
  Future<void> send(MediaAction action) async {
    final pairing = _readPairing();
    // No pairing means there is no laptop to reach. This is not an auth
    // failure, so it must not send the app back to pairing.
    if (pairing == null) throw const UnreachableFailure();

    return _client.postMedia(
      host: pairing.host,
      port: pairing.port,
      token: pairing.token,
      action: action.wire,
      timeout: timeout,
    );
  }
}
