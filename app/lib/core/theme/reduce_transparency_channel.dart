import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'glass_mode.dart';

/// Nama kanal yang didaftarkan di `ios/Runner/AppDelegate.swift`.
const reduceTransparencyChannelName = 'remotto/accessibility';

/// Membawa nilai reduce transparency dari iOS ke Dart lewat platform channel.
///
/// Nilai awal dibaca sekali saat [start], lalu hanya diperbarui saat native
/// mengirim `reduceTransparencyChanged`. Tidak ada polling. Android tidak
/// punya handler native, jadi `MissingPluginException` dianggap `false`.
final class ReduceTransparencySource {
  ReduceTransparencySource({required this.onChanged, MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(reduceTransparencyChannelName);

  /// Dipanggil dengan nilai awal dan setiap perubahan.
  final void Function(bool value) onChanged;

  final MethodChannel _channel;

  /// Pasang handler perubahan, lalu kirim nilai awal ke [onChanged].
  Future<void> start() async {
    _channel.setMethodCallHandler(_handleCall);
    onChanged(await _readInitial());
  }

  /// Lepas handler agar native tidak mengirim ke Dart yang sudah tidak aktif.
  void dispose() => _channel.setMethodCallHandler(null);

  Future<dynamic> _handleCall(MethodCall call) async {
    if (call.method == 'reduceTransparencyChanged') {
      onChanged(call.arguments == true);
    }
  }

  Future<bool> _readInitial() async {
    try {
      final value = await _channel.invokeMethod<bool>(
        'isReduceTransparencyEnabled',
      );
      return value ?? false;
    } on MissingPluginException {
      return false;
    }
  }
}

/// Inisialisasi sekali: dibaca dari `RemottoApp`. Tidak ada state yang
/// disimpan di sini, hanya efek samping ke [reduceTransparencyProvider].
final reduceTransparencyBootstrapProvider = Provider<void>((ref) {
  var disposed = false;
  final source = ReduceTransparencySource(
    onChanged: (value) {
      // Nilai awal bisa tiba setelah container dibuang; abaikan saja.
      if (!disposed) ref.read(reduceTransparencyProvider.notifier).set(value);
    },
  );
  unawaited(source.start());
  ref.onDispose(() {
    disposed = true;
    source.dispose();
  });
});
