import 'dart:collection';

import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'glass_mode.dart';

/// Jumlah frame terakhir yang dinilai. Ambang ini memberi cukup sampel agar
/// satu lonjakan sesaat tidak langsung mematikan efek kaca (sekitar 2 detik
/// pada 60 fps). Angka ini keputusan M6; design-system.md section 7 hanya menyebut "terlalu lambat secara konsisten" tanpa angka.
const rasterWindowFrames = 120;

/// Persentase frame lambat dalam jendela yang memicu mode solid, 90 persen.
/// Dinyatakan sebagai pecahan persen agar perbandingan tetap integer.
/// Angka ini keputusan M6; design-system.md section 7 hanya menyebut "terlalu lambat secara konsisten" tanpa angka.
const rasterSlowPercent = 90;

/// Batas raster per frame. Frame 60 fps punya anggaran sekitar 16,7 ms
/// (1000 / 60); di atas 16 ms dianggap lambat. Sumber: anggaran frame 60 fps
/// (Flutter performance best practices), dibulatkan ke 16 ms sesuai M6.
const rasterSlowFrame = Duration(milliseconds: 16);

/// Menilai apakah raster terlalu lambat secara konsisten.
///
/// Jendela geser berisi [rasterWindowFrames] frame terakhir. [slow] menjadi
/// true bila jendela sudah penuh dan minimal [rasterSlowPercent] persen
/// frame di dalamnya melewati [rasterSlowFrame]. Setelah true, nilainya
/// tetap true selama sesi (tidak kembali ke false).
final class RasterTimingEvaluator {
  final Queue<bool> _window = Queue<bool>();
  int _slowCount = 0;
  bool _slow = false;

  /// True setelah raster terbukti lambat secara konsisten. Tidak pernah
  /// kembali ke false.
  bool get slow => _slow;

  /// Mencatat satu frame. Frame sesudah [slow] true tidak mengubah apa pun.
  void add(Duration rasterTime) {
    if (_slow) return;

    final isSlow = rasterTime > rasterSlowFrame;
    _window.addLast(isSlow);
    if (isSlow) _slowCount++;

    if (_window.length > rasterWindowFrames) {
      if (_window.removeFirst()) _slowCount--;
    }

    if (_window.length >= rasterWindowFrames &&
        _slowCount * 100 >= rasterWindowFrames * rasterSlowPercent) {
      _slow = true;
    }
  }
}

/// Pembungkus `SchedulerBinding.addTimingsCallback` agar bisa diganti di test.
abstract interface class RasterTimingsHook {
  void add(TimingsCallback callback);
  void remove(TimingsCallback callback);
}

/// Implementasi nyata: meneruskan ke `SchedulerBinding.instance`.
final class SchedulerRasterTimingsHook implements RasterTimingsHook {
  const SchedulerRasterTimingsHook();

  @override
  void add(TimingsCallback callback) =>
      SchedulerBinding.instance.addTimingsCallback(callback);

  @override
  void remove(TimingsCallback callback) =>
      SchedulerBinding.instance.removeTimingsCallback(callback);
}

/// Sumber hook. Test menimpanya dengan implementasi palsu.
final rasterTimingsHookProvider = Provider<RasterTimingsHook>(
  (ref) => const SchedulerRasterTimingsHook(),
);

/// Inisialisasi sekali: dibaca dari `RemottoApp`. Memasang callback timing
/// frame dan, saat raster terbukti lambat, menyalakan [slowRasterProvider]
/// sekali. Callback dilepas saat provider dibuang.
final rasterMonitorBootstrapProvider = Provider<void>((ref) {
  final hook = ref.read(rasterTimingsHookProvider);
  final evaluator = RasterTimingEvaluator();
  var notified = false;

  void onTimings(List<FrameTiming> timings) {
    if (notified) return;
    for (final timing in timings) {
      evaluator.add(timing.rasterDuration);
    }
    if (evaluator.slow) {
      notified = true;
      ref.read(slowRasterProvider.notifier).set(true);
    }
  }

  hook.add(onTimings);
  ref.onDispose(() => hook.remove(onTimings));
});
