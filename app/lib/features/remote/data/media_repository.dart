/// Media commands the agent accepts (`POST /media/{action}`, docs/api-spec.md).
enum MediaAction {
  playPause('play-pause'),
  next('next'),
  prev('prev');

  const MediaAction(this.wire);

  /// Value of `data.action` in the response and the endpoint path segment.
  final String wire;
}

/// Source of the media commands. Mock now, HTTP in the Integrasi phase.
abstract interface class MediaRepository {
  /// Failure throws [ApiFailure] (see `api_failure.dart`).
  /// The media command is not idempotent, so callers must not retry it automatically.
  Future<void> send(MediaAction action);
}
