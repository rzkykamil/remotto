import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:remotto/core/network/agent_http_client.dart';
import 'package:remotto/core/network/agent_status.dart';
import 'package:remotto/core/network/api_failure.dart';
import 'package:remotto/core/storage/pairing_data.dart';
import 'package:remotto/features/remote/data/http_power_repository.dart';
import 'package:remotto/features/remote/data/power_repository.dart';

const _token =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

const _pairing = PairingData(
  host: '192.168.1.20',
  port: 8765,
  token: _token,
  laptopName: 'Laptop-Kamil',
);

const _jsonHeaders = {'content-type': 'application/json; charset=utf-8'};

http.Response _pending202({String action = 'shutdown'}) {
  return http.Response(
    jsonEncode({
      'data': {
        'pending': {
          'action': action,
          'remainingMs': 5000,
          'delayMs': 5000,
          'scheduledAt': '2026-01-01T23:41:00+07:00',
        },
      },
    }),
    202,
    headers: _jsonHeaders,
  );
}

http.Response _cancelled200({String action = 'shutdown'}) {
  return http.Response(
    jsonEncode({
      'data': {'cancelled': action, 'pending': null},
    }),
    200,
    headers: _jsonHeaders,
  );
}

http.Response _error(int status, String code, {Map<String, String>? headers}) {
  return http.Response(
    jsonEncode({
      'error': {'code': code, 'message': 'x'},
    }),
    status,
    headers: {..._jsonHeaders, ...?headers},
  );
}

({
  HttpPowerRepository repo,
  List<http.Request> requests,
  void Function(PairingData?) setPairing,
})
_build({
  PairingData? pairing = _pairing,
  FutureOr<http.Response> Function(http.Request)? handler,
  Duration timeout = const Duration(seconds: 3),
}) {
  final requests = <http.Request>[];
  var current = pairing;
  final mock = MockClient((request) async {
    requests.add(request);
    if (handler != null) return handler(request);
    return _pending202();
  });
  final repo = HttpPowerRepository(
    AgentHttpClient(mock),
    () => current,
    timeout: timeout,
  );
  return (
    repo: repo,
    requests: requests,
    setPairing: (value) => current = value,
  );
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
  group('schedule', () {
    test('POST /power/shutdown dengan Bearer token, tanpa body', () async {
      final built = _build();

      await built.repo.schedule(PowerAction.shutdown);

      expect(built.requests, hasLength(1));
      final request = built.requests.single;
      expect(request.method, 'POST');
      expect(
        request.url,
        Uri.http('192.168.1.20:8765', '/api/v1/power/shutdown'),
      );
      expect(request.headers['Authorization'], 'Bearer $_token');
      expect(request.body, isEmpty);
    });

    test('202 diurai ke Pending dengan field dari api-spec', () async {
      final built = _build();

      final pending = await built.repo.schedule(PowerAction.shutdown);

      expect(
        pending,
        const Pending(
          action: 'shutdown',
          remainingMs: 5000,
          delayMs: 5000,
          scheduledAt: '2026-01-01T23:41:00+07:00',
        ),
      );
    });

    test('409 power_pending menjadi ServerFailure dengan code', () async {
      final built = _build(handler: (_) => _error(409, 'power_pending'));

      final error = await _errorOf(
        () => built.repo.schedule(PowerAction.sleep),
      );

      expect(error, isA<ServerFailure>());
      expect((error as ApiFailure).code, 'power_pending');
      expect(built.requests, hasLength(1));
    });

    test('409 power_executing menjadi ServerFailure dengan code', () async {
      final built = _build(handler: (_) => _error(409, 'power_executing'));

      final error = await _errorOf(
        () => built.repo.schedule(PowerAction.restart),
      );

      expect(error, isA<ServerFailure>());
      expect((error as ApiFailure).code, 'power_executing');
    });

    test('500 power_failed menjadi ServerFailure dengan code', () async {
      final built = _build(handler: (_) => _error(500, 'power_failed'));

      final error = await _errorOf(
        () => built.repo.schedule(PowerAction.shutdown),
      );

      expect(error, isA<ServerFailure>());
      expect((error as ApiFailure).code, 'power_failed');
      expect(built.requests, hasLength(1));
    });

    test('401 menjadi UnauthorizedFailure', () async {
      final built = _build(handler: (_) => _error(401, 'invalid_token'));

      final error = await _errorOf(
        () => built.repo.schedule(PowerAction.shutdown),
      );

      expect(error, isA<UnauthorizedFailure>());
      expect(built.requests, hasLength(1));
    });

    test('403 menjadi ForbiddenFailure', () async {
      final built = _build(handler: (_) => _error(403, 'forbidden_source'));

      final error = await _errorOf(
        () => built.repo.schedule(PowerAction.shutdown),
      );

      expect(error, isA<ForbiddenFailure>());
      expect(built.requests, hasLength(1));
    });

    test('429 menjadi RateLimitedFailure, satu request', () async {
      final built = _build(
        handler: (_) =>
            _error(429, 'rate_limited', headers: {'Retry-After': '1'}),
      );

      final error = await _errorOf(
        () => built.repo.schedule(PowerAction.shutdown),
      );

      expect(error, isA<RateLimitedFailure>());
      expect(built.requests, hasLength(1));
    });

    test(
      'respons lambat melewati timeout menjadi TimeoutFailure, tanpa retry',
      () async {
        final gate = Completer<void>();
        addTearDown(() {
          if (!gate.isCompleted) gate.complete();
        });
        final built = _build(
          timeout: const Duration(milliseconds: 50),
          handler: (_) async {
            await gate.future;
            return _pending202();
          },
        );

        final error = await _errorOf(
          () => built.repo.schedule(PowerAction.shutdown),
        );

        expect(error, isA<TimeoutFailure>());
        expect(built.requests, hasLength(1));
      },
    );

    test('SocketException menjadi UnreachableFailure', () async {
      final built = _build(
        handler: (_) => throw const SocketException('Connection refused'),
      );

      final error = await _errorOf(
        () => built.repo.schedule(PowerAction.shutdown),
      );

      expect(error, isA<UnreachableFailure>());
      expect(built.requests, hasLength(1));
    });

    test('202 tanpa pending menjadi ServerFailure', () async {
      final built = _build(
        handler: (_) => http.Response(
          jsonEncode({'data': <String, Object?>{}}),
          202,
          headers: _jsonHeaders,
        ),
      );

      final error = await _errorOf(
        () => built.repo.schedule(PowerAction.shutdown),
      );

      expect(error, isA<ServerFailure>());
    });

    test('pending dengan action tak dikenal menjadi ServerFailure', () async {
      final built = _build(handler: (_) => _pending202(action: 'hibernate'));

      final error = await _errorOf(
        () => built.repo.schedule(PowerAction.shutdown),
      );

      expect(error, isA<ServerFailure>());
    });

    test(
      'pairing null menghasilkan UnreachableFailure tanpa request',
      () async {
        final built = _build(pairing: null);

        final error = await _errorOf(
          () => built.repo.schedule(PowerAction.shutdown),
        );

        expect(error, isA<UnreachableFailure>());
        expect(built.requests, isEmpty);
      },
    );
  });

  group('cancel', () {
    test('POST /power/cancel dengan Bearer token, tanpa body', () async {
      final built = _build(handler: (_) => _cancelled200());

      await built.repo.cancel();

      expect(built.requests, hasLength(1));
      final request = built.requests.single;
      expect(request.method, 'POST');
      expect(
        request.url,
        Uri.http('192.168.1.20:8765', '/api/v1/power/cancel'),
      );
      expect(request.headers['Authorization'], 'Bearer $_token');
      expect(request.body, isEmpty);
    });

    test('200 cancelled shutdown menjadi PowerAction.shutdown', () async {
      final built = _build(handler: (_) => _cancelled200());

      final action = await built.repo.cancel();

      expect(action, PowerAction.shutdown);
    });

    test('409 no_pending_power menjadi ServerFailure dengan code', () async {
      final built = _build(handler: (_) => _error(409, 'no_pending_power'));

      final error = await _errorOf(() => built.repo.cancel());

      expect(error, isA<ServerFailure>());
      expect((error as ApiFailure).code, 'no_pending_power');
      expect(built.requests, hasLength(1));
    });

    test('401 menjadi UnauthorizedFailure', () async {
      final built = _build(handler: (_) => _error(401, 'invalid_token'));

      final error = await _errorOf(() => built.repo.cancel());

      expect(error, isA<UnauthorizedFailure>());
      expect(built.requests, hasLength(1));
    });

    test('403 menjadi ForbiddenFailure', () async {
      final built = _build(handler: (_) => _error(403, 'forbidden_source'));

      final error = await _errorOf(() => built.repo.cancel());

      expect(error, isA<ForbiddenFailure>());
    });

    test('429 menjadi RateLimitedFailure, satu request', () async {
      final built = _build(
        handler: (_) =>
            _error(429, 'rate_limited', headers: {'Retry-After': '1'}),
      );

      final error = await _errorOf(() => built.repo.cancel());

      expect(error, isA<RateLimitedFailure>());
      expect(built.requests, hasLength(1));
    });

    test('timeout menjadi TimeoutFailure, tanpa retry', () async {
      final gate = Completer<void>();
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      final built = _build(
        timeout: const Duration(milliseconds: 50),
        handler: (_) async {
          await gate.future;
          return _cancelled200();
        },
      );

      final error = await _errorOf(() => built.repo.cancel());

      expect(error, isA<TimeoutFailure>());
      expect(built.requests, hasLength(1));
    });

    test('SocketException menjadi UnreachableFailure', () async {
      final built = _build(
        handler: (_) => throw const SocketException('Connection refused'),
      );

      final error = await _errorOf(() => built.repo.cancel());

      expect(error, isA<UnreachableFailure>());
    });

    test('cancelled dengan action tak dikenal menjadi ServerFailure', () async {
      final built = _build(handler: (_) => _cancelled200(action: 'hibernate'));

      final error = await _errorOf(() => built.repo.cancel());

      expect(error, isA<ServerFailure>());
    });

    test(
      'pairing null menghasilkan UnreachableFailure tanpa request',
      () async {
        final built = _build(pairing: null);

        final error = await _errorOf(() => built.repo.cancel());

        expect(error, isA<UnreachableFailure>());
        expect(built.requests, isEmpty);
      },
    );
  });

  test('token tidak muncul di toString failure', () async {
    final built = _build(handler: (_) => _error(401, 'invalid_token'));

    final error = await _errorOf(
      () => built.repo.schedule(PowerAction.shutdown),
    );

    expect(error, isA<UnauthorizedFailure>());
    expect(error.toString(), isNot(contains(_token)));
    expect(error.toString(), isNot(contains('Bearer')));
  });

  test(
    'pairing yang diganti antar panggilan dipakai pada panggilan berikutnya',
    () async {
      final built = _build(handler: (_) => _cancelled200());

      await built.repo.cancel();
      built.setPairing(null);
      final error = await _errorOf(() => built.repo.cancel());

      expect(error, isA<UnreachableFailure>());
      expect(built.requests, hasLength(1));
    },
  );
}
