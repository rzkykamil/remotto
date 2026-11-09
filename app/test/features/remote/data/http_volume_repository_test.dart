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
import 'package:remotto/features/remote/data/http_volume_repository.dart';

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

http.Response _okVolume({int level = 50, bool muted = false}) {
  return http.Response(
    jsonEncode({
      'data': {'level': level, 'muted': muted},
    }),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}

http.Response _error(int status, String code) {
  return http.Response(
    jsonEncode({
      'error': {'code': code, 'message': 'x'},
    }),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}

({
  HttpVolumeRepository repo,
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
    return _okVolume();
  });
  final repo = HttpVolumeRepository(
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
  test('setLevel memakai host, port, dan token dari pairing', () async {
    final built = _build();

    final volume = await built.repo.setLevel(60);

    expect(volume, const VolumeStatus(level: 50, muted: false));
    expect(built.requests, hasLength(1));
    final request = built.requests.single;
    expect(request.method, 'PUT');
    expect(request.url, Uri.http('192.168.1.20:8765', '/api/v1/volume'));
    expect(request.headers['Authorization'], 'Bearer $_token');
    expect(jsonDecode(request.body), {'level': 60});
  });

  test('up dan down memakai path /volume/up dan /volume/down', () async {
    final built = _build();

    await built.repo.up();
    await built.repo.down();

    expect(built.requests, hasLength(2));
    expect(built.requests[0].method, 'POST');
    expect(built.requests[0].url.path, '/api/v1/volume/up');
    expect(built.requests[0].body, isEmpty);
    expect(built.requests[1].method, 'POST');
    expect(built.requests[1].url.path, '/api/v1/volume/down');
    expect(built.requests[1].body, isEmpty);
  });

  test('setMuted mengirim body muted ke /volume/mute', () async {
    final built = _build();

    await built.repo.setMuted(true);

    final request = built.requests.single;
    expect(request.method, 'POST');
    expect(request.url.path, '/api/v1/volume/mute');
    expect(request.headers['Authorization'], 'Bearer $_token');
    expect(jsonDecode(request.body), {'muted': true});
  });

  test(
    'tanpa pairing melempar UnreachableFailure dan tidak ada request',
    () async {
      final built = _build(pairing: null);

      final error = await _errorOf(() => built.repo.setLevel(40));
      final errorUp = await _errorOf(() => built.repo.up());
      final errorDown = await _errorOf(() => built.repo.down());
      final errorMute = await _errorOf(() => built.repo.setMuted(true));

      expect(error, isA<UnreachableFailure>());
      expect(errorUp, isA<UnreachableFailure>());
      expect(errorDown, isA<UnreachableFailure>());
      expect(errorMute, isA<UnreachableFailure>());
      expect(built.requests, isEmpty);
    },
  );

  test(
    'pairing yang diganti antar panggilan dipakai pada panggilan berikutnya',
    () async {
      final built = _build(pairing: _pairingA);

      await built.repo.up();
      built.setPairing(_pairingB);
      await built.repo.setLevel(30);

      expect(built.requests, hasLength(2));
      expect(
        built.requests[0].url,
        Uri.http('192.168.1.20:8765', '/api/v1/volume/up'),
      );
      expect(built.requests[0].headers['Authorization'], 'Bearer $_token');
      expect(
        built.requests[1].url,
        Uri.http('192.168.1.44:9000', '/api/v1/volume'),
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

      await built.repo.up();
      built.setPairing(null);
      final error = await _errorOf(() => built.repo.down());

      expect(error, isA<UnreachableFailure>());
      expect(built.requests, hasLength(1));
    },
  );

  test('401 dari agent diteruskan sebagai UnauthorizedFailure', () async {
    final built = _build(handler: (_) => _error(401, 'invalid_token'));

    final error = await _errorOf(() => built.repo.up());

    expect(error, isA<UnauthorizedFailure>());
    expect(built.requests, hasLength(1));
  });

  test(
    '429 dari agent diteruskan sebagai RateLimitedFailure, satu request',
    () async {
      final built = _build(
        handler: (_) => http.Response(
          jsonEncode({
            'error': {'code': 'rate_limited', 'message': 'x'},
          }),
          429,
          headers: {
            'content-type': 'application/json; charset=utf-8',
            'Retry-After': '1',
          },
        ),
      );

      final error = await _errorOf(() => built.repo.setMuted(false));

      expect(error, isA<RateLimitedFailure>());
      expect(built.requests, hasLength(1));
    },
  );

  test('500 audio_failed dari agent satu request, tanpa retry', () async {
    final built = _build(handler: (_) => _error(500, 'audio_failed'));

    final error = await _errorOf(() => built.repo.setLevel(70));

    expect(error, isA<ServerFailure>());
    expect((error as ApiFailure).code, 'audio_failed');
    expect(built.requests, hasLength(1));
  });

  test('socket gagal diteruskan sebagai UnreachableFailure', () async {
    final built = _build(
      handler: (_) => throw const SocketException('Connection refused'),
    );

    final error = await _errorOf(() => built.repo.down());

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
        return _okVolume();
      },
    );

    final error = await _errorOf(() => built.repo.up());

    expect(error, isA<TimeoutFailure>());
    expect(built.requests, hasLength(1));
  });
}
