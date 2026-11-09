import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:remotto/core/network/agent_http_client.dart';
import 'package:remotto/core/network/api_failure.dart';
import 'package:remotto/core/storage/pairing_data.dart';
import 'package:remotto/features/remote/data/http_media_repository.dart';
import 'package:remotto/features/remote/data/media_repository.dart';

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

String _okBody(MediaAction action) {
  return jsonEncode({
    'data': {'action': action.wire},
  });
}

({
  HttpMediaRepository repo,
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
    final action = request.url.pathSegments.last;
    return http.Response(
      jsonEncode({
        'data': {'action': action},
      }),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  });
  final repo = HttpMediaRepository(
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

Future<Object?> _errorOf(Future<void> Function() call) async {
  try {
    await call();
  } catch (error) {
    return error;
  }
  return null;
}

void main() {
  test('send memakai host, port, dan token dari pairing', () async {
    final built = _build();

    await built.repo.send(MediaAction.playPause);

    expect(built.requests, hasLength(1));
    final request = built.requests.single;
    expect(request.method, 'POST');
    expect(
      request.url,
      Uri.http('192.168.1.20:8765', '/api/v1/media/play-pause'),
    );
    expect(request.headers['Authorization'], 'Bearer $_token');
    expect(request.body, isEmpty);
  });

  test('setiap aksi memakai path /media/{action} yang benar', () async {
    final built = _build();

    await built.repo.send(MediaAction.next);
    await built.repo.send(MediaAction.prev);

    expect(built.requests[0].url.path, '/api/v1/media/next');
    expect(built.requests[1].url.path, '/api/v1/media/prev');
  });

  test(
    'tanpa pairing melempar UnreachableFailure dan tidak ada request',
    () async {
      final built = _build(pairing: null);

      final error = await _errorOf(
        () => built.repo.send(MediaAction.playPause),
      );

      expect(error, isA<UnreachableFailure>());
      expect(built.requests, isEmpty);
    },
  );

  test(
    'pairing yang diganti antar panggilan dipakai pada panggilan berikutnya',
    () async {
      final built = _build(pairing: _pairingA);

      await built.repo.send(MediaAction.playPause);
      built.setPairing(_pairingB);
      await built.repo.send(MediaAction.next);

      expect(built.requests, hasLength(2));
      expect(
        built.requests[0].url,
        Uri.http('192.168.1.20:8765', '/api/v1/media/play-pause'),
      );
      expect(built.requests[0].headers['Authorization'], 'Bearer $_token');
      expect(
        built.requests[1].url,
        Uri.http('192.168.1.44:9000', '/api/v1/media/next'),
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

      await built.repo.send(MediaAction.playPause);
      built.setPairing(null);
      final error = await _errorOf(
        () => built.repo.send(MediaAction.playPause),
      );

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

    final error = await _errorOf(() => built.repo.send(MediaAction.playPause));

    expect(error, isA<UnauthorizedFailure>());
    expect(built.requests, hasLength(1));
  });

  test(
    'data.action tidak cocok dengan aksi diteruskan sebagai ServerFailure',
    () async {
      final built = _build(
        handler: (_) => http.Response(
          jsonEncode({
            'data': {'action': 'next'},
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      );

      final error = await _errorOf(
        () => built.repo.send(MediaAction.playPause),
      );

      expect(error, isA<ServerFailure>());
    },
  );

  test('500 dari agent satu request, tanpa retry', () async {
    final built = _build(
      handler: (_) => http.Response(
        jsonEncode({
          'error': {'code': 'media_failed', 'message': 'gagal'},
        }),
        500,
        headers: {'content-type': 'application/json; charset=utf-8'},
      ),
    );

    final error = await _errorOf(() => built.repo.send(MediaAction.next));

    expect(error, isA<ServerFailure>());
    expect(built.requests, hasLength(1));
  });

  test('socket gagal diteruskan sebagai UnreachableFailure', () async {
    final built = _build(
      handler: (_) => throw const SocketException('Connection refused'),
    );

    final error = await _errorOf(() => built.repo.send(MediaAction.prev));

    expect(error, isA<UnreachableFailure>());
    expect(built.requests, hasLength(1));
  });

  test('timeout satu request, tanpa retry', () async {
    final gate = Completer<void>();
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
    });
    final built = _build(
      timeout: const Duration(milliseconds: 50),
      handler: (_) async {
        await gate.future;
        return http.Response(_okBody(MediaAction.playPause), 200);
      },
    );

    final error = await _errorOf(() => built.repo.send(MediaAction.playPause));

    expect(error, isA<TimeoutFailure>());
    expect(built.requests, hasLength(1));
  });
}
