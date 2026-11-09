import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:remotto/core/network/agent_http_client.dart';
import 'package:remotto/core/network/api_failure.dart';
import 'package:remotto/features/pairing/data/http_pairing_repository.dart';
import 'package:remotto/features/pairing/domain/pairing_target.dart';

const _token =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

const _target = PairingTarget(
  host: '10.0.0.5',
  port: 8765,
  token: _token,
  name: 'Laptop-Kamil',
);

String _okBody() {
  return jsonEncode({
    'data': {
      'name': 'Laptop-Kamil',
      'version': '1.0.0',
      'uptimeSeconds': 5,
      'volume': null,
      'pending': null,
    },
  });
}

({HttpPairingRepository repo, List<http.Request> requests}) _build({
  FutureOr<http.Response> Function(http.Request)? handler,
  Duration? timeout,
}) {
  final requests = <http.Request>[];
  final mock = MockClient((request) async {
    requests.add(request);
    if (handler != null) return handler(request);
    return http.Response(
      _okBody(),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  });
  final client = AgentHttpClient(mock);
  final repo = timeout == null
      ? HttpPairingRepository(client)
      : HttpPairingRepository(client, timeout: timeout);
  return (repo: repo, requests: requests);
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
  test('testConnection memakai host, port, dan token dari target', () async {
    final built = _build();

    final status = await built.repo.testConnection(_target);

    expect(status.name, 'Laptop-Kamil');
    expect(built.requests, hasLength(1));
    final request = built.requests.single;
    expect(request.method, 'GET');
    expect(request.url, Uri.http('10.0.0.5:8765', '/api/v1/status'));
    expect(request.headers['Authorization'], 'Bearer $_token');
  });

  test('401 dari agent diteruskan sebagai UnauthorizedFailure', () async {
    final built = _build(
      handler: (_) => http.Response(
        jsonEncode({
          'error': {'code': 'invalid_token', 'message': 'salah'},
        }),
        401,
        headers: {'content-type': 'application/json; charset=utf-8'},
      ),
    );

    final error = await _errorOf(() => built.repo.testConnection(_target));

    expect(error, isA<UnauthorizedFailure>());
  });

  test('socket gagal diteruskan sebagai UnreachableFailure', () async {
    final built = _build(
      handler: (_) => throw const SocketException('No route to host'),
    );

    final error = await _errorOf(() => built.repo.testConnection(_target));

    expect(error, isA<UnreachableFailure>());
  });

  test('timeout pairing diteruskan sebagai TimeoutFailure', () async {
    final gate = Completer<void>();
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
    });
    final built = _build(
      timeout: const Duration(milliseconds: 50),
      handler: (_) async {
        await gate.future;
        return http.Response(_okBody(), 200);
      },
    );

    final error = await _errorOf(() => built.repo.testConnection(_target));

    expect(error, isA<TimeoutFailure>());
  });

  test('pesan failure pairing tidak memuat token', () async {
    final built = _build(
      handler: (_) => throw const SocketException('gagal $_token'),
    );

    final error = await _errorOf(() => built.repo.testConnection(_target));

    expect(error.toString(), isNot(contains(_token)));
  });
}
