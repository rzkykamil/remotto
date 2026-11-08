import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../connection/connection_state.dart';

/// Preferensi non-sensitif (data-design.md §6). Nilai rusak atau tidak dikenal
/// kembali ke default.
final class AppPreferences {
  const AppPreferences(this._prefs);

  static const keyThemeMode = 'themeMode';
  static const keyHapticEnabled = 'hapticEnabled';
  static const keyLastPowerCommand = 'lastPowerCommand';

  static const _powerActions = {'sleep', 'restart', 'shutdown'};

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

  /// Membaca `{action, sentAt}` (sentAt ISO 8601 UTC). Null bila tidak ada,
  /// JSON rusak, atau action tidak dikenal. Batas waktu 10 menit dicek di
  /// pemanggil, bukan di sini.
  LastPowerCommand? readLastPowerCommand() {
    final raw = _prefs.get(keyLastPowerCommand);
    if (raw is! String) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final action = decoded['action'];
      final sentAtRaw = decoded['sentAt'];
      if (action is! String || !_powerActions.contains(action)) return null;
      if (sentAtRaw is! String) return null;
      final sentAt = DateTime.tryParse(sentAtRaw);
      if (sentAt == null) return null;
      return LastPowerCommand(action: action, sentAt: sentAt.toUtc());
    } on FormatException {
      return null;
    }
  }

  Future<void> writeLastPowerCommand(LastPowerCommand command) {
    final value = jsonEncode({
      'action': command.action,
      'sentAt': command.sentAt.toUtc().toIso8601String(),
    });
    return _prefs.setString(keyLastPowerCommand, value);
  }

  Future<void> clearLastPowerCommand() => _prefs.remove(keyLastPowerCommand);
}
