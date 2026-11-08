import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../connection/connection_providers.dart';
import 'app_preferences.dart';
import 'connection_storage.dart';
import 'pairing_data.dart';

/// Di-override saat bootstrap (`main.dart`) dengan instance yang sudah dibuka.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('override in bootstrap'),
);

final appPreferencesProvider = Provider<AppPreferences>(
  (ref) => AppPreferences(ref.watch(sharedPreferencesProvider)),
);

final secureStorageProvider = Provider<FlutterSecureStorage>(
  (ref) => const FlutterSecureStorage(),
);

final connectionStorageProvider = Provider<ConnectionStorage>(
  (ref) => SecureConnectionStorage(ref.watch(secureStorageProvider)),
);

/// Hasil baca awal storage. Di-override saat bootstrap; default null.
final initialPairingProvider = Provider<PairingData?>((ref) => null);

final pairingProvider = NotifierProvider<PairingNotifier, PairingData?>(
  PairingNotifier.new,
);

final class PairingNotifier extends Notifier<PairingData?> {
  @override
  PairingData? build() => ref.read(initialPairingProvider);

  /// Menulis storage dulu, baru mengubah state. Bila tulis gagal, state tetap.
  /// Pairing baru menghapus `lastPowerCommand` milik laptop lama.
  Future<void> save(PairingData data) async {
    await ref.read(connectionStorageProvider).write(data);
    state = data;
    ref.read(lastPowerCommandProvider.notifier).clear();
  }

  /// Penghapusan pairing juga menghapus `lastPowerCommand`.
  Future<void> clear() async {
    await ref.read(connectionStorageProvider).clear();
    state = null;
    ref.read(lastPowerCommandProvider.notifier).clear();
  }
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);

final class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ref.read(appPreferencesProvider).readThemeMode();

  Future<void> set(ThemeMode mode) async {
    await ref.read(appPreferencesProvider).writeThemeMode(mode);
    state = mode;
  }
}

final hapticEnabledProvider = NotifierProvider<HapticEnabledNotifier, bool>(
  HapticEnabledNotifier.new,
);

final class HapticEnabledNotifier extends Notifier<bool> {
  @override
  bool build() => ref.read(appPreferencesProvider).readHapticEnabled();

  Future<void> set({required bool enabled}) async {
    await ref.read(appPreferencesProvider).writeHapticEnabled(enabled);
    state = enabled;
  }
}
