import 'dart:async';

import 'package:remotto/core/discovery/endpoint_resolver.dart';

/// [EndpointResolver] palsu. Tidak ada discovery atau HTTP.
///
/// - [results]: hasil untuk setiap panggilan `rediscover`, berurutan. Setelah
///   habis, hasilnya [RediscoverResult.none].
/// - [manual]: bila true, setiap panggilan menahan future-nya di [held] dan
///   tes yang menyelesaikannya (dipakai untuk membuktikan poll tidak diblok).
/// - [forceCalls]: nilai `force` tiap panggilan, dalam urutan panggilan.
final class FakeEndpointResolver implements EndpointResolver {
  FakeEndpointResolver({this.results = const [], this.manual = false});

  final List<RediscoverResult> results;
  final bool manual;
  final List<bool> forceCalls = [];
  final List<Completer<RediscoverResult>> held = [];

  int get callCount => forceCalls.length;

  @override
  Future<RediscoverResult> rediscover({bool force = false}) {
    final index = forceCalls.length;
    forceCalls.add(force);
    if (manual) {
      final completer = Completer<RediscoverResult>();
      held.add(completer);
      return completer.future;
    }
    return Future.value(
      index < results.length ? results[index] : RediscoverResult.none,
    );
  }
}
