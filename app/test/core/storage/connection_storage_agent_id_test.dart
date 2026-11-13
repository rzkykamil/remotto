import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotto/core/storage/connection_storage.dart';
import 'package:remotto/core/storage/pairing_data.dart';
import 'package:remotto/core/storage/storage_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fakes.dart';

const _agentId = 'a3f1c9e0b72d4e85916f0c2d7b4e13a8';

const _withId = PairingData(
  host: '192.168.1.20',
  port: 8765,
  token: 'secret-token-123',
  laptopName: 'LAPTOP-ABC',
  agentId: _agentId,
);

const _legacy = PairingData(
  host: '192.168.1.20',
  port: 8765,
  token: 'secret-token-123',
  laptopName: 'LAPTOP-ABC',
);

/// Storage yang melempar exception hanya saat key agentId dibaca.
final class _FailOnAgentIdStorage extends FlutterSecureStorage {
  const _FailOnAgentIdStorage();

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) {
    if (key == SecureConnectionStorage.keyAgentId) {
      throw PlatformException(code: 'boom', message: 'agentId rusak');
    }
    return super.read(
      key: key,
      iOptions: iOptions,
      aOptions: aOptions,
      lOptions: lOptions,
      webOptions: webOptions,
      mOptions: mOptions,
      wOptions: wOptions,
    );
  }
}

/// Storage in-memory yang menahan tulis pertama lewat [gate] dan bisa dibuat
/// gagal sekali lewat [failNextWrite].
final class _GatedStorage implements ConnectionStorage {
  _GatedStorage([this.data]);

  PairingData? data;
  Completer<void>? gate;
  bool failNextWrite = false;

  @override
  Future<PairingData?> read() async => data;

  @override
  Future<void> write(PairingData value) async {
    final pending = gate;
    if (pending != null) {
      gate = null;
      await pending.future;
    }
    if (failNextWrite) {
      failNextWrite = false;
      throw StateError('tulis gagal');
    }
    data = value;
  }

  @override
  Future<void> clear() async => data = null;
}

/// Seperti [_containerWith], tetapi juga meng-override SharedPreferences agar
/// `save` dan `clear` (yang menyentuh lastPowerCommand) bisa dijalankan.
Future<ProviderContainer> _containerWithPrefs(
  PairingData? initial,
  ConnectionStorage storage,
) async {
  SharedPreferences.setMockInitialValues({});
  final container = ProviderContainer(
    overrides: [
      initialPairingProvider.overrideWithValue(initial),
      connectionStorageProvider.overrideWithValue(storage),
      sharedPreferencesProvider.overrideWithValue(
        await SharedPreferences.getInstance(),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

ProviderContainer _containerWith(
  PairingData? initial, [
  ConnectionStorage? storage,
]) {
  final container = ProviderContainer(
    overrides: [
      initialPairingProvider.overrideWithValue(initial),
      connectionStorageProvider.overrideWithValue(
        storage ?? InMemoryConnectionStorage(),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  const storage = SecureConnectionStorage(FlutterSecureStorage());

  group('PairingData agentId', () {
    test('agentId ikut ==, dan null berbeda dari terisi', () {
      expect(_withId == _legacy, isFalse);
      expect(
        _withId,
        const PairingData(
          host: '192.168.1.20',
          port: 8765,
          token: 'secret-token-123',
          laptopName: 'LAPTOP-ABC',
          agentId: _agentId,
        ),
      );
    });

    test('toString memuat agentId tetapi token tetap ***', () {
      final text = _withId.toString();
      expect(text, contains(_agentId));
      expect(text, contains('token: ***'));
      expect(text, isNot(contains('secret-token-123')));
    });
  });

  group('SecureConnectionStorage agentId', () {
    setUp(() => FlutterSecureStorage.setMockInitialValues({}));

    test('pairing tanpa agentId tetap terbaca dengan agentId null', () async {
      FlutterSecureStorage.setMockInitialValues({
        'remotto.host': '192.168.1.20',
        'remotto.port': '8765',
        'remotto.token': 'secret-token-123',
        'remotto.laptopName': 'LAPTOP-ABC',
      });
      expect(await storage.read(), _legacy);
    });

    test('round-trip dengan agentId mengembalikan data yang sama', () async {
      await storage.write(_withId);
      expect(await storage.read(), _withId);
      final raw = await const FlutterSecureStorage().readAll();
      expect(raw['remotto.agentId'], _agentId);
    });

    test('write dengan agentId null tidak menulis key agentId', () async {
      await storage.write(_legacy);
      final raw = await const FlutterSecureStorage().readAll();
      expect(raw.containsKey('remotto.agentId'), isFalse);
    });

    test('write dengan agentId null menghapus agentId lama', () async {
      await storage.write(_withId);
      await storage.write(_legacy);
      expect(await storage.read(), _legacy);
    });

    test('clear juga menghapus key agentId', () async {
      await storage.write(_withId);
      await storage.clear();
      expect(await const FlutterSecureStorage().readAll(), isEmpty);
    });

    test('agentId gagal dibaca tidak membuat pairing null', () async {
      await storage.write(_legacy);
      const failing = SecureConnectionStorage(_FailOnAgentIdStorage());
      expect(await failing.read(), _legacy);
    });
  });

  group('PairingNotifier updateEndpoint dan backfillAgentId', () {
    test('updateEndpoint mengganti host dan port saja', () async {
      final container = _containerWith(_withId);
      await container
          .read(pairingProvider.notifier)
          .updateEndpoint(host: '10.0.0.7', port: 9000);

      final next = container.read(pairingProvider)!;
      expect(next.host, '10.0.0.7');
      expect(next.port, 9000);
      expect(next.token, _withId.token);
      expect(next.laptopName, _withId.laptopName);
      expect(next.agentId, _agentId);
    });

    test('updateEndpoint menulis storage dulu', () async {
      final fake = InMemoryConnectionStorage(_withId);
      final container = _containerWith(_withId, fake);
      await container
          .read(pairingProvider.notifier)
          .updateEndpoint(host: '10.0.0.7', port: 9000);
      expect(fake.data, container.read(pairingProvider));
      expect(fake.data!.host, '10.0.0.7');
    });

    test('updateEndpoint tanpa pairing tidak melakukan apa pun', () async {
      final container = _containerWith(null);
      await container
          .read(pairingProvider.notifier)
          .updateEndpoint(host: '10.0.0.7', port: 9000);
      expect(container.read(pairingProvider), isNull);
    });

    test('backfillAgentId mengisi pairing lama', () async {
      final container = _containerWith(_legacy);
      await container.read(pairingProvider.notifier).backfillAgentId(_agentId);
      expect(container.read(pairingProvider)!.agentId, _agentId);
      expect(container.read(pairingProvider)!.host, _legacy.host);
    });

    test('backfillAgentId tidak menimpa agentId yang sudah ada', () async {
      final container = _containerWith(_withId);
      await container.read(pairingProvider.notifier).backfillAgentId('0' * 32);
      expect(container.read(pairingProvider), _withId);
    });

    test(
      'backfillAgentId tanpa pairing atau id tidak valid diabaikan',
      () async {
        final empty = _containerWith(null);
        await empty.read(pairingProvider.notifier).backfillAgentId(_agentId);
        expect(empty.read(pairingProvider), isNull);

        final legacy = _containerWith(_legacy);
        await legacy.read(pairingProvider.notifier).backfillAgentId('ABC');
        expect(legacy.read(pairingProvider), _legacy);
      },
    );
  });

  group('PairingNotifier serialisasi tulis', () {
    test(
      'updateEndpoint tertahan, lalu clear: state null dan storage kosong',
      () async {
        final fake = _GatedStorage(_withId);
        final container = await _containerWithPrefs(_withId, fake);
        final notifier = container.read(pairingProvider.notifier);

        fake.gate = Completer<void>();
        final endpoint = notifier.updateEndpoint(host: '10.0.0.7', port: 9000);
        final cleared = notifier.clear();

        // clear menunggu updateEndpoint yang masih tertahan di storage.
        expect(container.read(pairingProvider), _withId);

        fake.gate!.complete();
        await endpoint;
        await cleared;

        expect(container.read(pairingProvider), isNull);
        expect(fake.data, isNull);
      },
    );

    test(
      'backfillAgentId tertahan, lalu save pairing baru: pairing baru utuh',
      () async {
        final fake = _GatedStorage(_legacy);
        final container = await _containerWithPrefs(_legacy, fake);
        final notifier = container.read(pairingProvider.notifier);
        const replacement = PairingData(
          host: '10.0.0.9',
          port: 8443,
          token: 'token-baru-456',
          laptopName: 'LAPTOP-BARU',
          agentId: _agentId,
        );

        fake.gate = Completer<void>();
        final backfill = notifier.backfillAgentId('1' * 32);
        final saved = notifier.save(replacement);

        fake.gate!.complete();
        await backfill;
        await saved;

        expect(container.read(pairingProvider), replacement);
        expect(fake.data, replacement);
      },
    );

    test('tulis yang gagal tidak meracuni antrean berikutnya', () async {
      final fake = _GatedStorage(_withId);
      final container = _containerWith(_withId, fake);
      final notifier = container.read(pairingProvider.notifier);

      fake.failNextWrite = true;
      await expectLater(
        notifier.updateEndpoint(host: '10.0.0.7', port: 9000),
        throwsStateError,
      );
      expect(container.read(pairingProvider), _withId);

      await notifier.updateEndpoint(host: '10.0.0.8', port: 9001);
      expect(container.read(pairingProvider)!.host, '10.0.0.8');
      expect(fake.data!.host, '10.0.0.8');
    });
  });
}
