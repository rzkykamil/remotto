import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotto/core/connection/connection_controller.dart';
import 'package:remotto/core/connection/connection_providers.dart';
import 'package:remotto/core/connection/connection_state.dart';
import 'package:remotto/core/connection/status_repository.dart';
import 'package:remotto/core/discovery/discovery_providers.dart';
import 'package:remotto/core/discovery/endpoint_resolver.dart';
import 'package:remotto/core/network/agent_status.dart';
import 'package:remotto/core/network/api_failure.dart';
import 'package:remotto/core/network/network_providers.dart';
import 'package:remotto/core/storage/pairing_data.dart';
import 'package:remotto/core/storage/storage_providers.dart';
import 'package:remotto/core/theme/r_behavior.dart';
import 'package:remotto/core/theme/tokens.g.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_endpoint_resolver.dart';
import '../../support/fake_network_change_source.dart';
import '../../support/fake_status_repository.dart';
import '../../support/fakes.dart';

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

/// Preferences baru tiap test (diisi di setUp).
late SharedPreferences _prefs;

final class _Clock {
  _Clock(this.now);

  DateTime now;
}

final class _Harness {
  _Harness(
    StatusRepository repo, {
    DateTime? now,
    PairingData? pairing,
    FakeEndpointResolver? resolver,
    FakeNetworkChangeSource? network,
  }) : clock = _Clock(now ?? DateTime(2026, 11, 8, 12)),
       resolver = resolver ?? FakeEndpointResolver(),
       network = network ?? FakeNetworkChangeSource() {
    container = ProviderContainer(
      overrides: [
        statusRepositoryProvider.overrideWithValue(repo),
        pollSchedulerProvider.overrideWithValue(sched),
        connectionClockProvider.overrideWithValue(() => clock.now),
        sharedPreferencesProvider.overrideWithValue(_prefs),
        initialPairingProvider.overrideWithValue(pairing),
        connectionStorageProvider.overrideWithValue(
          InMemoryConnectionStorage(pairing),
        ),
        endpointResolverProvider.overrideWithValue(this.resolver),
        networkChangeSourceProvider.overrideWithValue(this.network),
      ],
    );
  }

  final _FakeScheduler sched = _FakeScheduler();
  final _Clock clock;
  final FakeEndpointResolver resolver;
  final FakeNetworkChangeSource network;
  late final ProviderContainer container;

  PairingData? get pairing => container.read(pairingProvider);

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

_Harness _harness(
  StatusRepository repo, {
  DateTime? now,
  PairingData? pairing,
  FakeEndpointResolver? resolver,
  FakeNetworkChangeSource? network,
}) {
  final harness = _Harness(
    repo,
    now: now,
    pairing: pairing,
    resolver: resolver,
    network: network,
  );
  addTearDown(harness.dispose);
  addTearDown(() => harness.network.close());
  return harness;
}

const _agentId = '0123456789abcdef0123456789abcdef';
const _pairedNoId = PairingData(
  host: '192.168.1.10',
  port: 8765,
  token: '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
  laptopName: 'Laptop-Kamil',
);
final _pairedWithId = PairingData(
  host: _pairedNoId.host,
  port: _pairedNoId.port,
  token: _pairedNoId.token,
  laptopName: _pairedNoId.laptopName,
  agentId: _agentId,
);

FakeHttpReply _ok({int uptime = 60, bool volumeUnavailable = false}) =>
    fakeStatusOk(uptimeSeconds: uptime, volumeUnavailable: volumeUnavailable);

const FakeStatusStep _down = FakeTransportFailure(UnreachableFailure());

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    _prefs = await SharedPreferences.getInstance();
  });

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
    test(
      '401 setelah sukses: data status terakhir tetap dipertahankan',
      () async {
        final h = _harness(
          FakeStatusRepository([_ok(), fakeErrorReply(401, 'invalid_token')]),
        );
        await h.start();
        expect(h.phase, ConnectionPhase.online);
        expect(h.state.status?.name, 'Laptop-Kamil');
        expect(h.state.status?.volume?.level, 35);

        await h.poll();
        expect(h.phase, ConnectionPhase.tokenRejected);
        expect(h.state.status?.name, 'Laptop-Kamil');
        expect(h.state.status?.volume?.level, 35);
      },
    );

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

  group('lastPowerCommand dari preferences', () {
    String stored(DateTime sentAt, {String action = 'shutdown'}) =>
        '{"action":"$action","sentAt":"${sentAt.toUtc().toIso8601String()}"}';

    test('nilai tersimpan dibaca saat provider dibangun', () async {
      final h = _harness(FakeStatusRepository([_ok()]));
      await _prefs.setString(
        'lastPowerCommand',
        stored(h.clock.now.subtract(const Duration(minutes: 2))),
      );

      final command = h.container.read(lastPowerCommandProvider);
      expect(command?.action, 'shutdown');
      // Dibaca sebagai UTC; instan yang sama dengan jam uji.
      expect(
        command?.sentAt,
        h.clock.now.subtract(const Duration(minutes: 2)).toUtc(),
      );
    });

    test('nilai rusak diabaikan', () async {
      final h = _harness(FakeStatusRepository([_ok()]));
      await _prefs.setString('lastPowerCommand', '{rusak');

      expect(h.container.read(lastPowerCommandProvider), isNull);
    });

    test('nilai lebih dari 10 menit dibuang saat dibaca', () async {
      final h = _harness(FakeStatusRepository([_ok()]));
      await _prefs.setString(
        'lastPowerCommand',
        stored(h.clock.now.subtract(const Duration(minutes: 11))),
      );

      expect(h.container.read(lastPowerCommandProvider), isNull);
      await h.settle();
      expect(_prefs.getString('lastPowerCommand'), isNull);
    });

    test('sentAt di masa depan dibuang saat dibaca', () async {
      final h = _harness(FakeStatusRepository([_ok()]));
      await _prefs.setString(
        'lastPowerCommand',
        stored(h.clock.now.add(const Duration(minutes: 1))),
      );

      expect(h.container.read(lastPowerCommandProvider), isNull);
      await h.settle();
      expect(_prefs.getString('lastPowerCommand'), isNull);
    });

    test('record menulis preferences, clear menghapusnya', () async {
      final h = _harness(FakeStatusRepository([_ok()]));
      final sentAt = h.clock.now.subtract(const Duration(minutes: 1));
      h.container
          .read(lastPowerCommandProvider.notifier)
          .record(LastPowerCommand(action: 'restart', sentAt: sentAt));
      await h.settle();
      expect(
        _prefs.getString('lastPowerCommand'),
        stored(sentAt, action: 'restart'),
      );

      h.container.read(lastPowerCommandProvider.notifier).clear();
      await h.settle();
      expect(_prefs.getString('lastPowerCommand'), isNull);
      expect(h.container.read(lastPowerCommandProvider), isNull);
    });

    test(
      'Offline dengan perintah restart tetap Offline biasa (FR-4.11)',
      () async {
        final h = _harness(FakeStatusRepository([_down, _down]));
        await _prefs.setString(
          'lastPowerCommand',
          stored(
            h.clock.now.subtract(const Duration(minutes: 3)),
            action: 'restart',
          ),
        );

        await h.start();
        await h.tick();
        expect(h.phase, ConnectionPhase.offline);
      },
    );

    test(
      'Offline dengan perintah tersimpan langsung jadi PoweredOff',
      () async {
        final h = _harness(FakeStatusRepository([_down, _down]));
        await _prefs.setString(
          'lastPowerCommand',
          stored(h.clock.now.subtract(const Duration(minutes: 3))),
        );

        await h.start();
        await h.tick();
        expect(h.phase, ConnectionPhase.poweredOff);
      },
    );
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

  group('kembali online mengatur ulang polling cepat', () {
    test('Offline lalu sukses: interval kembali 5 detik', () async {
      final h = _harness(FakeStatusRepository([_ok(), _down, _down, _ok()]));
      await h.start();
      h.ctrl.setFastPoll(enabled: true);
      expect(h.sched.periodicJob?.delay, RBehavior.fastPoll);

      await h.tick();
      await h.tick();
      expect(h.phase, ConnectionPhase.offline);

      await h.poll();
      expect(h.phase, ConnectionPhase.back);
      expect(h.sched.periodicJob?.delay, RMotion.poll);
      expect(h.sched.jobs.where((job) => job.periodic && job.live).length, 1);

      // The fast flag was reset, so enabling it again changes the interval.
      h.ctrl.setFastPoll(enabled: true);
      expect(h.sched.periodicJob?.delay, RBehavior.fastPoll);
    });

    test('PoweredOff lalu sukses: interval kembali 5 detik', () async {
      final h = _harness(FakeStatusRepository([_ok(), _down, _down, _ok()]));
      h.container
          .read(lastPowerCommandProvider.notifier)
          .record(
            LastPowerCommand(
              action: 'sleep',
              sentAt: h.clock.now.subtract(const Duration(minutes: 1)),
            ),
          );
      await h.start();
      h.ctrl.setFastPoll(enabled: true);

      await h.tick();
      await h.tick();
      expect(h.phase, ConnectionPhase.poweredOff);

      await h.poll();
      expect(h.phase, ConnectionPhase.back);
      expect(h.sched.periodicJob?.delay, RMotion.poll);
    });
  });

  group('stop', () {
    test('stop mereset polling cepat; start berikutnya 5 detik', () async {
      final h = _harness(FakeStatusRepository([_ok(), _ok()]));
      await h.start();
      h.ctrl.setFastPoll(enabled: true);
      expect(h.sched.periodicJob?.delay, RBehavior.fastPoll);

      h.ctrl.stop();
      await h.start();
      expect(h.sched.periodicJob?.delay, RMotion.poll);
    });

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

  group('pause dan resume (FR-6.6, BR-21)', () {
    test('pause membatalkan jadwal dan poll yang sedang jalan', () async {
      final repo = _ManualRepository();
      final h = _harness(repo);

      h.ctrl.start();
      await h.settle();
      expect(repo.requests, hasLength(1));

      h.ctrl.pause();
      expect(h.sched.periodicJob, isNull);
      expect(h.sched.hasLiveOnce(RBehavior.resumeWait), isFalse);

      // The late reply from the paused poll is ignored.
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

    test('pause lalu resume menjaga polling cepat tetap aktif', () async {
      final h = _harness(FakeStatusRepository([_ok()]));
      await h.start();
      h.ctrl.setFastPoll(enabled: true);
      expect(h.sched.periodicJob?.delay, RBehavior.fastPoll);

      h.ctrl.pause();
      expect(h.sched.periodicJob, isNull);

      h.ctrl.resume();
      await h.settle();
      expect(h.sched.periodicJob?.delay, RBehavior.fastPoll);
    });

    test(
      'resume dari Online: Connecting dan poll pertama 2 detik (BR-21)',
      () async {
        final repo = _ManualRepository();
        final h = _harness(repo);

        h.ctrl.start();
        await h.settle();
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

        h.ctrl.pause();
        h.ctrl.resume();
        await h.settle();

        expect(h.phase, ConnectionPhase.connecting);
        expect(repo.requests, hasLength(2));
        expect(h.sched.hasLiveOnce(RBehavior.resumeWait), isTrue);
      },
    );

    test(
      'resume dari Offline: Connecting dan poll pertama 2 detik (BR-21)',
      () async {
        final repo = _ManualRepository();
        final h = _harness(repo);

        h.ctrl.start();
        await h.settle();
        repo.requests.last.completeError(const UnreachableFailure());
        await h.settle();
        await h.tick();
        repo.requests.last.completeError(const UnreachableFailure());
        await h.settle();
        expect(h.phase, ConnectionPhase.offline);

        h.ctrl.pause();
        h.ctrl.resume();
        await h.settle();

        expect(h.phase, ConnectionPhase.connecting);
        expect(repo.requests, hasLength(3));
        expect(h.sched.hasLiveOnce(RBehavior.resumeWait), isTrue);
      },
    );

    test(
      'resume dari PoweredOff: Connecting dan poll pertama 2 detik (BR-21)',
      () async {
        final repo = _ManualRepository();
        final h = _harness(repo);
        h.container
            .read(lastPowerCommandProvider.notifier)
            .record(
              LastPowerCommand(
                action: 'shutdown',
                sentAt: h.clock.now.subtract(const Duration(minutes: 1)),
              ),
            );

        h.ctrl.start();
        await h.settle();
        repo.requests.last.completeError(const UnreachableFailure());
        await h.settle();
        await h.tick();
        repo.requests.last.completeError(const UnreachableFailure());
        await h.settle();
        expect(h.phase, ConnectionPhase.poweredOff);

        h.ctrl.pause();
        h.ctrl.resume();
        await h.settle();

        expect(h.phase, ConnectionPhase.connecting);
        expect(repo.requests, hasLength(3));
        expect(h.sched.hasLiveOnce(RBehavior.resumeWait), isTrue);
      },
    );

    test('resume dari Online: poll pertama habis waktu tetap Connecting, poll kedua gagal jadi Offline (FR-6.6, BR-21)', () async {
      final repo = _ManualRepository();
      final h = _harness(repo);

      h.ctrl.start();
      await h.settle();
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

      h.ctrl.pause();
      h.ctrl.resume();
      await h.settle();
      expect(h.phase, ConnectionPhase.connecting);

      // Poll pertama habis waktu 2 detik: satu kegagalan, masih Connecting.
      h.sched.fireOnce(RBehavior.resumeWait);
      await h.settle();
      expect(h.phase, ConnectionPhase.connecting);

      // Poll kedua gagal: dua kegagalan berturut, jadi Offline.
      await h.tick();
      repo.requests.last.completeError(const UnreachableFailure());
      await h.settle();
      expect(h.phase, ConnectionPhase.offline);
    });

    test('resume dari PoweredOff: dua poll gagal kembali PoweredOff selama perintah daya masih berlaku (FR-6.6, P15)', () async {
      final repo = _ManualRepository();
      final h = _harness(repo);
      h.container
          .read(lastPowerCommandProvider.notifier)
          .record(
            LastPowerCommand(
              action: 'shutdown',
              sentAt: h.clock.now.subtract(const Duration(minutes: 1)),
            ),
          );

      h.ctrl.start();
      await h.settle();
      repo.requests.last.completeError(const UnreachableFailure());
      await h.settle();
      await h.tick();
      repo.requests.last.completeError(const UnreachableFailure());
      await h.settle();
      expect(h.phase, ConnectionPhase.poweredOff);

      h.ctrl.pause();
      h.ctrl.resume();
      await h.settle();
      expect(h.phase, ConnectionPhase.connecting);

      // Poll pertama habis waktu: masih Connecting.
      h.sched.fireOnce(RBehavior.resumeWait);
      await h.settle();
      expect(h.phase, ConnectionPhase.connecting);

      // Poll kedua gagal: kembali PoweredOff karena perintah daya kurang dari 10 menit.
      await h.tick();
      repo.requests.last.completeError(const UnreachableFailure());
      await h.settle();
      expect(h.phase, ConnectionPhase.poweredOff);
    });

    test('resume saat TokenRejected tidak melakukan apa-apa (BR-9)', () async {
      final repo = FakeStatusRepository([fakeErrorReply(401, 'invalid_token')]);
      final h = _harness(repo);
      await h.start();
      expect(h.phase, ConnectionPhase.tokenRejected);

      final callsBefore = repo.calls;
      h.ctrl.resume();
      await h.settle();

      expect(h.phase, ConnectionPhase.tokenRejected);
      expect(repo.calls, callsBefore);
      expect(h.sched.periodicJob, isNull);
      expect(h.sched.hasLiveOnce(RBehavior.resumeWait), isFalse);
    });
  });

  group('penemuan ulang endpoint (M7, D6)', () {
    test('satu poll gagal memicu rediscover tanpa paksa, lalu poll ke endpoint baru', () async {
      final h = _harness(
        FakeStatusRepository([_down, _ok()]),
        pairing: _pairedWithId,
        resolver: FakeEndpointResolver(results: [RediscoverResult.updated]),
      );
      await h.start();

      expect(h.resolver.forceCalls, [false]);
      expect(h.phase, ConnectionPhase.online);
      expect(h.state.status?.name, 'Laptop-Kamil');
    });

    test('rediscover tidak memblokir poll: poll berikutnya tetap jalan saat rediscover masih menunggu', () async {
      final h = _harness(
        FakeStatusRepository([_down, _ok()]),
        pairing: _pairedWithId,
        resolver: FakeEndpointResolver(manual: true),
      );
      await h.start();
      expect(h.resolver.held, hasLength(1));
      expect(h.phase, ConnectionPhase.connecting);

      await h.tick();
      expect(h.phase, ConnectionPhase.online);
      expect(h.resolver.callCount, 1);
    });

    test(
      'updated saat Online: fase tetap Online setelah poll ke endpoint baru',
      () async {
        final h = _harness(
          FakeStatusRepository([_ok(), _down, _ok()]),
          pairing: _pairedWithId,
          resolver: FakeEndpointResolver(results: [RediscoverResult.updated]),
        );
        await h.start();
        expect(h.phase, ConnectionPhase.online);

        await h.tick();
        expect(h.resolver.forceCalls, [false]);
        expect(h.phase, ConnectionPhase.online);
      },
    );

    test('none saat Offline: fase tidak berubah, rediscover dicoba lagi tanpa paksa', () async {
      final h = _harness(
        FakeStatusRepository([_down, _down, _down]),
        pairing: _pairedWithId,
        resolver: FakeEndpointResolver(),
      );
      await h.start();
      await h.tick();
      expect(h.phase, ConnectionPhase.offline);

      await h.tick();
      expect(h.phase, ConnectionPhase.offline);
      expect(h.resolver.forceCalls, [false, false, false]);
    });

    test('tokenRejected dari rediscover: fase TokenRejected, polling berhenti, tidak ada rediscover lagi', () async {
      final repo = FakeStatusRepository([_ok(), _down]);
      final h = _harness(
        repo,
        pairing: _pairedWithId,
        resolver: FakeEndpointResolver(
          results: [RediscoverResult.tokenRejected],
        ),
      );
      await h.start();
      await h.tick();

      expect(h.phase, ConnectionPhase.tokenRejected);
      expect(h.sched.periodicJob, isNull);
      expect(h.network.subscribed, isFalse);

      final callsBefore = repo.calls;
      await h.poll();
      h.network.emit();
      h.ctrl.resume();
      await h.settle();

      expect(repo.calls, callsBefore);
      expect(h.resolver.callCount, 1);
      expect(h.phase, ConnectionPhase.tokenRejected);
    });

    test('stop saat rediscover tertahan: tokenRejected yang datang kemudian tidak mengubah fase', () async {
      final h = _harness(
        FakeStatusRepository([_down]),
        pairing: _pairedWithId,
        resolver: FakeEndpointResolver(manual: true),
      );
      await h.start();
      expect(h.resolver.held, hasLength(1));
      expect(h.phase, ConnectionPhase.connecting);

      h.ctrl.stop();
      h.resolver.held.single.complete(RediscoverResult.tokenRejected);
      await h.settle();

      expect(h.phase, ConnectionPhase.connecting);
    });

    test('pause saat rediscover tertahan: tokenRejected yang datang kemudian tidak mengubah fase', () async {
      final h = _harness(
        FakeStatusRepository([_down]),
        pairing: _pairedWithId,
        resolver: FakeEndpointResolver(manual: true),
      );
      await h.start();
      expect(h.resolver.held, hasLength(1));

      h.ctrl.pause();
      h.resolver.held.single.complete(RediscoverResult.tokenRejected);
      await h.settle();

      expect(h.phase, ConnectionPhase.connecting);
    });

    test('resolver tanpa kandidat (legacy, none) tidak mengubah fase pada kegagalan', () async {
      final h = _harness(
        FakeStatusRepository([_down, _ok()]),
        pairing: _pairedNoId,
        resolver: FakeEndpointResolver(results: [RediscoverResult.none]),
      );
      await h.start();
      expect(h.phase, ConnectionPhase.connecting);

      await h.tick();
      expect(h.phase, ConnectionPhase.online);
    });

    test(
      'event jaringan lokal: debounce 1 detik lalu rediscover paksa dan poll',
      () async {
        final repo = FakeStatusRepository([_ok(), _ok()]);
        final h = _harness(
          repo,
          pairing: _pairedWithId,
          resolver: FakeEndpointResolver(results: [RediscoverResult.none]),
        );
        await h.start();
        final callsBefore = repo.calls;

        h.network.emit();
        await h.settle();
        expect(h.sched.hasLiveOnce(RBehavior.networkChangeDebounce), isTrue);
        expect(h.resolver.callCount, 0);

        h.sched.fireOnce(RBehavior.networkChangeDebounce);
        await h.settle();

        expect(h.resolver.forceCalls, [true]);
        expect(repo.calls, callsBefore + 1);
        expect(h.phase, ConnectionPhase.online);
      },
    );

    test('event jaringan bukan Wi-Fi/Ethernet: tidak ada rediscover dan tidak ada poll', () async {
      final repo = FakeStatusRepository([_ok()]);
      final network = FakeNetworkChangeSource(onLocal: false);
      final h = _harness(
        repo,
        pairing: _pairedWithId,
        network: network,
        resolver: FakeEndpointResolver(),
      );
      await h.start();
      final callsBefore = repo.calls;

      network.emit();
      await h.settle();
      h.sched.fireOnce(RBehavior.networkChangeDebounce);
      await h.settle();

      expect(h.resolver.callCount, 0);
      expect(repo.calls, callsBefore);
    });

    test(
      'pause menghentikan langganan jaringan, resume memasangnya lagi',
      () async {
        final h = _harness(
          FakeStatusRepository([_ok()]),
          pairing: _pairedWithId,
          resolver: FakeEndpointResolver(),
        );
        await h.start();
        expect(h.network.subscribed, isTrue);

        h.ctrl.pause();
        expect(h.network.subscribed, isFalse);
        expect(h.sched.hasLiveOnce(RBehavior.networkChangeDebounce), isFalse);

        h.ctrl.resume();
        await h.settle();
        expect(h.network.subscribed, isTrue);
      },
    );

    test(
      'backfill: poll sukses dengan agentId mengisi pairing lama sekali',
      () async {
        final h = _harness(
          FakeStatusRepository([
            FakeHttpReply(
              200,
              jsonEncode({
                'data': {
                  'name': 'Laptop-Kamil',
                  'version': '1.0.0',
                  'uptimeSeconds': 1,
                  'volume': {'level': 35, 'muted': false},
                  'pending': null,
                  'agentId': _agentId,
                },
              }),
            ),
          ]),
          pairing: _pairedNoId,
        );
        await h.start();

        expect(h.pairing?.agentId, _agentId);
        expect(h.pairing?.host, _pairedNoId.host);
        expect(h.pairing?.token, _pairedNoId.token);
        expect(h.state.status?.agentId, _agentId);

        await h.tick();
        expect(h.pairing?.agentId, _agentId);
        expect(h.phase, ConnectionPhase.online);
      },
    );

    test('backfill tidak terjadi bila agent belum mengirim agentId', () async {
      final h = _harness(FakeStatusRepository([_ok()]), pairing: _pairedNoId);
      await h.start();

      expect(h.pairing?.agentId, isNull);
      expect(h.state.status?.agentId, isNull);
    });
  });
}
