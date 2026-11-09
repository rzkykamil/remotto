import 'package:flutter_test/flutter_test.dart';
import 'package:remotto/core/connection/connection_controller.dart';

/// Satu job dari [FakePollScheduler]. Timer tidak pernah jalan sendiri.
final class FakeScheduledJob implements ScheduledJob {
  FakeScheduledJob(this.delay, this.callback, {required this.periodic});

  final Duration delay;
  final void Function() callback;
  final bool periodic;
  bool _done = false;

  bool get live => !_done;

  @override
  void cancel() => _done = true;

  void run() {
    if (!periodic) _done = true;
    callback();
  }
}

/// Scheduler palsu: tes yang memicu timer, tanpa menunggu waktu nyata.
final class FakePollScheduler implements PollScheduler {
  final List<FakeScheduledJob> jobs = [];

  @override
  ScheduledJob every(Duration interval, void Function() tick) {
    final job = FakeScheduledJob(interval, tick, periodic: true);
    jobs.add(job);
    return job;
  }

  @override
  ScheduledJob after(Duration delay, void Function() callback) {
    final job = FakeScheduledJob(delay, callback, periodic: false);
    jobs.add(job);
    return job;
  }

  Iterable<FakeScheduledJob> get _live => jobs.where((job) => job.live);

  /// Job periodik yang masih hidup, atau null.
  FakeScheduledJob? get periodicJob {
    final found = _live.where((job) => job.periodic).toList();
    return found.isEmpty ? null : found.last;
  }

  bool hasLiveOnce(Duration delay) =>
      _live.any((job) => !job.periodic && job.delay == delay);

  /// Menjalankan timer sekali terakhir dengan [delay].
  void fireOnce(Duration delay) {
    final found = _live
        .where((job) => !job.periodic && job.delay == delay)
        .toList();
    expect(found, isNotEmpty, reason: 'tidak ada timer sekali $delay');
    found.last.run();
  }

  /// Memicu satu poll periodik. No-op bila tidak ada job periodik.
  void tick() => periodicJob?.run();
}
