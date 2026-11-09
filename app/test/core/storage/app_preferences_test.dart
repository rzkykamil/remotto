import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotto/core/connection/connection_state.dart';
import 'package:remotto/core/storage/app_preferences.dart';
import 'package:remotto/core/storage/storage_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _container({
  Map<String, Object> initial = const {},
}) async {
  SharedPreferences.setMockInitialValues(initial);
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
  return container;
}

void main() {
  group('AppPreferences', () {
    test('default: themeMode system, haptic true', () async {
      SharedPreferences.setMockInitialValues({});
      final p = AppPreferences(await SharedPreferences.getInstance());
      expect(p.readThemeMode(), ThemeMode.system);
      expect(p.readHapticEnabled(), isTrue);
    });

    test('tulis lalu baca themeMode dan haptic', () async {
      SharedPreferences.setMockInitialValues({});
      final p = AppPreferences(await SharedPreferences.getInstance());
      await p.writeThemeMode(ThemeMode.dark);
      await p.writeHapticEnabled(false);
      expect(p.readThemeMode(), ThemeMode.dark);
      expect(p.readHapticEnabled(), isFalse);
    });

    test('nilai themeMode rusak -> system', () async {
      SharedPreferences.setMockInitialValues({'themeMode': 'neon'});
      final p = AppPreferences(await SharedPreferences.getInstance());
      expect(p.readThemeMode(), ThemeMode.system);
    });

    test('tipe themeMode salah -> system; haptic tipe salah -> true', () async {
      SharedPreferences.setMockInitialValues({
        'themeMode': 42,
        'hapticEnabled': 'ya',
      });
      final p = AppPreferences(await SharedPreferences.getInstance());
      expect(p.readThemeMode(), ThemeMode.system);
      expect(p.readHapticEnabled(), isTrue);
    });
  });

  group('lastPowerCommand', () {
    final sentAt = DateTime.utc(2026, 11, 8, 5, 30, 15, 250);

    test('default: tidak ada perintah daya', () async {
      SharedPreferences.setMockInitialValues({});
      final p = AppPreferences(await SharedPreferences.getInstance());
      expect(p.readLastPowerCommand(), isNull);
    });

    test('tulis lalu baca menghasilkan nilai yang sama', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final p = AppPreferences(prefs);
      await p.writeLastPowerCommand(
        LastPowerCommand(action: 'shutdown', sentAt: sentAt),
      );
      expect(
        prefs.getString('lastPowerCommand'),
        '{"action":"shutdown","sentAt":"2026-11-08T05:30:15.250Z"}',
      );
      expect(
        p.readLastPowerCommand(),
        LastPowerCommand(action: 'shutdown', sentAt: sentAt),
      );
    });

    test('sentAt non-UTC disimpan sebagai UTC', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final p = AppPreferences(prefs);
      final local = sentAt.toLocal();
      await p.writeLastPowerCommand(
        LastPowerCommand(action: 'sleep', sentAt: local),
      );
      expect(
        p.readLastPowerCommand(),
        LastPowerCommand(action: 'sleep', sentAt: sentAt),
      );
    });

    test('clear menghapus nilai', () async {
      SharedPreferences.setMockInitialValues({});
      final p = AppPreferences(await SharedPreferences.getInstance());
      await p.writeLastPowerCommand(
        LastPowerCommand(action: 'restart', sentAt: sentAt),
      );
      await p.clearLastPowerCommand();
      expect(p.readLastPowerCommand(), isNull);
    });

    test('nilai rusak diabaikan', () async {
      final broken = <Object>[
        'bukan json',
        '[1,2]',
        '{"action":"shutdown"}',
        '{"action":"shutdown","sentAt":42}',
        '{"action":"shutdown","sentAt":"kemarin"}',
        '{"sentAt":"2026-11-08T05:30:15.250Z"}',
        '{"action":"hibernate","sentAt":"2026-11-08T05:30:15.250Z"}',
        '{"action":42,"sentAt":"2026-11-08T05:30:15.250Z"}',
        42,
        true,
      ];
      for (final raw in broken) {
        SharedPreferences.setMockInitialValues({'lastPowerCommand': raw});
        final p = AppPreferences(await SharedPreferences.getInstance());
        expect(p.readLastPowerCommand(), isNull, reason: 'nilai: $raw');
      }
    });
  });

  group('themeModeProvider and hapticEnabledProvider', () {
    test('set themeMode dark menyimpan dan membaca ulang', () async {
      final container = await _container();
      addTearDown(container.dispose);

      expect(container.read(themeModeProvider), ThemeMode.system);
      await container.read(themeModeProvider.notifier).set(ThemeMode.dark);
      expect(container.read(themeModeProvider), ThemeMode.dark);

      final fresh = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(
            await SharedPreferences.getInstance(),
          ),
        ],
      );
      addTearDown(fresh.dispose);
      expect(fresh.read(themeModeProvider), ThemeMode.dark);
    });

    test('set haptic false menyimpan dan membaca ulang', () async {
      final container = await _container();
      addTearDown(container.dispose);

      expect(container.read(hapticEnabledProvider), isTrue);
      await container.read(hapticEnabledProvider.notifier).set(enabled: false);
      expect(container.read(hapticEnabledProvider), isFalse);
      expect(
        (await SharedPreferences.getInstance()).getBool('hapticEnabled'),
        isFalse,
      );
    });
  });
}
