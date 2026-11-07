import 'package:flutter_test/flutter_test.dart';
import 'package:remotto/features/pairing/domain/manual_input_validator.dart';
import 'package:remotto/features/pairing/domain/pairing_target.dart';

const _token =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

PairingInvalidReason _invalidReason({
  required String address,
  String token = _token,
}) {
  final result = validateManualInput(address: address, token: token);
  expect(result, isA<PairingInvalid>(), reason: address);
  return (result as PairingInvalid).reason;
}

void main() {
  group('validateManualInput (BR-12, data-design §5)', () {
    test('alamat tanpa port memakai port default 8765', () {
      final result = validateManualInput(
        address: '192.168.1.20',
        token: _token,
      );
      expect(result, isA<PairingValid>());
      final target = (result as PairingValid).target;
      expect(target.host, '192.168.1.20');
      expect(target.port, AgentDefaults.port);
      expect(target.port, 8765);
      expect(target.token, _token);
      expect(target.name, isNull);
    });

    test('alamat dengan port eksplisit dipakai', () {
      final result = validateManualInput(
        address: '10.0.0.5:9000',
        token: _token,
      );
      expect((result as PairingValid).target.port, 9000);
    });

    test('token di-trim dan dijadikan huruf kecil', () {
      final upper = _token.toUpperCase();
      final result = validateManualInput(
        address: '192.168.1.20',
        token: '  $upper  ',
      );
      expect((result as PairingValid).target.token, _token);
    });

    test('spasi di sekitar alamat diabaikan', () {
      final result = validateManualInput(
        address: '  192.168.1.20:8765 ',
        token: _token,
      );
      expect((result as PairingValid).target.host, '192.168.1.20');
    });

    test('rentang privat dan Tailscale diterima', () {
      for (final address in [
        '10.1.2.3',
        '172.20.0.9',
        '192.168.0.1',
        '100.100.1.1',
      ]) {
        expect(
          validateManualInput(address: address, token: _token),
          isA<PairingValid>(),
          reason: address,
        );
      }
    });

    test('format alamat salah -> invalidAddress', () {
      for (final address in [
        '',
        'laptop',
        '192.168.1',
        '192.168.1.1.1',
        '192.168.1.300',
        '192.168.1.1:80:90',
        'http://192.168.1.1',
        '192.168.01.1',
      ]) {
        expect(
          _invalidReason(address: address),
          PairingInvalidReason.invalidAddress,
          reason: address,
        );
      }
    });

    test('host publik ditolak -> invalidHost', () {
      expect(
        _invalidReason(address: '8.8.8.8'),
        PairingInvalidReason.invalidHost,
      );
      expect(
        _invalidReason(address: '100.63.0.1'),
        PairingInvalidReason.invalidHost,
      );
      expect(
        _invalidReason(address: '172.32.0.1'),
        PairingInvalidReason.invalidHost,
      );
    });

    test('port tidak valid -> invalidPort', () {
      expect(
        _invalidReason(address: '192.168.1.1:abc'),
        PairingInvalidReason.invalidPort,
      );
      expect(
        _invalidReason(address: '192.168.1.1:0'),
        PairingInvalidReason.invalidPort,
      );
      expect(
        _invalidReason(address: '192.168.1.1:65536'),
        PairingInvalidReason.invalidPort,
      );
      expect(
        _invalidReason(address: '192.168.1.1:-1'),
        PairingInvalidReason.invalidPort,
      );
      expect(
        _invalidReason(address: '192.168.1.1:'),
        PairingInvalidReason.invalidPort,
      );
    });

    test('port 1 dan 65535 diterima', () {
      expect(
        validateManualInput(address: '192.168.1.1:1', token: _token),
        isA<PairingValid>(),
      );
      expect(
        validateManualInput(address: '192.168.1.1:65535', token: _token),
        isA<PairingValid>(),
      );
    });

    test('token 63 atau 65 karakter, atau bukan hex -> invalidToken', () {
      expect(
        _invalidReason(address: '192.168.1.1', token: _token.substring(1)),
        PairingInvalidReason.invalidToken,
      );
      expect(
        _invalidReason(address: '192.168.1.1', token: '${_token}0'),
        PairingInvalidReason.invalidToken,
      );
      expect(
        _invalidReason(
          address: '192.168.1.1',
          token: 'g${_token.substring(1)}',
        ),
        PairingInvalidReason.invalidToken,
      );
      expect(
        _invalidReason(address: '192.168.1.1', token: ''),
        PairingInvalidReason.invalidToken,
      );
    });
  });
}
