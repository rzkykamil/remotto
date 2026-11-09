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

  group('postMedia', () {
    Future<Object?> postMedia(
      AgentHttpClient client, {
      String action = 'play-pause',
      Duration timeout = _timeout,
    }) {
      return _errorOf(
        () => client.postMedia(
          host: _host,
          port: _port,
          token: _token,
          action: action,
          timeout: timeout,
        ),
      );
    }

    String echoBody(String action) => jsonEncode({
      'data': {'action': action},
    });

    test('POST ke /api/v1/media/play-pause dengan Bearer token', () async {
      final built = _build((_) => _json(200, echoBody('play-pause')));

      await built.client.postMedia(
        host: _host,
        port: _port,
        token: _token,
        action: 'play-pause',
        timeout: _timeout,
      );

      expect(built.requests, hasLength(1));
      final request = built.requests.single;
      expect(request.method, 'POST');
      expect(
        request.url,
        Uri.http('$_host:$_port', '/api/v1/media/play-pause'),
      );
      expect(request.headers['Authorization'], 'Bearer $_token');
      expect(request.headers['Accept'], 'application/json');
      expect(request.body, isEmpty);
    });

    test('tiga action memakai tiga path berbeda', () async {
      final built = _build((request) {
        final action = request.url.pathSegments.last;
        return _json(200, echoBody(action));
      });

      for (final action in ['play-pause', 'next', 'prev']) {
        await built.client.postMedia(
          host: _host,
          port: _port,
          token: _token,
          action: action,
          timeout: _timeout,
        );
      }

      expect(built.requests.map((r) => r.url.path).toList(), [
        '/api/v1/media/play-pause',
        '/api/v1/media/next',
        '/api/v1/media/prev',
      ]);
      expect(built.requests.every((r) => r.method == 'POST'), isTrue);
    });

    test('200 dengan action cocok selesai tanpa error', () async {
      final built = _build((_) => _json(200, echoBody('next')));

      final error = await postMedia(built.client, action: 'next');

      expect(error, isNull);
      expect(built.requests, hasLength(1));
    });

    test('200 dengan action berbeda menjadi ServerFailure', () async {
      final built = _build((_) => _json(200, echoBody('prev')));

      final error = await postMedia(built.client, action: 'next');

      expect(error, isA<ServerFailure>());
    });

    test('200 tanpa action di data menjadi ServerFailure', () async {
      final built = _build((_) => _json(200, jsonEncode({'data': {}})));

      final error = await postMedia(built.client);

      expect(error, isA<ServerFailure>());
    });

    test('200 dengan body bukan JSON menjadi ServerFailure', () async {
      final built = _build((_) => _json(200, '<html>proxy</html>'));

      final error = await postMedia(built.client);

      expect(error, isA<ServerFailure>());
    });

    test('401 invalid_token menjadi UnauthorizedFailure', () async {
      final built = _build(
        (_) => _json(
          401,
          jsonEncode({
            'error': {'code': 'invalid_token', 'message': 'Token salah'},
          }),
        ),
      );

      final error = await postMedia(built.client);

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

      final error = await postMedia(built.client);

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

        final error = await postMedia(built.client);

        expect(error, isA<RateLimitedFailure>());
        final failure = error as RateLimitedFailure;
        expect(failure.code, 'rate_limited');
        expect(failure.retryAfter, const Duration(seconds: 2));
      },
    );

    test(
      '500 media_failed menjadi ServerFailure dengan code media_failed',
      () async {
        final built = _build(
          (_) => _json(
            500,
            jsonEncode({
              'error': {'code': 'media_failed', 'message': 'Pesan aman'},
            }),
          ),
        );

        final error = await postMedia(built.client);

        expect(error, isA<ServerFailure>());
        expect((error as ServerFailure).code, 'media_failed');
      },
    );

    test('409 tidak dipetakan khusus dan jatuh ke ServerFailure', () async {
      final built = _build(
        (_) => _json(
          409,
          jsonEncode({
            'error': {'code': 'power_pending', 'message': 'Ada jadwal'},
          }),
        ),
      );

      final error = await postMedia(built.client);

      expect(error, isA<ServerFailure>());
      expect((error as ServerFailure).code, 'power_pending');
    });

    test('handler tak pernah selesai menjadi TimeoutFailure', () async {
      final gate = Completer<void>();
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      final built = _build((_) async {
        await gate.future;
        return _json(200, echoBody('play-pause'));
      });

      final error = await postMedia(
        built.client,
        timeout: const Duration(milliseconds: 50),
      );

      expect(error, isA<TimeoutFailure>());
    });

    test('SocketException menjadi UnreachableFailure', () async {
      final built = _build(
        (_) => throw const SocketException('Connection refused'),
      );

      final error = await postMedia(built.client);

      expect(error, isA<UnreachableFailure>());
    });

    test('http.ClientException menjadi UnreachableFailure', () async {
      final built = _build(
        (_) => throw http.ClientException('Connection closed'),
      );

      final error = await postMedia(built.client);

      expect(error, isA<UnreachableFailure>());
    });

    test('pesan exception yang memuat token tidak ikut ke failure', () async {
      final built = _build(
        (_) => throw const SocketException('gagal ke Bearer $_token'),
      );

      final error = await postMedia(built.client);

      expect(error, isA<UnreachableFailure>());
      expect(error.toString(), isNot(contains(_token)));
    });
  });

  group('postPower', () {
    String scheduledBody(String action) => jsonEncode({
      'data': {
        'pending': {
          'action': action,
          'remainingMs': 5000,
          'delayMs': 5000,
          'scheduledAt': '2026-01-01T23:41:00+07:00',
        },
      },
    });

    test(
      'schedule POST ke /api/v1/power/{action} tanpa body, 202 sukses',
      () async {
        final built = _build((request) {
          final action = request.url.pathSegments.last;
          return _json(202, scheduledBody(action));
        });

        final data = await built.client.postPowerSchedule(
          host: _host,
          port: _port,
          token: _token,
          action: 'shutdown',
          timeout: _timeout,
        );

        expect(data['pending'], isA<Map<String, Object?>>());
        final request = built.requests.single;
        expect(request.method, 'POST');
        expect(
          request.url,
          Uri.http('$_host:$_port', '/api/v1/power/shutdown'),
        );
        expect(request.headers['Authorization'], 'Bearer $_token');
        expect(request.headers.containsKey('Content-Type'), isFalse);
        expect(request.body, isEmpty);
      },
    );

    test('cancel POST ke /api/v1/power/cancel, 200 sukses', () async {
      final built = _build(
        (_) => _json(
          200,
          jsonEncode({
            'data': {'cancelled': 'shutdown', 'pending': null},
          }),
        ),
      );

      final data = await built.client.postPowerCancel(
        host: _host,
        port: _port,
        token: _token,
        timeout: _timeout,
      );

      expect(data['cancelled'], 'shutdown');
      final request = built.requests.single;
      expect(request.url, Uri.http('$_host:$_port', '/api/v1/power/cancel'));
      expect(request.headers['Authorization'], 'Bearer $_token');
    });

    test('schedule tidak di-retry walau gagal transport', () async {
      final built = _build((_) => throw const SocketException('putus'));

      final error = await _errorOf(
        () => built.client.postPowerSchedule(
          host: _host,
          port: _port,
          token: _token,
          action: 'sleep',
          timeout: _timeout,
        ),
      );

      expect(error, isA<UnreachableFailure>());
      expect(built.requests, hasLength(1));
    });

    test('409 power_pending menjadi ServerFailure dengan code', () async {
      final built = _build(
        (_) => _json(
          409,
          jsonEncode({
            'error': {'code': 'power_pending', 'message': 'ada jadwal'},
          }),
        ),
      );

      final error = await _errorOf(
        () => built.client.postPowerSchedule(
          host: _host,
          port: _port,
          token: _token,
          action: 'restart',
          timeout: _timeout,
        ),
      );

      expect(error, isA<ServerFailure>());
      expect((error as ServerFailure).code, 'power_pending');
    });
  });
}
