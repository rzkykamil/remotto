import '../../../core/network/agent_http_client.dart';
import '../../../core/network/agent_status.dart';
import '../../../core/network/api_failure.dart';
import '../../../core/storage/pairing_data.dart';
import '../../../core/theme/tokens.g.dart';
import 'volume_repository.dart';

/// `/volume` endpoints over HTTP to the paired laptop.
///
/// [readPairing] is called on every command, so a new pairing (or a cleared
/// one) applies to the next command without rebuilding the repository.
///
/// Never retries here. The retry lives in the state layer: VolumeSender retries
/// the PUT once and VolumeController retries the mute once. Repeating it in
/// this layer would double the retries.
final class HttpVolumeRepository implements VolumeRepository {
  HttpVolumeRepository(
    this._client,
    this._readPairing, {
    this.timeout = RMotion.commandTimeout,
  });

  final AgentHttpClient _client;
  final PairingData? Function() _readPairing;

  /// Per-request limit for a volume command.
  final Duration timeout;

  @override
  Future<VolumeStatus> setLevel(int level) async {
    final pairing = _readPairing();
    // No pairing means there is no laptop to reach. This is not an auth
    // failure, so it must not send the app back to pairing.
    if (pairing == null) throw const UnreachableFailure();

    return _client.putVolume(
      host: pairing.host,
      port: pairing.port,
      token: pairing.token,
      level: level,
      timeout: timeout,
    );
  }

  @override
  Future<VolumeStatus> up() async {
    final pairing = _readPairing();
    if (pairing == null) throw const UnreachableFailure();

    return _client.postVolumeStep(
      host: pairing.host,
      port: pairing.port,
      token: pairing.token,
      direction: 'up',
      timeout: timeout,
    );
  }

  @override
  Future<VolumeStatus> down() async {
    final pairing = _readPairing();
    if (pairing == null) throw const UnreachableFailure();

    return _client.postVolumeStep(
      host: pairing.host,
      port: pairing.port,
      token: pairing.token,
      direction: 'down',
      timeout: timeout,
    );
  }

  @override
  Future<VolumeStatus> setMuted(bool muted) async {
    final pairing = _readPairing();
    if (pairing == null) throw const UnreachableFailure();

    return _client.postVolumeMute(
      host: pairing.host,
      port: pairing.port,
      token: pairing.token,
      muted: muted,
      timeout: timeout,
    );
  }
}
