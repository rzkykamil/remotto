import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:remotto/features/pairing/domain/pairing_target.dart';
import 'package:remotto/features/pairing/domain/qr_payload_validator.dart';

const _token =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
const _agentId = 'a3f1c9e0b72d4e85916f0c2d7b4e13a8';

String _payload(Map<String, Object?> extra) => jsonEncode({
  'v': 1,
  'name': 'Laptop Kamar',
  'host': '192.168.1.10',
  'port': 8765,
  'token': _token,
  ...extra,
});

void main() {
  group('validateQrPayload id (data-design §5, M7)', () {
    test('QR tanpa id (sebelum M7) tetap valid dengan agentId null', () {
      final result = validateQrPayload(_payload({}));
      expect(result, isA<PairingValid>());
      expect((result as PairingValid).target.agentId, isNull);
    });

    test('id 32 hex valid dan terbawa ke target', () {
      final result = validateQrPayload(_payload({'id': _agentId}));
      expect(result, isA<PairingValid>());
      expect((result as PairingValid).target.agentId, _agentId);
    });

    test('id bentuk salah ditolak dengan invalidAgentId', () {
      const badValues = <Object?>[
        'ABCDEF0123456789ABCDEF0123456789', // huruf besar
        'a3f1c9e0b72d4e85916f0c2d7b4e13a', // 31 karakter
        'a3f1c9e0b72d4e85916f0c2d7b4e13a88', // 33 karakter
        '',
        123,
        null, // ada tetapi null
        ['a3f1c9e0b72d4e85916f0c2d7b4e13a8'],
      ];
      for (final bad in badValues) {
        final result = validateQrPayload(_payload({'id': bad}));
        expect(result, isA<PairingInvalid>(), reason: '$bad');
        expect(
          (result as PairingInvalid).reason,
          PairingInvalidReason.invalidAgentId,
          reason: '$bad',
        );
      }
    });

    test('QR dengan id di batas ukuran 256 byte tetap diterima', () {
      final raw = _payload({'id': _agentId, 'name': 'N' * 64});
      // Ukuran dihitung ulang: id dan nama panjang tetap di bawah 256 byte.
      expect(utf8.encode(raw).length, lessThanOrEqualTo(256));
      expect(validateQrPayload(raw), isA<PairingValid>());
    });
  });
}
