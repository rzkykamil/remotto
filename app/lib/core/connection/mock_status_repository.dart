import 'dart:convert';

import '../network/agent_status.dart';
import '../network/api_failure.dart';
import 'status_repository.dart';

/// One mock script step: a fake HTTP reply, or a failure before any response.
sealed class MockStatusStep {
  const MockStatusStep();
}

/// Fake HTTP reply. The body is parsed via [parseStatusResponse], same as the later HTTP.
final class MockHttpReply extends MockStatusStep {
  const MockHttpReply(this.statusCode, this.body, {this.headers = const {}});

  final int statusCode;
  final String body;
  final Map<String, String> headers;
}

/// Failure before any response: timeout or agent unreachable.
final class MockTransportFailure extends MockStatusStep {
  const MockTransportFailure(this.failure);

  final ApiFailure failure;
}

/// Success envelope `{ "data": ... }` for `GET /status`.
MockHttpReply mockStatusOk({
  String name = 'Laptop-Kamil',
  int uptimeSeconds = 0,
  bool volumeUnavailable = false,
  int volumeLevel = 35,
  bool volumeMuted = false,
  Map<String, Object?>? pending,
}) {
  return MockHttpReply(
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
MockHttpReply mockErrorReply(
  int statusCode,
  String code, {
  Map<String, String> headers = const {},
}) {
  return MockHttpReply(
    statusCode,
    jsonEncode({
      'error': {'code': code, 'message': 'mock error'},
    }),
    headers: headers,
  );
}

/// Programmable mock of `GET /status`. Steps are used in order;
/// after they run out, the last step repeats.
final class MockStatusRepository implements StatusRepository {
  MockStatusRepository(
    List<MockStatusStep> script, {
    this.delay = Duration.zero,
  }) : assert(script.isNotEmpty, 'script harus berisi minimal satu langkah'),
       _script = List.unmodifiable(script);

  final List<MockStatusStep> _script;

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
      case MockHttpReply(:final statusCode, :final body, :final headers):
        return parseStatusResponse(statusCode, body, headers: headers);
      case MockTransportFailure(:final failure):
        throw failure;
    }
  }
}
