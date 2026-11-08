import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:remotto/core/network/agent_status.dart';
import 'package:remotto/core/network/api_failure.dart';

String _envelope(Map<String, Object?> data) => jsonEncode({'data': data});

Map<String, Object?> _data({
  Object? volume = const {'level': 35, 'muted': false},
  Object? pending,
}) {
  return {
    'name': 'Laptop-Kamil',
    'version': '1.0.0',
    'uptimeSeconds': 11520,
    'volume': volume,
    'pending': pending,
  };
}

void main() {
  group('parseStatusResponse sukses', () {
    test('membaca envelope lengkap dengan volume dan tanpa pending', () {
      final status = parseStatusResponse(200, _envelope(_data()));

      expect(status.name, 'Laptop-Kamil');
      expect(status.version, '1.0.0');
      expect(status.uptimeSeconds, 11520);
      expect(status.volume, const VolumeStatus(level: 35, muted: false));
      expect(status.pending, isNull);
    });

    test('volume null dibaca sebagai null, status tetap 200', () {
      final status = parseStatusResponse(200, _envelope(_data(volume: null)));

      expect(status.volume, isNull);
      expect(status.name, 'Laptop-Kamil');
    });

    test('pending terisi memakai remainingMs dan delayMs (BR-20)', () {
      final status = parseStatusResponse(
        200,
        _envelope(
          _data(
            pending: {
              'action': 'shutdown',
              'remainingMs': 3200,
              'delayMs': 5000,
              'scheduledAt': '2026-01-01T23:41:00+07:00',
            },
          ),
        ),
      );

      final pending = status.pending!;
      expect(pending.action, 'shutdown');
      expect(pending.remainingMs, 3200);
      expect(pending.delayMs, 5000);
      expect(pending.scheduledAt, '2026-01-01T23:41:00+07:00');
    });

    test('dua pembacaan dengan isi sama saling sama', () {
      final a = parseStatusResponse(200, _envelope(_data()));
      final b = parseStatusResponse(200, _envelope(_data()));

      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });
  });

  group('parseStatusResponse gagal', () {
    test('401 menjadi UnauthorizedFailure dengan code invalid_token', () {
      final body = jsonEncode({
        'error': {'code': 'invalid_token', 'message': 'Token salah'},
      });

      expect(
        () => parseStatusResponse(401, body),
        throwsA(
          isA<UnauthorizedFailure>().having(
            (f) => f.code,
            'code',
            'invalid_token',
          ),
        ),
      );
    });

    test('403 menjadi ForbiddenFailure', () {
      final body = jsonEncode({
        'error': {'code': 'forbidden_network', 'message': 'x'},
      });

      expect(
        () => parseStatusResponse(403, body),
        throwsA(isA<ForbiddenFailure>()),
      );
    });

    test('429 membaca Retry-After tanpa memedulikan huruf header', () {
      final body = jsonEncode({
        'error': {'code': 'rate_limited', 'message': 'x'},
      });

      expect(
        () => parseStatusResponse(
          429,
          body,
          headers: const {'RETRY-AFTER': '12'},
        ),
        throwsA(
          isA<RateLimitedFailure>().having(
            (f) => f.retryAfter,
            'retryAfter',
            const Duration(seconds: 12),
          ),
        ),
      );
    });

    test('500 menjadi ServerFailure dengan code dari envelope', () {
      final body = jsonEncode({
        'error': {'code': 'internal', 'message': 'x'},
      });

      expect(
        () => parseStatusResponse(500, body),
        throwsA(isA<ServerFailure>().having((f) => f.code, 'code', 'internal')),
      );
    });

    test('500 dengan body bukan JSON tetap menjadi ServerFailure', () {
      expect(
        () => parseStatusResponse(500, '<html>proxy</html>'),
        throwsA(isA<ServerFailure>().having((f) => f.code, 'code', isNull)),
      );
    });

    test('200 dengan body bukan JSON menjadi ServerFailure', () {
      expect(
        () => parseStatusResponse(200, 'bukan json'),
        throwsA(isA<ServerFailure>()),
      );
    });

    test('field wajib hilang menjadi ServerFailure', () {
      final data = _data()..remove('version');

      expect(
        () => parseStatusResponse(200, _envelope(data)),
        throwsA(isA<ServerFailure>()),
      );
    });

    test('volume di luar 0 sampai 100 menjadi ServerFailure', () {
      expect(
        () => parseStatusResponse(
          200,
          _envelope(_data(volume: {'level': 101, 'muted': false})),
        ),
        throwsA(isA<ServerFailure>()),
      );
    });
  });

  group('VolumeStatus.fromData', () {
    test('membaca level dan muted yang valid', () {
      final volume = VolumeStatus.fromData({'level': 60, 'muted': true});

      expect(volume, const VolumeStatus(level: 60, muted: true));
    });

    test('level 0 dan 100 diterima sebagai batas', () {
      expect(VolumeStatus.fromData({'level': 0, 'muted': false}).level, 0);
      expect(VolumeStatus.fromData({'level': 100, 'muted': false}).level, 100);
    });

    test('level 101 menjadi ServerFailure', () {
      expect(
        () => VolumeStatus.fromData({'level': 101, 'muted': false}),
        throwsA(isA<ServerFailure>()),
      );
    });

    test('level -1 menjadi ServerFailure', () {
      expect(
        () => VolumeStatus.fromData({'level': -1, 'muted': false}),
        throwsA(isA<ServerFailure>()),
      );
    });

    test('level berupa string menjadi ServerFailure', () {
      expect(
        () => VolumeStatus.fromData({'level': '35', 'muted': false}),
        throwsA(isA<ServerFailure>()),
      );
    });

    test('muted bukan bool menjadi ServerFailure', () {
      expect(
        () => VolumeStatus.fromData({'level': 35, 'muted': 'false'}),
        throwsA(isA<ServerFailure>()),
      );
    });

    test('key level hilang menjadi ServerFailure', () {
      expect(
        () => VolumeStatus.fromData({'muted': false}),
        throwsA(isA<ServerFailure>()),
      );
    });

    test('key muted hilang menjadi ServerFailure', () {
      expect(
        () => VolumeStatus.fromData({'level': 35}),
        throwsA(isA<ServerFailure>()),
      );
    });
  });
}
