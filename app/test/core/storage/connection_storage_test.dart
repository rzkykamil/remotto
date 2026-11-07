import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotto/core/storage/connection_storage.dart';
import 'package:remotto/core/storage/pairing_data.dart';
import 'package:remotto/core/storage/storage_providers.dart';

import '../../support/fakes.dart';

const _data = PairingData(
  host: '192.168.1.20',
  port: 8443,
  token: 'secret-token-123',
  laptopName: 'LAPTOP-ABC',
);

/// Storage yang selalu melempar exception saat dibaca.
final class _ThrowingSecureStorage extends FlutterSecureStorage {
  const _ThrowingSecureStorage();

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => throw PlatformException(code: 'boom', message: 'storage rusak');
}

void main() {
  const storage = SecureConnectionStorage(FlutterSecureStorage());

  group('SecureConnectionStorage', () {
    setUp(() => FlutterSecureStorage.setMockInitialValues({}));

    test('tulis lalu baca menghasilkan data yang sama', () async {
      await storage.write(_data);
      expect(await storage.read(), _data);
    });

    test('write memakai key remotto.* persis', () async {
      FlutterSecureStorage.setMockInitialValues({});
      await storage.write(_data);
      final raw = await const FlutterSecureStorage().readAll();
      expect(raw, {
        'remotto.host': '192.168.1.20',
        'remotto.port': '8443',
        'remotto.token': 'secret-token-123',
        'remotto.laptopName': 'LAPTOP-ABC',
      });
    });

    test('satu key hilang -> null', () async {
      FlutterSecureStorage.setMockInitialValues({
        'remotto.host': '192.168.1.20',
        'remotto.port': '8443',
        'remotto.laptopName': 'LAPTOP-ABC',
      });
      expect(await storage.read(), isNull);
    });

    test('port bukan angka -> null', () async {
      FlutterSecureStorage.setMockInitialValues({
        'remotto.host': '192.168.1.20',
        'remotto.port': 'abc',
        'remotto.token': 'secret-token-123',
        'remotto.laptopName': 'LAPTOP-ABC',
      });
      expect(await storage.read(), isNull);
    });

    test('port di luar rentang 1-65535 -> null', () async {
      FlutterSecureStorage.setMockInitialValues({
        'remotto.host': '192.168.1.20',
        'remotto.port': '70000',
        'remotto.token': 'secret-token-123',
        'remotto.laptopName': 'LAPTOP-ABC',
      });
      expect(await storage.read(), isNull);
    });

    test('clear menghapus keempat key -> read null', () async {
      await storage.write(_data);
      await storage.clear();
      expect(await storage.read(), isNull);
      expect(await const FlutterSecureStorage().readAll(), isEmpty);
    });

    test('storage melempar exception -> read null, tidak crash', () async {
      const throwing = SecureConnectionStorage(_ThrowingSecureStorage());
      expect(await throwing.read(), isNull);
    });
  });

  group('pairingProvider', () {
    test('state awal dari initialPairingProvider', () {
      final container = ProviderContainer(
        overrides: [initialPairingProvider.overrideWithValue(_data)],
      );
      addTearDown(container.dispose);
      expect(container.read(pairingProvider), _data);
    });

    test(
      'save menulis storage dan mengubah state; clear menghapus keduanya',
      () async {
        final fake = InMemoryConnectionStorage();
        final container = ProviderContainer(
          overrides: [
            initialPairingProvider.overrideWithValue(null),
            connectionStorageProvider.overrideWithValue(fake),
          ],
        );
        addTearDown(container.dispose);

        expect(container.read(pairingProvider), isNull);

        await container.read(pairingProvider.notifier).save(_data);
        expect(container.read(pairingProvider), _data);
        expect(fake.data, _data);

        await container.read(pairingProvider.notifier).clear();
        expect(container.read(pairingProvider), isNull);
        expect(fake.data, isNull);
      },
    );
  });

  group('PairingData', () {
    test('toString tidak memuat token', () {
      expect(_data.toString(), isNot(contains('secret-token-123')));
      expect(_data.toString(), contains('token: ***'));
    });

    test('== dan hashCode berdasarkan nilai', () {
      const same = PairingData(
        host: '192.168.1.20',
        port: 8443,
        token: 'secret-token-123',
        laptopName: 'LAPTOP-ABC',
      );
      expect(same, _data);
      expect(same.hashCode, _data.hashCode);
    });
  });
}
