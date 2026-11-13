import 'dart:async';

import 'package:remotto/core/discovery/network_change_source.dart';

/// [NetworkChangeSource] palsu. Tes memicu [emit] dan mengatur [onLocal].
final class FakeNetworkChangeSource implements NetworkChangeSource {
  FakeNetworkChangeSource({this.onLocal = true});

  final StreamController<void> _controller = StreamController<void>.broadcast();

  /// Hasil [onLocalNetwork]: true berarti Wi-Fi atau Ethernet.
  bool onLocal;

  /// True bila ada langganan aktif (controller sudah listen).
  bool get subscribed => _controller.hasListener;

  @override
  Stream<void> get changes => _controller.stream;

  @override
  Future<bool> get onLocalNetwork async => onLocal;

  /// Satu event perubahan jaringan.
  void emit() => _controller.add(null);

  Future<void> close() => _controller.close();
}
