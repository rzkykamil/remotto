import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotto/core/haptics/r_haptics.dart';
import 'package:remotto/core/storage/storage_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RHaptics', () {
    late RecordingHapticSink sink;
    var enabled = true;
    late RHaptics haptics;

    setUp(() {
      sink = RecordingHapticSink();
      enabled = true;
      haptics = RHaptics(sink: sink, enabled: () => enabled);
    });

    test('setiap momen memanggil pola haptic yang sesuai desain', () async {
      haptics
        ..press()
        ..detent()
        ..limit()
        ..qrScanned()
        ..holdHalf()
        ..holdDone()
        ..failure();
      await Future<void>.delayed(Duration.zero);

      expect(sink.calls, [
        'light',
        'selection',
        'medium',
        'medium',
        'selection',
        'heavy',
        'vibrate',
      ]);
    });

    test('tidak ada panggilan sink saat haptic dimatikan', () async {
      enabled = false;
      haptics
        ..press()
        ..detent()
        ..limit()
        ..qrScanned()
        ..holdHalf()
        ..holdDone()
        ..failure();
      await Future<void>.delayed(Duration.zero);

      expect(sink.calls, isEmpty);
    });

    test('toggle enabled di tengah jalan langsung berpengaruh', () async {
      haptics.press();
      enabled = false;
      haptics.press();
      enabled = true;
      haptics.holdDone();
      await Future<void>.delayed(Duration.zero);

      expect(sink.calls, ['light', 'heavy']);
    });
  });

  group('hapticsProvider', () {
    test('mengikuti hapticEnabledProvider', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final sink = RecordingHapticSink();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          hapticSinkProvider.overrideWithValue(sink),
        ],
      );
      addTearDown(container.dispose);

      final haptics = container.read(hapticsProvider);
      haptics.press();
      await Future<void>.delayed(Duration.zero);
      expect(sink.calls, ['light']);

      await container.read(hapticEnabledProvider.notifier).set(enabled: false);
      haptics.press();
      await Future<void>.delayed(Duration.zero);
      expect(sink.calls, ['light']);

      await container.read(hapticEnabledProvider.notifier).set(enabled: true);
      haptics.failure();
      await Future<void>.delayed(Duration.zero);
      expect(sink.calls, ['light', 'vibrate']);
    });
  });
}
