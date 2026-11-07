import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotto/core/connection/connection_controller.dart';
import 'package:remotto/core/connection/connection_providers.dart';
import 'package:remotto/core/connection/connection_state.dart';
import 'package:remotto/core/connection/status_repository.dart';
import 'package:remotto/core/network/agent_status.dart';
import 'package:remotto/core/network/api_failure.dart';
import 'package:remotto/core/network/network_providers.dart';
import 'package:remotto/core/theme/r_behavior.dart';
import 'package:remotto/core/theme/tokens.g.dart';

import '../../support/fake_status_repository.dart';

final class _FakeJob implements ScheduledJob {
  _FakeJob(this.delay, this.callback, {required this.periodic});

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

/// Fake scheduler: timers never run on their own, the test triggers them.
final class _FakeScheduler implements PollScheduler {
  final List<_FakeJob> jobs = [];

  @override
  ScheduledJob every(Duration interval, void Function() tick) {
    final job = _FakeJob(interval, tick, periodic: true);
    jobs.add(job);
    return job;
  }

  @override
  ScheduledJob after(Duration delay, void Function() callback) {
    final job = _FakeJob(delay, callback, periodic: false);
    jobs.add(job);
    return job;
  }

  Iterable<_FakeJob> get _live => jobs.where((job) => job.live);

  _FakeJob? get periodicJob {
    final found = _live.where((job) => job.periodic).toList();
    return found.isEmpty ? null : found.last;
  }

  bool hasLiveOnce(Duration delay) =>
      _live.any((job) => !job.periodic && job.delay == delay);

  /// Run the most recent one-shot timer with [delay].
  void fireOnce(Duration delay) {
    final found = _live
        .where((job) => !job.periodic && job.delay == delay)
        .toList();
    expect(found, isNotEmpty, reason: 'tidak ada timer sekali $delay');
    found.last.run();
  }

  void tick() => periodicJob?.run();
}

/// Repository that holds every reply until the test completes it.
final class _ManualRepository implements StatusRepository {
  final List<Completer<AgentStatus>> requests = [];

  @override
  Future<AgentStatus> fetchStatus() {
    final completer = Completer<AgentStatus>();
    requests.add(completer);
    return completer.future;
  }
}

final class _Clock {
  _Clock(this.now);

  DateTime now;
}

final class _Harness {
  _Harness(StatusRepository repo, {DateTime? now})
    : clock = _Clock(now ?? DateTime(2026, 11, 8, 12)) {
    container = ProviderContainer(
      overrides: [
        statusRepositoryProvider.overrideWithValue(repo),
        pollSchedulerProvider.overrideWithValue(sched),
        connectionClockProvider.overrideWithValue(() => clock.now),
      ],
    );
  }

  final _FakeScheduler sched = _FakeScheduler();
  final _Clock clock;
  late final ProviderContainer container;

  ConnectionController get ctrl =>
      container.read(connectionControllerProvider.notifier);

  ConnectionState get state => container.read(connectionControllerProvider);

  ConnectionPhase get phase => state.phase;

  /// Let the already completed future (mock reply) process its result.
  Future<void> settle() => pumpEventQueue();

  Future<void> start() async {
    ctrl.start();
    await settle();
  }

  Future<void> tick() async {
    sched.tick();
    await settle();
  }

  Future<void> poll() async {
    await ctrl.pollOnce();
  }

  void dispose() => container.dispose();
}

_Harness _harness(StatusRepository repo, {DateTime? now}) {
  final harness = _Harness(repo, now: now);
  addTearDown(harness.dispose);
  return harness;
}

FakeHttpReply _ok({int uptime = 60, bool volumeUnavailable = false}) =>
    fakeStatusOk(uptimeSeconds: uptime, volumeUnavailable: volumeUnavailable);

const FakeStatusStep _down = FakeTransportFailure(UnreachableFailure());

void main() {
  group('start', () {
    test(
      'poll pertama 2 detik dan jadwal periodik 5 detik (BR-21, BR-8)',
      () async {
        final h = _harness(FakeStatusRepository([_ok()]));

        expect(h.phase, ConnectionPhase.connecting);
        await h.start();

        expect(h.sched.periodicJob?.delay, RMotion.poll);
        expect(
          h.sched.jobs.any(
            (job) => !job.periodic && job.delay == RBehavior.resumeWait,
          ),
          isTrue,
        );
        expect(h.phase, ConnectionPhase.online);
        expect(h.state.status?.name, 'Laptop-Kamil');
      },
    );

    test('start saat sudah berjalan tidak menambah jadwal', () async {
      final h = _harness(FakeStatusRepository([_ok()]));
      await h.start();
      h.ctrl.start();
      await h.settle();

      expect(h.sched.jobs.where((job) => job.periodic && job.live).length, 1);
    });
  });

  group('transisi polling', () {
    test(
      'Connecting: 1 gagal tetap Connecting, 2 gagal jadi Offline',
      () async {
        final h = _harness(FakeStatusRepository([_down, _down]));

        await h.start();
        expect(h.phase, ConnectionPhase.connecting);

        await h.tick();
        expect(h.phase, ConnectionPhase.offline);
      },
    );

    test(
      'Online: 1 gagal tetap Online, 2 gagal berturut jadi Offline (BR-8)',
      () async {
        final h = _harness(FakeStatusRepository([_ok(), _down, _down]));
        await h.start();

        await h.tick();
        expect(h.phase, ConnectionPhase.online);

        await h.tick();
        expect(h.phase, ConnectionPhase.offline);
      },
    );

    test('sukses di antara kegagalan mereset hitungan gagal', () async {
      final h = _harness(FakeStatusRepository([_down, _ok(), _down, _down]));
      await h.start();
      await h.tick();
      expect(h.phase, ConnectionPhase.online);

      await h.tick();
      expect(h.phase, ConnectionPhase.online);

      await h.tick();
      expect(h.phase, ConnectionPhase.offline);
    });

    test('Offline lalu sukses: Back, lalu Online setelah 2 detik', () async {
      final h = _harness(FakeStatusRepository([_down, _down, _ok()]));
      await h.start();
      await h.tick();
      expect(h.phase, ConnectionPhase.offline);

      await h.poll();
      expect(h.phase, ConnectionPhase.back);
      expect(h.state.status, isNotNull);

      h.sched.fireOnce(RBehavior.reconnectedPill);
      expect(h.phase, ConnectionPhase.online);
    });

    test(
      'Back: 2 gagal berturut jadi Offline dan timer Back dibatalkan',
      () async {
        final h = _harness(
          FakeStatusRepository([_down, _down, _ok(), _down, _down]),
        );
        await h.start();
        await h.tick();
        await h.poll();
        expect(h.phase, ConnectionPhase.back);

        await h.tick();
        expect(h.phase, ConnectionPhase.back);

        await h.tick();
        expect(h.phase, ConnectionPhase.offline);
        expect(h.sched.hasLiveOnce(RBehavior.reconnectedPill), isFalse);
      },
    );

    test('timeout 3 detik dihitung sebagai gagal', () async {
      final repo = _ManualRepository();
      final h = _harness(repo);

      // The first poll (start) waits; the 2 second timeout fails it.
      h.ctrl.start();
      await h.settle();
      expect(repo.requests, hasLength(1));
      h.sched.fireOnce(RBehavior.resumeWait);
      expect(h.phase, ConnectionPhase.connecting);

      // The start timeout already counted 1 failure. A regular poll timeout (3 seconds)
      // becomes the 2nd consecutive failure, so Offline.
      final manual = h.ctrl.pollOnce();
      expect(repo.requests, hasLength(2));
      h.sched.fireOnce(const Duration(seconds: 3));
      await manual;
      expect(h.phase, ConnectionPhase.offline);
    });
  });

  group('token ditolak (BR-9)', () {
    test('401 saat Connecting: TokenRejected dan polling berhenti', () async {
      final h = _harness(
        FakeStatusRepository([fakeErrorReply(401, 'invalid_token')]),
      );
      await h.start();

      expect(h.phase, ConnectionPhase.tokenRejected);
      expect(h.sched.periodicJob, isNull);
    });

    test('401 saat Offline: TokenRejected', () async {
      final h = _harness(
        FakeStatusRepository([
          _down,
          _down,
          fakeErrorReply(401, 'invalid_token'),
        ]),
      );
      await h.start();
      await h.tick();
      expect(h.phase, ConnectionPhase.offline);

      await h.poll();
      expect(h.phase, ConnectionPhase.tokenRejected);
    });

    test(
      'reportUnauthorized saat Online: TokenRejected dan poll manual diabaikan',
      () async {
        final repo = FakeStatusRepository([_ok()]);
        final h = _harness(repo);
        await h.start();
        expect(h.phase, ConnectionPhase.online);

        h.ctrl.reportUnauthorized();
        expect(h.phase, ConnectionPhase.tokenRejected);
        expect(h.sched.periodicJob, isNull);

        final callsBefore = repo.calls;
        await h.poll();
        expect(repo.calls, callsBefore);
      },
    );
  });

  group('perintah daya (P15)', () {
    test(
      'Offline dengan perintah daya kurang dari 10 menit jadi PoweredOff',
      () async {
        final h = _harness(FakeStatusRepository([_down, _down]));
        h.container
            .read(lastPowerCommandProvider.notifier)
            .record(
              LastPowerCommand(
                action: 'shutdown',
                sentAt: h.clock.now.subtract(const Duration(minutes: 5)),
              ),
            );

        await h.start();
        await h.tick();
        expect(h.phase, ConnectionPhase.poweredOff);

        // 5 minutes left out of 10 minutes.
        h.sched.fireOnce(const Duration(minutes: 5));
        expect(h.phase, ConnectionPhase.offline);
      },
    );

    test('perintah daya lebih dari 10 menit lalu tetap Offline', () async {
      final h = _harness(FakeStatusRepository([_down, _down]));
      h.container
          .read(lastPowerCommandProvider.notifier)
          .record(
            LastPowerCommand(
              action: 'sleep',
              sentAt: h.clock.now.subtract(const Duration(minutes: 11)),
            ),
          );

      await h.start();
      await h.tick();
      expect(h.phase, ConnectionPhase.offline);
    });

    test('PoweredOff lalu sukses: Back dan perintah daya dihapus', () async {
      final h = _harness(FakeStatusRepository([_down, _down, _ok()]));
      final notifier = h.container.read(lastPowerCommandProvider.notifier)
        ..record(
          LastPowerCommand(
            action: 'shutdown',
            sentAt: h.clock.now.subtract(const Duration(minutes: 1)),
          ),
        );

      await h.start();
      await h.tick();
      expect(h.phase, ConnectionPhase.poweredOff);

      await h.poll();
      expect(h.phase, ConnectionPhase.back);
      expect(h.container.read(lastPowerCommandProvider), isNull);

      h.sched.fireOnce(RBehavior.reconnectedPill);
      expect(h.phase, ConnectionPhase.online);
      expect(notifier.state, isNull);
    });
  });

  group('poll', () {
    test(
      'paling banyak satu fetch berjalan; tick bertabrakan dilewati',
      () async {
        final repo = _ManualRepository();
        final h = _harness(repo);

        h.ctrl.start();
        await h.settle();
        expect(repo.requests, hasLength(1));

        h.sched.tick();
        await h.settle();
        expect(repo.requests, hasLength(1));

        repo.requests.single.complete(
          const AgentStatus(
            name: 'Laptop-Kamil',
            version: '1.0.0',
            uptimeSeconds: 10,
            volume: null,
            pending: null,
          ),
        );
        await h.settle();
        expect(h.phase, ConnectionPhase.online);

        h.sched.tick();
        await h.settle();
        expect(repo.requests, hasLength(2));
      },
    );

    test('pollOnce saat poll berjalan menunggu poll yang sama', () async {
      final repo = _ManualRepository();
      final h = _harness(repo);

      h.ctrl.start();
      await h.settle();
      final manual = h.ctrl.pollOnce();
      expect(repo.requests, hasLength(1));

      h.sched.fireOnce(RBehavior.resumeWait);
      await manual;
      expect(h.phase, ConnectionPhase.connecting);
    });
  });

  group('status', () {
    test(
      'volume null mempertahankan nilai terakhir, uptime ikut diperbarui',
      () async {
        final h = _harness(
          FakeStatusRepository([
            _ok(uptime: 60),
            _ok(uptime: 120, volumeUnavailable: true),
          ]),
        );
        await h.start();
        expect(h.state.status?.volume?.level, 35);

        await h.poll();
        expect(h.state.status?.volume?.level, 35);
        expect(h.state.uptime, const Duration(seconds: 120));
      },
    );
  });

  group('setFastPoll', () {
    test('2 detik saat aktif, kembali 5 detik saat nonaktif', () async {
      final h = _harness(FakeStatusRepository([_ok()]));
      await h.start();
      expect(h.sched.periodicJob?.delay, RMotion.poll);

      h.ctrl.setFastPoll(enabled: true);
      expect(h.sched.periodicJob?.delay, RBehavior.fastPoll);
      expect(h.sched.jobs.where((job) => job.periodic && job.live).length, 1);

      h.ctrl.setFastPoll(enabled: false);
      expect(h.sched.periodicJob?.delay, RMotion.poll);
    });
  });

  group('stop', () {
    test('stop membatalkan jadwal; balasan yang terlambat diabaikan', () async {
      final repo = _ManualRepository();
      final h = _harness(repo);

      h.ctrl.start();
      await h.settle();
      h.ctrl.stop();
      expect(h.sched.periodicJob, isNull);

      repo.requests.single.complete(
        const AgentStatus(
          name: 'Laptop-Kamil',
          version: '1.0.0',
          uptimeSeconds: 10,
          volume: null,
          pending: null,
        ),
      );
      await h.settle();
      expect(h.phase, ConnectionPhase.connecting);
      expect(h.state.status, isNull);
    });
  });
}
