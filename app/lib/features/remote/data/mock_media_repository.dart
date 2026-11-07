import 'dart:convert';

import 'package:remotto/core/network/api_failure.dart';
import 'package:remotto/features/remote/data/media_repository.dart';

/// One scripted step of [MockMediaRepository].
sealed class MockMediaStep {
  const MockMediaStep();
}

/// Fixed HTTP reply. The body goes through the same parsing as the HTTP path.
final class MockMediaReply extends MockMediaStep {
  const MockMediaReply(this.statusCode, this.body, {this.headers = const {}});

  final int statusCode;
  final String body;
  final Map<String, String> headers;
}

/// 200 reply that echoes the requested action, like the agent does.
final class MockMediaEcho extends MockMediaStep {
  const MockMediaEcho();
}

/// No response within the time limit.
final class MockMediaTimeout extends MockMediaStep {
  const MockMediaTimeout();
}

/// Success envelope `{ "data": { "action": ... } }`.
MockMediaReply mockMediaOk(MediaAction action) {
  return MockMediaReply(
    200,
    jsonEncode({
      'data': {'action': action.wire},
    }),
  );
}

/// Error envelope `{ "error": { "code", "message" } }`.
MockMediaReply mockMediaError(int statusCode, String code) {
  return MockMediaReply(
    statusCode,
    jsonEncode({
      'error': {'code': code, 'message': 'mock error'},
    }),
  );
}

/// Programmable fake of the media endpoints. Steps are used in order;
/// after they run out, the last step repeats.
final class MockMediaRepository implements MediaRepository {
  MockMediaRepository(List<MockMediaStep> script, {this.delay = Duration.zero})
    : assert(script.isNotEmpty, 'script harus berisi minimal satu langkah'),
      _script = List.unmodifiable(script);

  final List<MockMediaStep> _script;

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

  MockMediaReply _replyFor(MediaAction action, MockMediaStep step) {
    return switch (step) {
      MockMediaReply() => step,
      MockMediaEcho() => mockMediaOk(action),
      MockMediaTimeout() => throw const TimeoutFailure(),
    };
  }
}
