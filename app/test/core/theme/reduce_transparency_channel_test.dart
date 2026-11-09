import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotto/core/theme/glass_mode.dart';
import 'package:remotto/core/theme/reduce_transparency_channel.dart';

const _channel = MethodChannel(reduceTransparencyChannelName);
const _codec = StandardMethodCodec();

/// Simulasi kiriman native ke Dart, seperti `invokeMethod` dari AppDelegate.
Future<void> _sendFromNative(
  TestDefaultBinaryMessenger messenger,
  Object? arguments,
) {
  return messenger.handlePlatformMessage(
    _channel.name,
    _codec.encodeMethodCall(MethodCall('reduceTransparencyChanged', arguments)),
    (_) {},
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestWidgetsFlutterBinding.instance.defaultBinaryMessenger;

  void mockNative({required bool initial}) {
    messenger.setMockMethodCallHandler(_channel, (call) async {
      if (call.method == 'isReduceTransparencyEnabled') return initial;
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(_channel, null));
  }

  ProviderContainer makeContainer() {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    return container;
  }

  ReduceTransparencySource makeSource(ProviderContainer container) {
    final source = ReduceTransparencySource(
      onChanged: (value) =>
          container.read(reduceTransparencyProvider.notifier).set(value),
    );
    addTearDown(source.dispose);
    return source;
  }

  test(
    'nilai awal true dari native mengubah reduceTransparencyProvider',
    () async {
      mockNative(initial: true);
      final container = makeContainer();

      await makeSource(container).start();

      expect(container.read(reduceTransparencyProvider), isTrue);
    },
  );

  test(
    'kiriman reduceTransparencyChanged true lalu false mengubah provider',
    () async {
      mockNative(initial: false);
      final container = makeContainer();
      await makeSource(container).start();
      expect(container.read(reduceTransparencyProvider), isFalse);

      await _sendFromNative(messenger, true);
      expect(container.read(reduceTransparencyProvider), isTrue);

      await _sendFromNative(messenger, false);
      expect(container.read(reduceTransparencyProvider), isFalse);
    },
  );

  test('MissingPluginException (Android) dianggap false dan tidak melempar', () async {
    // Tanpa mock, pemanggilan kanal tidak punya handler: sama seperti Android.
    final container = makeContainer();
    final source = makeSource(container);

    await expectLater(source.start(), completes);
    expect(container.read(reduceTransparencyProvider), isFalse);
  });

  test('bootstrap provider memasang sumber dan tidak melempar di Android', () async {
    final container = makeContainer();

    container.read(reduceTransparencyBootstrapProvider);
    // Beri waktu agar balasan kanal (MissingPluginException) selesai diproses.
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(container.read(reduceTransparencyProvider), isFalse);
  });
}
