import 'dart:convert';

import 'package:remotto/core/connection/status_repository.dart';
import 'package:remotto/core/network/agent_status.dart';
import 'package:remotto/core/network/api_failure.dart';

/// One fake script step: a fake HTTP reply, or a failure before any response.
sealed class FakeStatusStep {
  const FakeStatusStep();
}

/// Fake HTTP reply. The body is parsed via [parseStatusResponse], same as the HTTP path.
final class FakeHttpReply extends FakeStatusStep {
  const FakeHttpReply(this.statusCode, this.body, {this.headers = const {}});

  final int statusCode;
  final String body;
  final Map<String, String> headers;
}

/// Failure before any response: timeout or agent unreachable.
final class FakeTransportFailure extends FakeStatusStep {
  const FakeTransportFailure(this.failure);

  final ApiFailure failure;
}

/// Success envelope `{ "data": ... }` for `GET /status`.
FakeHttpReply fakeStatusOk({
  String name = 'Laptop-Kamil',
  int uptimeSeconds = 0,
  bool volumeUnavailable = false,
  int volumeLevel = 35,
  bool volumeMuted = false,
  Map<String, Object?>? pending,
}) {
  return FakeHttpReply(
    200,
    jsonEncode({
      'data': {
        'name': name,
        'version': '1.0.0',
        'uptimeSeconds': uptimeSeconds,
        'volume': volumeUnavailable
            ? null
            : {'level': volumeLevel, 'muted': volumeMuted},
        'pending': pending,
      },
    }),
  );
}

/// Error envelope `{ "error": { "code", "message" } }`.
FakeHttpReply fakeErrorReply(
  int statusCode,
  String code, {
  Map<String, String> headers = const {},
}) {
  return FakeHttpReply(
    statusCode,
    jsonEncode({
      'error': {'code': code, 'message': 'fake error'},
    }),
    headers: headers,
  );
}

/// Programmable fake of `GET /status`. Steps are used in order;
/// after they run out, the last step repeats.
final class FakeStatusRepository implements StatusRepository {
  FakeStatusRepository(
    List<FakeStatusStep> script, {
    this.delay = Duration.zero,
  }) : assert(script.isNotEmpty, 'script harus berisi minimal satu langkah'),
       _script = List.unmodifiable(script);

  final List<FakeStatusStep> _script;

  /// Delay before the reply. Zero in tests.
  final Duration delay;

  int _calls = 0;

  /// Number of [fetchStatus] calls so far.
  int get calls => _calls;

  @override
  Future<AgentStatus> fetchStatus() async {
    final index = _calls < _script.length ? _calls : _script.length - 1;
    _calls++;
    if (delay > Duration.zero) await Future<void>.delayed(delay);

    final step = _script[index];
    switch (step) {
      case FakeHttpReply(:final statusCode, :final body, :final headers):
        return parseStatusResponse(statusCode, body, headers: headers);
      case FakeTransportFailure(:final failure):
        throw failure;
    }
  }
}
