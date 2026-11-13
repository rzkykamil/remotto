import 'dart:async';

import 'package:remotto/core/discovery/agent_discovery.dart';

/// [AgentDiscovery] palsu. Tidak ada I/O; tes yang memutuskan hasilnya.
///
/// - [resultsPerCall]: hasil untuk setiap panggilan `find`, berurutan. Setelah
///   habis, `find` mengembalikan daftar kosong.
/// - [gate]: bila ada, setiap `find` menunggu future ini selesai sebelum
///   mengembalikan hasil. Dipakai untuk menahan proses discovery.
/// - [throwOnCalls]: indeks panggilan (mulai 0) yang melempar error.
/// - [hangOnCalls]: indeks panggilan (mulai 0) yang menggantung. Panggilan
///   itu menunggu [hung] yang secara default tak pernah selesai. Tes boleh
///   menyelesaikan [hung] untuk meniru hasil yang telat; panggilan lalu
///   mengembalikan hasil biasa sesuai [resultsPerCall]. Panggilan lain tidak
///   terpengaruh.
/// - [timeouts] dan [callCount]: catatan untuk assertion.
final class FakeAgentDiscovery implements AgentDiscovery {
  FakeAgentDiscovery({
    this.resultsPerCall = const [],
    this.gate,
    this.throwOnCalls = const {},
    this.hangOnCalls = const {},
  });

  final List<List<DiscoveredAgent>> resultsPerCall;
  final Completer<void>? gate;
  final Set<int> throwOnCalls;
  final Set<int> hangOnCalls;

  /// Ditahan oleh panggilan di [hangOnCalls]. Tidak pernah selesai kecuali
  /// tes menyelesaikannya sendiri.
  final Completer<void> hung = Completer<void>();

  /// Timeout yang diterima setiap panggilan, dalam urutan panggilan.
  final List<Duration> timeouts = [];

  int get callCount => timeouts.length;

  @override
  Future<List<DiscoveredAgent>> find({required Duration timeout}) async {
    final index = timeouts.length;
    timeouts.add(timeout);
    final hold = gate;
    if (hold != null) await hold.future;
    if (hangOnCalls.contains(index)) await hung.future;
    if (throwOnCalls.contains(index)) throw StateError('discovery failed');
    if (index >= resultsPerCall.length) return const [];
    return List<DiscoveredAgent>.of(resultsPerCall[index]);
  }
}
