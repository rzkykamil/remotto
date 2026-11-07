import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:remotto/features/pairing/domain/pairing_target.dart';
import 'package:remotto/features/pairing/domain/qr_payload_validator.dart';

const _token =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

String _payload({
  Object? v = 1,
  Object? name = 'Laptop Kamar',
  Object? host = '192.168.1.10',
  Object? port = 8765,
  Object? token = _token,
  Map<String, Object?> extra = const {},
}) {
  final map = <String, Object?>{
    'v': v,
    'name': name,
    'host': host,
    'port': port,
    'token': token,
    ...extra,
  };
  return jsonEncode(map);
}

void _expectInvalid(String raw, PairingInvalidReason reason) {
  final result = validateQrPayload(raw);
  expect(result, isA<PairingInvalid>(), reason: raw);
  expect((result as PairingInvalid).reason, reason, reason: raw);
}

void main() {
  group('validateQrPayload (BR-12, data-design §5)', () {
    test('payload valid menghasilkan target dengan field yang benar', () {
      final result = validateQrPayload(_payload());
      expect(result, isA<PairingValid>());
      final target = (result as PairingValid).target;
      expect(target.host, '192.168.1.10');
      expect(target.port, 8765);
      expect(target.token, _token);
      expect(target.name, 'Laptop Kamar');
    });

    test('name di-trim sebelum dipakai', () {
      final result = validateQrPayload(_payload(name: '  Laptop  '));
      expect((result as PairingValid).target.name, 'Laptop');
    });

    test('field tak dikenal diabaikan', () {
      final result = validateQrPayload(
        _payload(extra: {'extra': 'x', 'nested': {}}),
      );
      expect(result, isA<PairingValid>());
    });

    test('rentang privat 10/8, 172.16/12, 172.31.x, 100.64/10 diterima', () {
      for (final host in [
        '10.0.0.1',
        '172.16.0.1',
        '172.31.255.254',
        '100.64.0.1',
        '100.127.255.1',
      ]) {
        expect(
          validateQrPayload(_payload(host: host)),
          isA<PairingValid>(),
          reason: host,
        );
      }
    });

    test('bukan JSON -> notJsonObject', () {
      _expectInvalid('ini bukan json', PairingInvalidReason.notJsonObject);
    });

    test('JSON bukan objek (array, string, angka) -> notJsonObject', () {
      _expectInvalid('[1,2,3]', PairingInvalidReason.notJsonObject);
      _expectInvalid('"teks"', PairingInvalidReason.notJsonObject);
      _expectInvalid('42', PairingInvalidReason.notJsonObject);
    });

    test('teks lebih dari 256 byte UTF-8 -> tooLarge', () {
      final longName = 'a' * 200;
      final raw = _payload(name: longName, extra: {'pad': 'x' * 60});
      expect(utf8.encode(raw).length, greaterThan(256));
      _expectInvalid(raw, PairingInvalidReason.tooLarge);
    });

    test('tepat 256 byte UTF-8 tidak ditolak karena ukuran', () {
      final empty = _payload(extra: {'p': ''});
      final pad = 256 - utf8.encode(empty).length;
      final raw = _payload(extra: {'p': 'x' * pad});
      expect(utf8.encode(raw).length, 256);
      expect(validateQrPayload(raw), isA<PairingValid>());
    });

    test('byte UTF-8 multibyte dihitung sebagai byte, bukan karakter', () {
      // 100 characters of "é" = 200 bytes; adding the other fields exceeds 256.
      final raw = _payload(extra: {'p': 'é' * 100});
      expect(raw.length, lessThan(256));
      expect(utf8.encode(raw).length, greaterThan(256));
      _expectInvalid(raw, PairingInvalidReason.tooLarge);
    });

    test('v salah (2, "1", 1.0, hilang) -> unsupportedVersion', () {
      _expectInvalid(_payload(v: 2), PairingInvalidReason.unsupportedVersion);
      _expectInvalid(_payload(v: '1'), PairingInvalidReason.unsupportedVersion);
      _expectInvalid(_payload(v: 1.0), PairingInvalidReason.unsupportedVersion);
      final noVersion = jsonEncode({
        'name': 'L',
        'host': '192.168.1.10',
        'port': 8765,
        'token': _token,
      });
      _expectInvalid(noVersion, PairingInvalidReason.unsupportedVersion);
    });

    test('name hilang, bukan string, kosong, atau >64 -> invalidName', () {
      _expectInvalid(_payload(name: null), PairingInvalidReason.invalidName);
      _expectInvalid(_payload(name: 12), PairingInvalidReason.invalidName);
      _expectInvalid(_payload(name: '   '), PairingInvalidReason.invalidName);
      _expectInvalid(
        _payload(name: 'a' * 65),
        PairingInvalidReason.invalidName,
      );
    });

    test('name tepat 64 karakter diterima', () {
      expect(validateQrPayload(_payload(name: 'a' * 64)), isA<PairingValid>());
    });

    test('host hilang, bukan string, atau bukan IPv4 -> invalidHost', () {
      _expectInvalid(_payload(host: null), PairingInvalidReason.invalidHost);
      _expectInvalid(_payload(host: 1921), PairingInvalidReason.invalidHost);
      _expectInvalid(
        _payload(host: 'laptop.local'),
        PairingInvalidReason.invalidHost,
      );
      _expectInvalid(
        _payload(host: '192.168.1'),
        PairingInvalidReason.invalidHost,
      );
      _expectInvalid(
        _payload(host: '192.168.1.256'),
        PairingInvalidReason.invalidHost,
      );
      _expectInvalid(
        _payload(host: '192.168.01.10'),
        PairingInvalidReason.invalidHost,
      );
    });

    test('host publik ditolak: 8.8.8.8, 100.63.x, 172.32.x -> invalidHost', () {
      _expectInvalid(
        _payload(host: '8.8.8.8'),
        PairingInvalidReason.invalidHost,
      );
      _expectInvalid(
        _payload(host: '100.63.0.1'),
        PairingInvalidReason.invalidHost,
      );
      _expectInvalid(
        _payload(host: '100.128.0.1'),
        PairingInvalidReason.invalidHost,
      );
      _expectInvalid(
        _payload(host: '172.32.0.1'),
        PairingInvalidReason.invalidHost,
      );
      _expectInvalid(
        _payload(host: '172.15.0.1'),
        PairingInvalidReason.invalidHost,
      );
    });

    test('port hilang, bukan int, 0, 65536 -> invalidPort', () {
      _expectInvalid(_payload(port: null), PairingInvalidReason.invalidPort);
      _expectInvalid(_payload(port: '8765'), PairingInvalidReason.invalidPort);
      _expectInvalid(_payload(port: 8765.0), PairingInvalidReason.invalidPort);
      _expectInvalid(_payload(port: 0), PairingInvalidReason.invalidPort);
      _expectInvalid(_payload(port: 65536), PairingInvalidReason.invalidPort);
    });

    test('port 1 dan 65535 diterima', () {
      expect(validateQrPayload(_payload(port: 1)), isA<PairingValid>());
      expect(validateQrPayload(_payload(port: 65535)), isA<PairingValid>());
    });

    test('token 63 karakter, 65 karakter, huruf besar -> invalidToken', () {
      _expectInvalid(
        _payload(token: _token.substring(1)),
        PairingInvalidReason.invalidToken,
      );
      _expectInvalid(
        _payload(token: '${_token}0'),
        PairingInvalidReason.invalidToken,
      );
      _expectInvalid(
        _payload(token: _token.toUpperCase()),
        PairingInvalidReason.invalidToken,
      );
      _expectInvalid(_payload(token: null), PairingInvalidReason.invalidToken);
    });
  });
}
