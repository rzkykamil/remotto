import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Preferensi non-sensitif (data-design.md §6). Nilai rusak atau tidak dikenal
/// kembali ke default.
final class AppPreferences {
  const AppPreferences(this._prefs);

  static const keyThemeMode = 'themeMode';
  static const keyHapticEnabled = 'hapticEnabled';

  final SharedPreferences _prefs;

  ThemeMode readThemeMode() {
    final raw = _prefs.get(keyThemeMode);
    return switch (raw) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  Future<void> writeThemeMode(ThemeMode mode) {
    final value = switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
    return _prefs.setString(keyThemeMode, value);
  }

  bool readHapticEnabled() {
    final raw = _prefs.get(keyHapticEnabled);
    return raw is bool ? raw : true;
  }

  Future<void> writeHapticEnabled(bool enabled) =>
      _prefs.setBool(keyHapticEnabled, enabled);
}
