import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotto/core/discovery/network_change_source.dart';

/// Nama channel diambil dari `connectivity_plus_platform_interface` 2.1.0
/// (`method_channel_connectivity.dart`): method `check` di channel
/// `dev.fluttercommunity.plus/connectivity`, stream di
/// `dev.fluttercommunity.plus/connectivity_status`.
const _methodChannelName = 'dev.fluttercommunity.plus/connectivity';
const _eventChannelName = 'dev.fluttercommunity.plus/connectivity_status';
const _codec = StandardMethodCodec();

void main() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void mockCheck(Future<Object?> Function(MethodCall call) handler) {
    messenger.setMockMethodCallHandler(
      const MethodChannel(_methodChannelName),
      handler,
    );
    addTearDown(
      () => messenger.setMockMethodCallHandler(
        const MethodChannel(_methodChannelName),
        null,
      ),
    );
  }

  group('onLocalNetwork', () {
    for (final entry in <List<Object>>[
      [
        <String>['wifi'],
        true,
      ],
      [
        <String>['ethernet'],
        true,
      ],
      [
        <String>['mobile'],
        false,
      ],
      [
        <String>['none'],
        false,
      ],
    ]) {
      final states = entry[0] as List<String>;
      final expected = entry[1] as bool;
      test('states $states -> $expected', () async {
        mockCheck((call) async {
          expect(call.method, 'check');
          return states;
        });

        final source = ConnectivityNetworkChangeSource();

        expect(await source.onLocalNetwork, expected);
      });
    }

    test('PlatformException dari plugin -> false, tidak melempar', () async {
      mockCheck((call) async {
        throw PlatformException(code: 'boom', message: 'native failure');
      });

      final source = ConnectivityNetworkChangeSource();

      expect(await source.onLocalNetwork, isFalse);
    });
  });

  group('changes', () {
    setUp(() {
      // Stream mengirim event lewat binary messenger. Override ini hanya
      // untuk tes ini; handler `listen` palsu global tetap dipakai.
      messenger.setMockMethodCallHandler(
        const MethodChannel(_eventChannelName),
        (call) async => null,
      );
      addTearDown(
        () => messenger.setMockMethodCallHandler(
          const MethodChannel(_eventChannelName),
          (call) async => null,
        ),
      );
    });

    Future<void> emit(List<String> states) async {
      await messenger.handlePlatformMessage(
        _eventChannelName,
        _codec.encodeSuccessEnvelope(states),
        null,
      );
    }

    test('satu event per perubahan koneksi', () async {
      final source = ConnectivityNetworkChangeSource();
      var count = 0;
      final sub = source.changes.listen((_) => count++);
      addTearDown(sub.cancel);
      await pumpEventQueue();

      await emit(['wifi']);
      await emit(['mobile']);
      await emit(['wifi']);
      await pumpEventQueue();

      expect(count, 3);
    });

    test('state identik berurutan tidak menghasilkan event tambahan', () async {
      final source = ConnectivityNetworkChangeSource();
      var count = 0;
      final sub = source.changes.listen((_) => count++);
      addTearDown(sub.cancel);
      await pumpEventQueue();

      await emit(['wifi']);
      await emit(['wifi']);
      await pumpEventQueue();

      expect(count, 1);
    });
  });
}
