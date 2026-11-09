import 'dart:convert';

import 'package:remotto/core/network/agent_status.dart';
import 'package:remotto/core/network/api_failure.dart';
import 'package:remotto/features/remote/data/volume_repository.dart';

/// One scripted step of [FakeVolumeRepository].
sealed class FakeVolumeStep {
  const FakeVolumeStep();
}

/// Success. Applies the requested change to the fake state, like the agent does.
final class FakeVolumeOk extends FakeVolumeStep {
  const FakeVolumeOk();
}

/// Fixed HTTP reply. The body goes through the same parsing as the HTTP path.
final class FakeVolumeReply extends FakeVolumeStep {
  const FakeVolumeReply(this.statusCode, this.body, {this.headers = const {}});

  final int statusCode;
  final String body;
  final Map<String, String> headers;
}

/// No response within the time limit. The state does not change.
final class FakeVolumeTimeout extends FakeVolumeStep {
  const FakeVolumeTimeout();
}

/// Success envelope `{ "data": { "level", "muted" } }`.
FakeVolumeReply fakeVolumeData(int level, bool muted) {
  return FakeVolumeReply(
    200,
    jsonEncode({
      'data': {'level': level, 'muted': muted},
    }),
  );
}

/// Error envelope `{ "error": { "code", "message" } }`.
FakeVolumeReply fakeVolumeError(int statusCode, String code) {
  return FakeVolumeReply(
    statusCode,
    jsonEncode({
      'error': {'code': code, 'message': 'fake error'},
    }),
  );
}

/// Programmable fake of the volume endpoints with a stateful level and mute.
///
/// Steps are used in order per call; after they run out, the last step repeats.
/// Only a successful step changes the state. Default: every call succeeds.
final class FakeVolumeRepository implements VolumeRepository {
  FakeVolumeRepository({
    List<FakeVolumeStep> script = const [FakeVolumeOk()],
    int initialLevel = 35,
    bool initialMuted = false,
    this.delay = Duration.zero,
  }) : assert(script.isNotEmpty, 'script must contain at least one step'),
       _script = List.unmodifiable(script),
       _current = VolumeStatus(level: initialLevel, muted: initialMuted);

  final List<FakeVolumeStep> _script;

  /// Delay before the reply. Zero in tests.
  final Duration delay;

  VolumeStatus _current;
  int _steps = 0;

  int setLevelCalls = 0;
  int upCalls = 0;
  int downCalls = 0;
  int setMutedCalls = 0;

  /// Argument of the most recent [setLevel] call, or null if none yet.
  int? lastLevel;

  /// Argument of the most recent [setMuted] call, or null if none yet.
  bool? lastMuted;

  /// State the fake currently holds (what the agent would report).
  VolumeStatus get current => _current;

  @override
  Future<VolumeStatus> setLevel(int level) async {
    setLevelCalls++;
    lastLevel = level;
    if (level < 0 || level > 100) {
      throw const ServerFailure(code: 'invalid_level');
    }
    return _run((s) => VolumeStatus(level: level, muted: false));
  }

  @override
  Future<VolumeStatus> up() async {
    upCalls++;
    return _run(
      (s) => VolumeStatus(level: (s.level + 5).clamp(0, 100), muted: false),
    );
  }

  @override
  Future<VolumeStatus> down() async {
    downCalls++;
    return _run(
      (s) => VolumeStatus(level: (s.level - 5).clamp(0, 100), muted: false),
    );
  }

  @override
  Future<VolumeStatus> setMuted(bool muted) async {
    setMutedCalls++;
    lastMuted = muted;
    return _run((s) => VolumeStatus(level: s.level, muted: muted));
  }

  /// Takes the next step. [apply] is the agent-side effect of a successful call.
  Future<VolumeStatus> _run(VolumeStatus Function(VolumeStatus) apply) async {
    final index = _steps < _script.length ? _steps : _script.length - 1;
    _steps++;
    if (delay > Duration.zero) await Future<void>.delayed(delay);

    final step = _script[index];
    switch (step) {
      case FakeVolumeOk():
        _current = apply(_current);
        return _current;
      case FakeVolumeReply():
        final data = unwrapAgentResponse(
          step.statusCode,
          step.body,
          headers: step.headers,
        );
        final parsed = _parseVolume(data);
        _current = parsed;
        return parsed;
      case FakeVolumeTimeout():
        throw const TimeoutFailure();
    }
  }

  /// Same rules as the HTTP path: `level` 0–100 and `muted` bool, else [ServerFailure].
  VolumeStatus _parseVolume(Map<String, Object?> data) {
    final level = data['level'];
    final muted = data['muted'];
    if (level is int && level >= 0 && level <= 100 && muted is bool) {
      return VolumeStatus(level: level, muted: muted);
    }
    throw const ServerFailure();
  }
}
