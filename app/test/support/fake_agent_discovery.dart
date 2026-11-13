import 'dart:async';

import 'package:remotto/core/discovery/agent_discovery.dart';

/// [AgentDiscovery] palsu. Tidak ada I/O; tes yang memutuskan hasilnya.
///
/// - [resultsPerCall]: hasil untuk setiap panggilan `find`, berurutan. Setelah
///   habis, `find` mengembalikan daftar kosong.
/// - [gate]: bila ada, setiap `find` menunggu future ini selesai sebelum
///   mengembalikan hasil. Dipakai untuk menahan proses discovery.
/// - [timeouts] dan [callCount]: catatan untuk assertion.
final class FakeAgentDiscovery implements AgentDiscovery {
  FakeAgentDiscovery({this.resultsPerCall = const [], this.gate});

  final List<List<DiscoveredAgent>> resultsPerCall;
  final Completer<void>? gate;

  /// Timeout yang diterima setiap panggilan, dalam urutan panggilan.
  final List<Duration> timeouts = [];

  int get callCount => timeouts.length;

  @override
  Future<List<DiscoveredAgent>> find({required Duration timeout}) async {
    final index = timeouts.length;
    timeouts.add(timeout);
    final hold = gate;
    if (hold != null) await hold.future;
    if (index >= resultsPerCall.length) return const [];
    return List<DiscoveredAgent>.of(resultsPerCall[index]);
  }
}
