import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:remotto/core/connection/http_status_repository.dart';
import 'package:remotto/core/network/agent_http_client.dart';
import 'package:remotto/core/network/api_failure.dart';
import 'package:remotto/core/storage/pairing_data.dart';

const _token =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

const _pairingA = PairingData(
  host: '192.168.1.20',
  port: 8765,
  token: _token,
  laptopName: 'Laptop-Kamil',
);

const _pairingB = PairingData(
  host: '192.168.1.44',
  port: 9000,
  token: 'fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210',
  laptopName: 'Laptop-Lain',
);

String _okBody() {
  return jsonEncode({
    'data': {
      'name': 'Laptop-Kamil',
      'version': '1.0.0',
      'uptimeSeconds': 120,
      'volume': {'level': 20, 'muted': false},
      'pending': null,
    },
  });
}

({
  HttpStatusRepository repo,
  List<http.Request> requests,
  void Function(PairingData?) setPairing,
})
_build({
  PairingData? pairing = _pairingA,
  FutureOr<http.Response> Function(http.Request)? handler,
  Duration timeout = const Duration(seconds: 3),
}) {
  final requests = <http.Request>[];
  var current = pairing;
  final mock = MockClient((request) async {
    requests.add(request);
    if (handler != null) return handler(request);
    return http.Response(
      _okBody(),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  });
  final repo = HttpStatusRepository(
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
  test('fetchStatus memakai host, port, dan token dari pairing', () async {
    final built = _build();

    final status = await built.repo.fetchStatus();

    expect(status.name, 'Laptop-Kamil');
    expect(built.requests, hasLength(1));
    final request = built.requests.single;
    expect(request.url, Uri.http('192.168.1.20:8765', '/api/v1/status'));
    expect(request.headers['Authorization'], 'Bearer $_token');
  });

  test(
    'tanpa pairing melempar UnreachableFailure dan tidak ada request',
    () async {
      final built = _build(pairing: null);

      final error = await _errorOf(built.repo.fetchStatus);

      expect(error, isA<UnreachableFailure>());
      expect(built.requests, isEmpty);
    },
  );

  test(
    'pairing yang diganti antar panggilan dipakai pada panggilan berikutnya',
    () async {
      final built = _build(pairing: _pairingA);

      await built.repo.fetchStatus();
      built.setPairing(_pairingB);
      await built.repo.fetchStatus();

      expect(built.requests, hasLength(2));
      expect(
        built.requests[0].url,
        Uri.http('192.168.1.20:8765', '/api/v1/status'),
      );
      expect(built.requests[0].headers['Authorization'], 'Bearer $_token');
      expect(
        built.requests[1].url,
        Uri.http('192.168.1.44:9000', '/api/v1/status'),
      );
      expect(
        built.requests[1].headers['Authorization'],
        'Bearer ${_pairingB.token}',
      );
    },
  );

  test(
    'pairing yang dihapus (null) pada panggilan berikutnya tidak request',
    () async {
      final built = _build(pairing: _pairingA);

      await built.repo.fetchStatus();
      built.setPairing(null);
      final error = await _errorOf(built.repo.fetchStatus);

      expect(error, isA<UnreachableFailure>());
      expect(built.requests, hasLength(1));
    },
  );

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

    final error = await _errorOf(built.repo.fetchStatus);

    expect(error, isA<UnauthorizedFailure>());
  });

  test('socket gagal diteruskan sebagai UnreachableFailure', () async {
    final built = _build(
      handler: (_) => throw const SocketException('Connection refused'),
    );

    final error = await _errorOf(built.repo.fetchStatus);

    expect(error, isA<UnreachableFailure>());
  });

  test('timeout polling diteruskan sebagai TimeoutFailure', () async {
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

    final error = await _errorOf(built.repo.fetchStatus);

    expect(error, isA<TimeoutFailure>());
  });
}
