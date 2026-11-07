import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/storage_providers.dart';

/// Sumber getaran fisik. Dipisah supaya test memakai sink palsu.
abstract interface class HapticSink {
  Future<void> light();
  Future<void> selection();
  Future<void> medium();
  Future<void> heavy();
  Future<void> vibrate();
}

final class SystemHapticSink implements HapticSink {
  const SystemHapticSink();

  @override
  Future<void> light() => HapticFeedback.lightImpact();

  @override
  Future<void> selection() => HapticFeedback.selectionClick();

  @override
  Future<void> medium() => HapticFeedback.mediumImpact();

  @override
  Future<void> heavy() => HapticFeedback.heavyImpact();

  @override
  Future<void> vibrate() => HapticFeedback.vibrate();
}

/// Satu-satunya pintu haptic di app. Pemetaan momen mengikuti
/// `design/design-system.md` bagian Haptic. Setiap momen no-op bila
/// preferensi "Getar saat ditekan" mati; [enabled] dibaca tiap panggilan.
final class RHaptics {
  RHaptics({required this.sink, required this.enabled});

  final HapticSink sink;
  final bool Function() enabled;

  /// Play, prev, next, mute, −+ (saat jari turun).
  void press() => _fire(sink.light);

  /// Slider setiap 5%.
  void detent() => _fire(sink.selection);

  /// Slider mentok 0 atau 100.
  void limit() => _fire(sink.medium);

  /// QR pairing terbaca.
  void qrScanned() => _fire(sink.medium);

  /// Tahan konfirmasi mencapai 50%.
  void holdHalf() => _fire(sink.selection);

  /// Tahan konfirmasi selesai.
  void holdDone() => _fire(sink.heavy);

  /// Gagal kirim atau batal gagal.
  void failure() => _fire(sink.vibrate);

  void _fire(Future<void> Function() play) {
    if (enabled()) {
      unawaited(play());
    }
  }
}

final hapticSinkProvider = Provider<HapticSink>(
  (ref) => const SystemHapticSink(),
);

/// Closure membaca `hapticEnabledProvider` tiap panggilan, jadi toggle
/// langsung berlaku tanpa membangun ulang provider ini.
final hapticsProvider = Provider<RHaptics>(
  (ref) => RHaptics(
    sink: ref.watch(hapticSinkProvider),
    enabled: () => ref.read(hapticEnabledProvider),
  ),
);
