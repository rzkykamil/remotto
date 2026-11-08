import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:remotto/core/network/agent_http_client.dart';
import 'package:remotto/core/network/agent_status.dart';
import 'package:remotto/core/network/api_failure.dart';

const _host = '192.168.1.20';
const _port = 8765;
const _token =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
const _timeout = Duration(seconds: 3);

String _volumeBody({int level = 60, bool muted = false}) {
  return jsonEncode({
    'data': {'level': level, 'muted': muted},
  });
}

http.Response _json(int status, String body, {Map<String, String>? headers}) {
  return http.Response(
    body,
    status,
    headers: {'content-type': 'application/json; charset=utf-8', ...?headers},
  );
}

/// Builds the client with a [MockClient] and records every request it sees.
({AgentHttpClient client, List<http.Request> requests}) _build(
  FutureOr<http.Response> Function(http.Request request) handler,
) {
  final requests = <http.Request>[];
  final mock = MockClient((request) async {
    requests.add(request);
    return handler(request);
  });
  return (client: AgentHttpClient(mock), requests: requests);
}

Future<Object?> _errorOf(Future<Object?> Function() call) async {
  try {
    await call();
  } catch (error) {
    return error;
  }
  return null;
}

Future<VolumeStatus> _putVolume(AgentHttpClient client, {int level = 60}) {
  return client.putVolume(
    host: _host,
    port: _port,
    token: _token,
    level: level,
    timeout: _timeout,
  );
}

Future<VolumeStatus> _postStep(AgentHttpClient client, String direction) {
  return client.postVolumeStep(
    host: _host,
    port: _port,
    token: _token,
    direction: direction,
    timeout: _timeout,
  );
}

Future<VolumeStatus> _postMute(AgentHttpClient client, {required bool muted}) {
  return client.postVolumeMute(
    host: _host,
    port: _port,
    token: _token,
    muted: muted,
    timeout: _timeout,
  );
}

void main() {
  group('request volume', () {
    test('PUT /api/v1/volume dengan body level dan Bearer token', () async {
      final built = _build((_) => _json(200, _volumeBody(level: 60)));

      await _putVolume(built.client, level: 60);

      expect(built.requests, hasLength(1));
      final request = built.requests.single;
      expect(request.method, 'PUT');
      expect(request.url, Uri.http('$_host:$_port', '/api/v1/volume'));
      expect(request.headers['Authorization'], 'Bearer $_token');
      expect(request.headers['Accept'], 'application/json');
      expect(request.headers['Content-Type'], 'application/json');
      expect(jsonDecode(request.body), {'level': 60});
    });

    test('POST /api/v1/volume/up tanpa body', () async {
      final built = _build((_) => _json(200, _volumeBody(level: 40)));

      await _postStep(built.client, 'up');

      expect(built.requests, hasLength(1));
      final request = built.requests.single;
      expect(request.method, 'POST');
      expect(request.url, Uri.http('$_host:$_port', '/api/v1/volume/up'));
      expect(request.headers['Authorization'], 'Bearer $_token');
      expect(request.body, isEmpty);
      expect(request.headers.containsKey('Content-Type'), isFalse);
    });

    test('POST /api/v1/volume/down tanpa body', () async {
      final built = _build((_) => _json(200, _volumeBody(level: 30)));

      await _postStep(built.client, 'down');

      final request = built.requests.single;
      expect(request.method, 'POST');
      expect(request.url, Uri.http('$_host:$_port', '/api/v1/volume/down'));
      expect(request.body, isEmpty);
    });

    test('POST /api/v1/volume/mute dengan body muted', () async {
      final built = _build(
        (_) => _json(200, _volumeBody(level: 35, muted: true)),
      );

      await _postMute(built.client, muted: true);

      final request = built.requests.single;
      expect(request.method, 'POST');
      expect(request.url, Uri.http('$_host:$_port', '/api/v1/volume/mute'));
      expect(request.headers['Authorization'], 'Bearer $_token');
      expect(request.headers['Content-Type'], 'application/json');
      expect(jsonDecode(request.body), {'muted': true});
    });
  });

  group('respons volume', () {
    test('200 menjadi VolumeStatus dari data', () async {
      final built = _build(
        (_) => _json(200, _volumeBody(level: 60, muted: true)),
      );

      final volume = await _putVolume(built.client, level: 60);

      expect(volume, const VolumeStatus(level: 60, muted: true));
    });

    test('401 menjadi UnauthorizedFailure dengan code invalid_token', () async {
      final built = _build(
        (_) => _json(
          401,
          jsonEncode({
            'error': {'code': 'invalid_token', 'message': 'x'},
          }),
        ),
      );

      final error = await _errorOf(() => _postStep(built.client, 'up'));

      expect(error, isA<UnauthorizedFailure>());
      expect((error as ApiFailure).code, 'invalid_token');
      expect(built.requests, hasLength(1));
    });

    test('403 menjadi ForbiddenFailure', () async {
      final built = _build(
        (_) => _json(
          403,
          jsonEncode({
            'error': {'code': 'forbidden_network', 'message': 'x'},
          }),
        ),
      );

      final error = await _errorOf(() => _postMute(built.client, muted: true));

      expect(error, isA<ForbiddenFailure>());
      expect(built.requests, hasLength(1));
    });

    test('429 menjadi RateLimitedFailure dengan retryAfter', () async {
      final built = _build(
        (_) => _json(
          429,
          jsonEncode({
            'error': {'code': 'rate_limited', 'message': 'x'},
          }),
          headers: {'Retry-After': '2'},
        ),
      );

      final error = await _errorOf(() => _postStep(built.client, 'down'));

      expect(error, isA<RateLimitedFailure>());
      expect(
        (error as RateLimitedFailure).retryAfter,
        const Duration(seconds: 2),
      );
      expect(built.requests, hasLength(1));
    });

    test('400 invalid_level menjadi ServerFailure dengan code', () async {
      final built = _build(
        (_) => _json(
          400,
          jsonEncode({
            'error': {'code': 'invalid_level', 'message': 'x'},
          }),
        ),
      );

      final error = await _errorOf(() => _putVolume(built.client, level: 150));

      expect(error, isA<ServerFailure>());
      expect((error as ApiFailure).code, 'invalid_level');
      expect(built.requests, hasLength(1));
    });

    test('500 audio_failed menjadi ServerFailure dengan code', () async {
      final built = _build(
        (_) => _json(
          500,
          jsonEncode({
            'error': {'code': 'audio_failed', 'message': 'x'},
          }),
        ),
      );

      final error = await _errorOf(() => _postStep(built.client, 'up'));

      expect(error, isA<ServerFailure>());
      expect((error as ApiFailure).code, 'audio_failed');
      expect(built.requests, hasLength(1));
    });

    test('200 tanpa level menjadi ServerFailure', () async {
      final built = _build(
        (_) => _json(
          200,
          jsonEncode({
            'data': {'muted': false},
          }),
        ),
      );

      final error = await _errorOf(() => _putVolume(built.client));

      expect(error, isA<ServerFailure>());
      expect(built.requests, hasLength(1));
    });

    test('200 dengan body bukan JSON menjadi ServerFailure', () async {
      final built = _build((_) => _json(200, 'bukan json'));

      final error = await _errorOf(() => _postMute(built.client, muted: false));

      expect(error, isA<ServerFailure>());
    });
  });

  group('transport volume', () {
    test('SocketException menjadi UnreachableFailure, satu request', () async {
      final built = _build((_) => throw const SocketException('refused'));

      final error = await _errorOf(() => _postStep(built.client, 'up'));

      expect(error, isA<UnreachableFailure>());
      expect(built.requests, hasLength(1));
    });

    test('handler tak selesai menjadi TimeoutFailure, satu request', () async {
      final built = _build((_) => Completer<http.Response>().future);

      final error = await _errorOf(() => _putVolume(built.client));

      expect(error, isA<TimeoutFailure>());
      expect(built.requests, hasLength(1));
    });
  });
}
