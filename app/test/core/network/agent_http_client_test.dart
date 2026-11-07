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

String _okBody({Object? volume = const {'level': 35, 'muted': false}}) {
  return jsonEncode({
    'data': {
      'name': 'Laptop-Kamil',
      'version': '1.0.0',
      'uptimeSeconds': 11520,
      'volume': volume,
      'pending': null,
    },
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

void main() {
  group('request', () {
    test('GET ke /api/v1/status pada host:port dengan Bearer token', () async {
      final built = _build((_) => _json(200, _okBody()));

      await built.client.getStatus(
        host: _host,
        port: _port,
        token: _token,
        timeout: _timeout,
      );

      expect(built.requests, hasLength(1));
      final request = built.requests.single;
      expect(request.method, 'GET');
      expect(request.url, Uri.http('$_host:$_port', '/api/v1/status'));
      expect(request.headers['Authorization'], 'Bearer $_token');
      expect(request.headers['Accept'], 'application/json');
    });

    test('request dikirim tepat satu kali per panggilan', () async {
      final built = _build((_) => _json(200, _okBody()));

      await built.client.getStatus(
        host: _host,
        port: _port,
        token: _token,
        timeout: _timeout,
      );

      expect(built.requests, hasLength(1));
    });
  });

  group('respons sukses', () {
    test('200 dengan volume terisi dibaca ke AgentStatus', () async {
      final built = _build((_) => _json(200, _okBody()));

      final status = await built.client.getStatus(
        host: _host,
        port: _port,
        token: _token,
        timeout: _timeout,
      );

      expect(status.name, 'Laptop-Kamil');
      expect(status.version, '1.0.0');
      expect(status.uptimeSeconds, 11520);
      expect(status.volume, const VolumeStatus(level: 35, muted: false));
      expect(status.pending, isNull);
    });

    test('200 dengan volume null tetap sukses (Core Audio gagal)', () async {
      final built = _build((_) => _json(200, _okBody(volume: null)));

      final status = await built.client.getStatus(
        host: _host,
        port: _port,
        token: _token,
        timeout: _timeout,
      );

      expect(status.volume, isNull);
      expect(status.name, 'Laptop-Kamil');
    });

    test('200 dengan pending objek membaca remainingMs dan delayMs', () async {
      final body = jsonEncode({
        'data': {
          'name': 'Laptop-Kamil',
          'version': '1.0.0',
          'uptimeSeconds': 60,
          'volume': {'level': 10, 'muted': true},
          'pending': {
            'action': 'shutdown',
            'remainingMs': 3200,
            'delayMs': 5000,
            'scheduledAt': '2026-01-01T23:41:00+07:00',
          },
        },
      });
      final built = _build((_) => _json(200, body));

      final status = await built.client.getStatus(
        host: _host,
        port: _port,
        token: _token,
        timeout: _timeout,
      );

      final pending = status.pending!;
      expect(pending.action, 'shutdown');
      expect(pending.remainingMs, 3200);
      expect(pending.delayMs, 5000);
    });
  });

  group('kode HTTP dipetakan ke ApiFailure', () {
    test('401 invalid_token menjadi UnauthorizedFailure', () async {
      final built = _build(
        (_) => _json(
          401,
          jsonEncode({
            'error': {'code': 'invalid_token', 'message': 'Token salah'},
          }),
        ),
      );

      final error = await _errorOf(
        () => built.client.getStatus(
          host: _host,
          port: _port,
          token: _token,
          timeout: _timeout,
        ),
      );

      expect(error, isA<UnauthorizedFailure>());
      expect((error as UnauthorizedFailure).code, 'invalid_token');
    });

    test('403 forbidden_network menjadi ForbiddenFailure', () async {
      final built = _build(
        (_) => _json(
          403,
          jsonEncode({
            'error': {'code': 'forbidden_network', 'message': 'Di luar LAN'},
          }),
        ),
      );

      final error = await _errorOf(
        () => built.client.getStatus(
          host: _host,
          port: _port,
          token: _token,
          timeout: _timeout,
        ),
      );

      expect(error, isA<ForbiddenFailure>());
      expect((error as ForbiddenFailure).code, 'forbidden_network');
    });

    test(
      '429 dengan Retry-After 2 menjadi RateLimitedFailure 2 detik',
      () async {
        final built = _build(
          (_) => _json(
            429,
            jsonEncode({
              'error': {'code': 'rate_limited', 'message': 'Terlalu banyak'},
            }),
            headers: {'Retry-After': '2'},
          ),
        );

        final error = await _errorOf(
          () => built.client.getStatus(
            host: _host,
            port: _port,
            token: _token,
            timeout: _timeout,
          ),
        );

        expect(error, isA<RateLimitedFailure>());
        final failure = error as RateLimitedFailure;
        expect(failure.code, 'rate_limited');
        expect(failure.retryAfter, const Duration(seconds: 2));
      },
    );

    test('429 tanpa Retry-After tetap RateLimitedFailure tanpa jeda', () async {
      final built = _build((_) => _json(429, '{}'));

      final error = await _errorOf(
        () => built.client.getStatus(
          host: _host,
          port: _port,
          token: _token,
          timeout: _timeout,
        ),
      );

      expect(error, isA<RateLimitedFailure>());
      expect((error as RateLimitedFailure).retryAfter, isNull);
    });

    test('500 internal menjadi ServerFailure', () async {
      final built = _build(
        (_) => _json(
          500,
          jsonEncode({
            'error': {'code': 'internal', 'message': 'Pesan aman'},
          }),
        ),
      );

      final error = await _errorOf(
        () => built.client.getStatus(
          host: _host,
          port: _port,
          token: _token,
          timeout: _timeout,
        ),
      );

      expect(error, isA<ServerFailure>());
      expect((error as ServerFailure).code, 'internal');
    });
  });

  group('body tidak sesuai kontrak menjadi ServerFailure', () {
    test('200 dengan body bukan JSON', () async {
      final built = _build((_) => _json(200, '<html>proxy</html>'));

      final error = await _errorOf(
        () => built.client.getStatus(
          host: _host,
          port: _port,
          token: _token,
          timeout: _timeout,
        ),
      );

      expect(error, isA<ServerFailure>());
    });

    test('200 tanpa kunci data', () async {
      final built = _build((_) => _json(200, jsonEncode({'ok': true})));

      final error = await _errorOf(
        () => built.client.getStatus(
          host: _host,
          port: _port,
          token: _token,
          timeout: _timeout,
        ),
      );

      expect(error, isA<ServerFailure>());
    });

    test('200 dengan byte bukan UTF-8', () async {
      final built = _build(
        (_) => http.Response.bytes(
          [0xff, 0xfe, 0xfd],
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      );

      final error = await _errorOf(
        () => built.client.getStatus(
          host: _host,
          port: _port,
          token: _token,
          timeout: _timeout,
        ),
      );

      expect(error, isA<ServerFailure>());
    });
  });

  group('error transport menjadi UnreachableFailure atau TimeoutFailure', () {
    test('SocketException menjadi UnreachableFailure', () async {
      final built = _build(
        (_) => throw const SocketException('Connection refused'),
      );

      final error = await _errorOf(
        () => built.client.getStatus(
          host: _host,
          port: _port,
          token: _token,
          timeout: _timeout,
        ),
      );

      expect(error, isA<UnreachableFailure>());
    });

    test('http.ClientException menjadi UnreachableFailure', () async {
      final built = _build(
        (_) => throw http.ClientException('Connection closed'),
      );

      final error = await _errorOf(
        () => built.client.getStatus(
          host: _host,
          port: _port,
          token: _token,
          timeout: _timeout,
        ),
      );

      expect(error, isA<UnreachableFailure>());
    });

    test('HandshakeException menjadi UnreachableFailure', () async {
      final built = _build((_) => throw const HandshakeException('TLS gagal'));

      final error = await _errorOf(
        () => built.client.getStatus(
          host: _host,
          port: _port,
          token: _token,
          timeout: _timeout,
        ),
      );

      expect(error, isA<UnreachableFailure>());
    });

    test('error tak dikenal menjadi UnreachableFailure', () async {
      final built = _build((_) => throw StateError('tak terduga'));

      final error = await _errorOf(
        () => built.client.getStatus(
          host: _host,
          port: _port,
          token: _token,
          timeout: _timeout,
        ),
      );

      expect(error, isA<UnreachableFailure>());
    });

    test('respons melebihi timeout menjadi TimeoutFailure', () async {
      // The gate is completed in tearDown, so no real timer keeps running.
      final gate = Completer<void>();
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      final built = _build((_) async {
        await gate.future;
        return _json(200, _okBody());
      });

      final error = await _errorOf(
        () => built.client.getStatus(
          host: _host,
          port: _port,
          token: _token,
          timeout: const Duration(milliseconds: 50),
        ),
      );

      expect(error, isA<TimeoutFailure>());
    });
  });

  group('token tidak bocor', () {
    test('pesan exception yang memuat token tidak ikut ke failure', () async {
      final built = _build(
        (_) => throw const SocketException('gagal ke Bearer $_token'),
      );

      final error = await _errorOf(
        () => built.client.getStatus(
          host: _host,
          port: _port,
          token: _token,
          timeout: _timeout,
        ),
      );

      expect(error, isA<UnreachableFailure>());
      expect(error.toString(), isNot(contains(_token)));
    });

    test('error tak dikenal yang memuat token tidak ikut ke failure', () async {
      final built = _build((_) => throw Exception('boom $_token'));

      final error = await _errorOf(
        () => built.client.getStatus(
          host: _host,
          port: _port,
          token: _token,
          timeout: _timeout,
        ),
      );

      expect(error, isA<UnreachableFailure>());
      expect(error.toString(), isNot(contains(_token)));
    });

    test('failure 401 tidak memuat token dari request', () async {
      final built = _build(
        (_) => _json(
          401,
          jsonEncode({
            'error': {'code': 'invalid_token', 'message': 'salah'},
          }),
        ),
      );

      final error = await _errorOf(
        () => built.client.getStatus(
          host: _host,
          port: _port,
          token: _token,
          timeout: _timeout,
        ),
      );

      expect(error.toString(), isNot(contains(_token)));
    });
  });
}
