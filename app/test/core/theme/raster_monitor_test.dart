import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotto/core/theme/glass_mode.dart';
import 'package:remotto/core/theme/raster_monitor.dart';

const _fast = Duration(milliseconds: 8);
const _slow = Duration(milliseconds: 25);

/// Hook palsu: menyimpan callback dan bisa "mengirim" timing ke dalamnya.
final class FakeRasterTimingsHook implements RasterTimingsHook {
  final List<TimingsCallback> callbacks = [];

  @override
  void add(TimingsCallback callback) => callbacks.add(callback);

  @override
  void remove(TimingsCallback callback) => callbacks.remove(callback);

  void emit(List<Duration> rasterTimes) {
    final timings = [
      for (final raster in rasterTimes)
        FrameTiming(
          vsyncStart: 0,
          buildStart: 0,
          buildFinish: 0,
          rasterStart: 0,
          rasterFinish: raster.inMicroseconds,
          rasterFinishWallTime: 0,
        ),
    ];
    for (final callback in List.of(callbacks)) {
      callback(timings);
    }
  }
}

void main() {
  group('RasterTimingEvaluator', () {
    test('stays false for fast frames', () {
      final evaluator = RasterTimingEvaluator();
      for (var i = 0; i < rasterWindowFrames * 3; i++) {
        evaluator.add(_fast);
      }
      expect(evaluator.slow, isFalse);
    });

    test('stays false before the window holds rasterWindowFrames frames', () {
      final evaluator = RasterTimingEvaluator();
      for (var i = 0; i < rasterWindowFrames - 1; i++) {
        evaluator.add(_slow);
      }
      expect(evaluator.slow, isFalse);
    });

    test('becomes true once a full window is at least 90 percent slow', () {
      final evaluator = RasterTimingEvaluator();
      // 108 of 120 frames slow (90 percent), the rest fast.
      for (var i = 0; i < 12; i++) {
        evaluator.add(_fast);
      }
      for (var i = 0; i < 108; i++) {
        evaluator.add(_slow);
      }
      expect(evaluator.slow, isTrue);
    });

    test('stays false when slow share is just under 90 percent', () {
      final evaluator = RasterTimingEvaluator();
      // 107 of 120 frames slow (89.2 percent).
      for (var i = 0; i < 13; i++) {
        evaluator.add(_fast);
      }
      for (var i = 0; i < 107; i++) {
        evaluator.add(_slow);
      }
      expect(evaluator.slow, isFalse);
    });

    test('a frame of exactly 16 ms is not slow', () {
      final evaluator = RasterTimingEvaluator();
      for (var i = 0; i < rasterWindowFrames; i++) {
        evaluator.add(rasterSlowFrame);
      }
      expect(evaluator.slow, isFalse);
    });

    test('never returns to false once true', () {
      final evaluator = RasterTimingEvaluator();
      for (var i = 0; i < rasterWindowFrames; i++) {
        evaluator.add(_slow);
      }
      expect(evaluator.slow, isTrue);
      for (var i = 0; i < rasterWindowFrames * 2; i++) {
        evaluator.add(_fast);
      }
      expect(evaluator.slow, isTrue);
    });
  });

  group('rasterMonitorBootstrapProvider', () {
    test('registers one callback and removes it on dispose', () {
      final hook = FakeRasterTimingsHook();
      final container = ProviderContainer(
        overrides: [rasterTimingsHookProvider.overrideWithValue(hook)],
      );

      container.read(rasterMonitorBootstrapProvider);
      expect(hook.callbacks, hasLength(1));

      container.dispose();
      expect(hook.callbacks, isEmpty);
    });

    testWidgets(
      'slow raster sets slowRasterProvider and GlassMode reports it',
      (tester) async {
        final hook = FakeRasterTimingsHook();
        final container = ProviderContainer(
          overrides: [rasterTimingsHookProvider.overrideWithValue(hook)],
        );
        addTearDown(container.dispose);
        container.read(rasterMonitorBootstrapProvider);

        hook.emit(List.filled(rasterWindowFrames, _slow));
        expect(container.read(slowRasterProvider), isTrue);

        late GlassFallbackReason reason;
        late bool solid;
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MediaQuery(
              data: const MediaQueryData(),
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: Consumer(
                  builder: (context, ref, _) {
                    reason = GlassMode.reason(context, ref);
                    solid = GlassMode.isSolid(context, ref);
                    return const SizedBox();
                  },
                ),
              ),
            ),
          ),
        );

        expect(reason, GlassFallbackReason.slowRaster);
        expect(solid, isTrue);
      },
    );

    test('fast frames leave slowRasterProvider false', () {
      final hook = FakeRasterTimingsHook();
      final container = ProviderContainer(
        overrides: [rasterTimingsHookProvider.overrideWithValue(hook)],
      );
      addTearDown(container.dispose);
      container.read(rasterMonitorBootstrapProvider);

      hook.emit(List.filled(rasterWindowFrames * 2, _fast));
      expect(container.read(slowRasterProvider), isFalse);
    });
  });
}
