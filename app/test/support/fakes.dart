import 'package:remotto/core/haptics/r_haptics.dart';
import 'package:remotto/core/storage/connection_storage.dart';
import 'package:remotto/core/storage/pairing_data.dart';

/// Mencatat nama pola haptic yang diminta, tanpa getaran sungguhan.
final class RecordingHapticSink implements HapticSink {
  final List<String> calls = [];

  @override
  Future<void> light() async => calls.add('light');

  @override
  Future<void> selection() async => calls.add('selection');

  @override
  Future<void> medium() async => calls.add('medium');

  @override
  Future<void> heavy() async => calls.add('heavy');

  @override
  Future<void> vibrate() async => calls.add('vibrate');
}

/// Penyimpanan sambungan in-memory untuk test lain.
final class InMemoryConnectionStorage implements ConnectionStorage {
  InMemoryConnectionStorage([this.data]);

  PairingData? data;

  @override
  Future<PairingData?> read() async => data;

  @override
  Future<void> write(PairingData value) async => data = value;

  @override
  Future<void> clear() async => data = null;
}
