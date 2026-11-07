import 'dart:convert';

import 'package:remotto/core/network/api_failure.dart';
import 'package:remotto/features/remote/data/media_repository.dart';

/// One scripted step of [FakeMediaRepository].
sealed class FakeMediaStep {
  const FakeMediaStep();
}

/// Fixed HTTP reply. The body goes through the same parsing as the HTTP path.
final class FakeMediaReply extends FakeMediaStep {
  const FakeMediaReply(this.statusCode, this.body, {this.headers = const {}});

  final int statusCode;
  final String body;
  final Map<String, String> headers;
}

/// 200 reply that echoes the requested action, like the agent does.
final class FakeMediaEcho extends FakeMediaStep {
  const FakeMediaEcho();
}

/// No response within the time limit.
final class FakeMediaTimeout extends FakeMediaStep {
  const FakeMediaTimeout();
}

/// Success envelope `{ "data": { "action": ... } }`.
FakeMediaReply fakeMediaOk(MediaAction action) {
  return FakeMediaReply(
    200,
    jsonEncode({
      'data': {'action': action.wire},
    }),
  );
}

/// Error envelope `{ "error": { "code", "message" } }`.
FakeMediaReply fakeMediaError(int statusCode, String code) {
  return FakeMediaReply(
    statusCode,
    jsonEncode({
      'error': {'code': code, 'message': 'fake error'},
    }),
  );
}

/// Programmable fake of the media endpoints. Steps are used in order;
/// after they run out, the last step repeats.
final class FakeMediaRepository implements MediaRepository {
  FakeMediaRepository(List<FakeMediaStep> script, {this.delay = Duration.zero})
    : assert(script.isNotEmpty, 'script must contain at least one step'),
      _script = List.unmodifiable(script);

  final List<FakeMediaStep> _script;

  /// Delay before the reply. Zero in tests.
  final Duration delay;

  int _calls = 0;
  MediaAction? _lastAction;

  /// Number of [send] calls so far.
  int get calls => _calls;

  /// Action of the most recent [send] call, or null if none yet.
  MediaAction? get lastAction => _lastAction;

  @override
  Future<void> send(MediaAction action) async {
    final index = _calls < _script.length ? _calls : _script.length - 1;
    _calls++;
    _lastAction = action;
    if (delay > Duration.zero) await Future<void>.delayed(delay);

    final reply = _replyFor(action, _script[index]);
    final data = unwrapAgentResponse(
      reply.statusCode,
      reply.body,
      headers: reply.headers,
    );
    if (data['action'] != action.wire) throw const ServerFailure();
  }

  FakeMediaReply _replyFor(MediaAction action, FakeMediaStep step) {
    return switch (step) {
      FakeMediaReply() => step,
      FakeMediaEcho() => fakeMediaOk(action),
      FakeMediaTimeout() => throw const TimeoutFailure(),
    };
  }
}
