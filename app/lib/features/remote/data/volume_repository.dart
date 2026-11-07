import '../../../core/network/agent_status.dart';

/// Source of the volume commands (`/volume` endpoints, docs/api-spec.md).
///
/// Every method returns the latest [VolumeStatus] from the agent. Failure
/// throws [ApiFailure] (see `api_failure.dart`).
abstract interface class VolumeRepository {
  /// `PUT /volume`. Sets the level and turns mute off (BR-15). Idempotent,
  /// so the caller may retry it once.
  Future<VolumeStatus> setLevel(int level);

  /// `POST /volume/up`. Raises the level by 5 and turns mute off (BR-16).
  /// Not idempotent, so callers must not retry it automatically.
  Future<VolumeStatus> up();

  /// `POST /volume/down`. Lowers the level by 5 and turns mute off (BR-16).
  /// Not idempotent, so callers must not retry it automatically.
  Future<VolumeStatus> down();

  /// `POST /volume/mute`. Sets mute explicitly. Idempotent.
  Future<VolumeStatus> setMuted(bool muted);
}
