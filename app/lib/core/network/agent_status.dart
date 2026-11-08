import 'api_failure.dart';

/// Laptop volume from `GET /status` (api-spec, `Volume` object).
final class VolumeStatus {
  const VolumeStatus({required this.level, required this.muted});

  /// Builds a volume from the `Volume` object (api-spec). Shared by `GET /status`
  /// and every `/volume` response. Fields that do not match the contract throw
  /// [ServerFailure].
  factory VolumeStatus.fromData(Map<String, Object?> data) {
    return VolumeStatus(
      level: _requireInt(data, 'level', min: 0, max: 100),
      muted: _requireBool(data, 'muted'),
    );
  }

  /// 0 to 100.
  final int level;
  final bool muted;

  @override
  bool operator ==(Object other) =>
      other is VolumeStatus && other.level == level && other.muted == muted;

  @override
  int get hashCode => Object.hash(level, muted);

  @override
  String toString() => 'VolumeStatus(level: $level, muted: $muted)';
}

/// Active power schedule (api-spec, `Pending` object).
///
/// The app uses [remainingMs] and [delayMs], not [scheduledAt], because the
/// laptop and phone clocks can differ (BR-20). [scheduledAt] is informational only.
final class Pending {
  const Pending({
    required this.action,
    required this.remainingMs,
    required this.delayMs,
    required this.scheduledAt,
  });

  /// `sleep`, `restart`, or `shutdown`.
  final String action;

  /// Remaining delay. 0 means it is being executed.
  final int remainingMs;

  final int delayMs;

  /// RFC 3339, laptop clock.
  final String scheduledAt;

  @override
  bool operator ==(Object other) =>
      other is Pending &&
      other.action == action &&
      other.remainingMs == remainingMs &&
      other.delayMs == delayMs &&
      other.scheduledAt == scheduledAt;

  @override
  int get hashCode => Object.hash(action, remainingMs, delayMs, scheduledAt);

  @override
  String toString() =>
      'Pending(action: $action, remainingMs: $remainingMs, delayMs: $delayMs, '
      'scheduledAt: $scheduledAt)';
}

/// Agent state from `GET /status` (api-spec, Status section).
final class AgentStatus {
  const AgentStatus({
    required this.name,
    required this.version,
    required this.uptimeSeconds,
    required this.volume,
    required this.pending,
  });

  final String name;
  final String version;
  final int uptimeSeconds;

  /// Null if Core Audio is currently failing on the laptop.
  final VolumeStatus? volume;

  /// Null if there is no power schedule.
  final Pending? pending;

  /// Builds a status from the `data` content. Fields that do not match the contract
  /// throw [ServerFailure].
  factory AgentStatus.fromData(Map<String, Object?> data) {
    return AgentStatus(
      name: _requireString(data, 'name'),
      version: _requireString(data, 'version'),
      uptimeSeconds: _requireInt(data, 'uptimeSeconds', min: 0),
      volume: _parseVolume(data),
      pending: _parsePending(data),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AgentStatus &&
      other.name == name &&
      other.version == version &&
      other.uptimeSeconds == uptimeSeconds &&
      other.volume == volume &&
      other.pending == pending;

  @override
  int get hashCode =>
      Object.hash(name, version, uptimeSeconds, volume, pending);

  @override
  String toString() =>
      'AgentStatus(name: $name, version: $version, '
      'uptimeSeconds: $uptimeSeconds, volume: $volume, pending: $pending)';
}

/// Single parser for `GET /status`, used by the later HTTP and the mock.
/// Unwraps the envelope then builds [AgentStatus]. Failure throws [ApiFailure].
AgentStatus parseStatusResponse(
  int statusCode,
  String body, {
  Map<String, String> headers = const {},
}) {
  return AgentStatus.fromData(
    unwrapAgentResponse(statusCode, body, headers: headers),
  );
}

VolumeStatus? _parseVolume(Map<String, Object?> data) {
  _requireKey(data, 'volume');
  final raw = data['volume'];
  if (raw == null) return null;
  return VolumeStatus.fromData(_asMap(raw));
}

Pending? _parsePending(Map<String, Object?> data) {
  _requireKey(data, 'pending');
  final raw = data['pending'];
  if (raw == null) return null;
  final pending = _asMap(raw);
  return Pending(
    action: _requireString(pending, 'action'),
    remainingMs: _requireInt(pending, 'remainingMs', min: 0),
    delayMs: _requireInt(pending, 'delayMs', min: 0),
    scheduledAt: _requireString(pending, 'scheduledAt'),
  );
}

void _requireKey(Map<String, Object?> map, String key) {
  if (!map.containsKey(key)) throw const ServerFailure();
}

Map<String, Object?> _asMap(Object? value) {
  if (value is Map<String, Object?>) return value;
  throw const ServerFailure();
}

String _requireString(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is String) return value;
  throw const ServerFailure();
}

bool _requireBool(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is bool) return value;
  throw const ServerFailure();
}

int _requireInt(
  Map<String, Object?> map,
  String key, {
  int min = -0x7fffffffffffffff,
  int max = 0x7fffffffffffffff,
}) {
  final value = map[key];
  if (value is int && value >= min && value <= max) return value;
  throw const ServerFailure();
}
