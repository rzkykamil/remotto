import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotto/core/connection/connection_providers.dart';
import 'package:remotto/core/connection/connection_state.dart';
import 'package:remotto/core/haptics/r_haptics.dart';
import 'package:remotto/core/network/agent_status.dart';
import 'package:remotto/core/network/api_failure.dart';
import 'package:remotto/core/network/network_providers.dart';
import 'package:remotto/core/strings/remote_strings.dart';
import 'package:remotto/core/toast/toast_controller.dart';
import 'package:remotto/features/remote/data/volume_repository.dart';
import 'package:remotto/features/remote/state/volume_controller.dart';
import 'package:remotto/features/remote/state/volume_providers.dart';

import '../../../support/fake_poll_scheduler.dart';
import '../../../support/fake_status_repository.dart';
import '../../../support/fake_volume_repository.dart';
import '../../../support/fakes.dart';

/// Repository whose replies the test completes by hand. Records each call.
final class GatedVolumeRepository implements VolumeRepository {
  final List<String> calls = [];
  final List<Completer<VolumeStatus>> pending = [];

  Future<VolumeStatus> _gate(String name) {
    calls.add(name);
    final gate = Completer<VolumeStatus>();
    pending.add(gate);
    return gate.future;
  }

  @override
  Future<VolumeStatus> setLevel(int level) => _gate('setLevel');

  @override
  Future<VolumeStatus> up() => _gate('up');

  @override
  Future<VolumeStatus> down() => _gate('down');

  @override
  Future<VolumeStatus> setMuted(bool muted) => _gate('setMuted');
}

void main() {
  late FakePollScheduler scheduler;
  late RecordingHapticSink sink;

  ProviderContainer makeContainer({
    required VolumeRepository repo,
    List<FakeStatusStep> status = const [],
  }) {
    scheduler = FakePollScheduler();
    sink = RecordingHapticSink();
    final container = ProviderContainer(
      overrides: [
        volumeRepositoryProvider.overrideWithValue(repo),
        pollSchedulerProvider.overrideWithValue(scheduler),
        statusRepositoryProvider.overrideWithValue(
          FakeStatusRepository(status.isEmpty ? [fakeStatusOk()] : status),
        ),
        hapticsProvider.overrideWithValue(
          RHaptics(sink: sink, enabled: () => true),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  VolumeController ctrl(ProviderContainer c) =>
      c.read(volumeControllerProvider.notifier);

  VolumeState state(ProviderContainer c) => c.read(volumeControllerProvider);

  ToastMessage? toast(ProviderContainer c) => c.read(toastControllerProvider);

  /// Lets queued microtasks (repository replies) run.
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  /// Starts polling (first poll now), reading the volume controller first so it listens.
  Future<void> startPolling(ProviderContainer c) async {
    c.read(volumeControllerProvider);
    c.read(connectionControllerProvider.notifier).start();
    await settle();
  }

  /// One periodic poll.
  Future<void> poll() async {
    scheduler.tick();
    await settle();
  }

  test('known false sebelum ada status volume', () {
    final c = makeContainer(repo: FakeVolumeRepository());
    c.read(volumeControllerProvider);
    expect(state(c).known, isFalse);
  });

  test('dragStart diabaikan saat volume belum diketahui', () {
    final c = makeContainer(repo: FakeVolumeRepository());
    c.read(volumeControllerProvider);
    ctrl(c).dragStart(50);
    expect(state(c).dragging, isFalse);
  });

  test('sinkron dari polling saat idle', () async {
    final c = makeContainer(
      repo: FakeVolumeRepository(),
      status: [fakeStatusOk(volumeLevel: 35), fakeStatusOk(volumeLevel: 40)],
    );
    await startPolling(c);
    expect(state(c).level, 35);
    expect(state(c).known, isTrue);

    await poll();
    expect(state(c).level, 40);
    expect(state(c).confirmed, const VolumeStatus(level: 40, muted: false));
  });

  test('volume null di status tidak mengubah state', () async {
    final c = makeContainer(
      repo: FakeVolumeRepository(),
      status: [
        fakeStatusOk(volumeLevel: 35),
        fakeStatusOk(volumeUnavailable: true),
      ],
    );
    await startPolling(c);
    await poll();
    expect(state(c).level, 35);
    expect(state(c).confirmed, const VolumeStatus(level: 35, muted: false));
  });

  test(
    'polling ditahan saat dragging lalu diterapkan saat drag dibatalkan',
    () async {
      final c = makeContainer(
        repo: FakeVolumeRepository(),
        status: [fakeStatusOk(volumeLevel: 35), fakeStatusOk(volumeLevel: 40)],
      );
      await startPolling(c);

      ctrl(c).dragStart(50);
      await poll();
      expect(state(c).level, 50, reason: 'angka jari tidak ditimpa polling');

      ctrl(c).dragCancel();
      expect(
        state(c).level,
        40,
        reason: 'status tertahan diterapkan saat idle',
      );
    },
  );

  test('balasan kirim membuang status tertahan yang lebih lama', () async {
    final repo = FakeVolumeRepository();
    final c = makeContainer(
      repo: repo,
      status: [fakeStatusOk(volumeLevel: 35), fakeStatusOk(volumeLevel: 40)],
    );
    await startPolling(c);

    ctrl(c).dragStart(50);
    await poll();
    ctrl(c).dragEnd(50);
    await settle();

    expect(repo.lastLevel, 50);
    expect(state(c).level, 50);
    expect(state(c).confirmed, const VolumeStatus(level: 50, muted: false));
  });

  test(
    'drag mengirim setLevel terakhir; finish ke nilai sama tidak dikirim lagi',
    () async {
      final repo = FakeVolumeRepository();
      final c = makeContainer(repo: repo);
      await startPolling(c);

      ctrl(c)
        ..dragStart(50)
        ..dragUpdate(60)
        ..dragEnd(60);
      await settle();

      expect(repo.setLevelCalls, 1);
      expect(repo.lastLevel, 60);
      expect(state(c).level, 60);
      expect(state(c).dragging, isFalse);
    },
  );

  test('drag saat muted: muted false lokal lalu terkirim', () async {
    final repo = FakeVolumeRepository(initialMuted: true);
    final c = makeContainer(
      repo: repo,
      status: [fakeStatusOk(volumeMuted: true)],
    );
    await startPolling(c);
    expect(state(c).muted, isTrue);

    ctrl(c).dragStart(40);
    expect(state(c).muted, isFalse);
    ctrl(c).dragEnd(40);
    await settle();

    expect(repo.current.muted, isFalse);
    expect(state(c).confirmed?.muted, isFalse);
  });

  test('dragCancel mengembalikan nilai tanpa mengirim', () async {
    final repo = FakeVolumeRepository();
    final c = makeContainer(repo: repo);
    await startPolling(c);

    ctrl(c).dragStart(50);
    ctrl(c).dragCancel();
    await settle();

    expect(state(c).level, 35);
    expect(state(c).dragging, isFalse);
    expect(repo.setLevelCalls, 0);
  });

  test(
    'gagal slider dua kali: rollback, toast berisi persen laptop, haptic gagal',
    () async {
      final repo = FakeVolumeRepository(
        script: [fakeVolumeError(500, 'audio_failed')],
      );
      final c = makeContainer(repo: repo);
      await startPolling(c);

      ctrl(c)
        ..dragStart(50)
        ..dragEnd(50);
      await settle();

      expect(repo.setLevelCalls, 2, reason: 'satu retry diam-diam');
      expect(state(c).level, 35);
      expect(state(c).dragging, isFalse);
      final message = toast(c);
      expect(message?.text, RemoteStrings.toastVolumeFailed(35));
      expect(message?.actionLabel, RemoteStrings.toastRetry);
      expect(sink.calls, contains('vibrate'));
    },
  );

  test('Ulangi mengirim ulang nilai yang gagal', () async {
    final repo = FakeVolumeRepository(
      script: [
        fakeVolumeError(500, 'audio_failed'),
        fakeVolumeError(500, 'audio_failed'),
        const FakeVolumeOk(),
      ],
    );
    final c = makeContainer(repo: repo);
    await startPolling(c);

    ctrl(c)
      ..dragStart(50)
      ..dragEnd(50);
    await settle();
    expect(state(c).level, 35);

    toast(c)!.onAction!.call();
    await settle();

    expect(repo.lastLevel, 50);
    expect(state(c).level, 50);
    expect(state(c).confirmed?.level, 50);
    expect(toast(c), isNull);
  });

  test('401 pada slider: reportUnauthorized tanpa toast', () async {
    final repo = FakeVolumeRepository(
      script: [fakeVolumeError(401, 'invalid_token')],
    );
    final c = makeContainer(repo: repo);
    await startPolling(c);

    ctrl(c)
      ..dragStart(50)
      ..dragEnd(50);
    await settle();

    expect(
      c.read(connectionControllerProvider).phase,
      ConnectionPhase.tokenRejected,
    );
    expect(toast(c), isNull);
    expect(repo.setLevelCalls, 1, reason: '401 tidak di-retry');
  });

  test(
    'down di 0 dan up di 100 tidak mengirim dan memberi haptic batas',
    () async {
      final lowRepo = FakeVolumeRepository();
      final low = makeContainer(
        repo: lowRepo,
        status: [fakeStatusOk(volumeLevel: 0)],
      );
      await startPolling(low);
      ctrl(low).down();
      await settle();
      expect(lowRepo.downCalls, 0);
      expect(sink.calls, contains('medium'));

      sink.calls.clear();
      final highRepo = FakeVolumeRepository();
      final high = makeContainer(
        repo: highRepo,
        status: [fakeStatusOk(volumeLevel: 100)],
      );
      await startPolling(high);
      ctrl(high).up();
      await settle();
      expect(highRepo.upCalls, 0);
      expect(sink.calls, contains('medium'));
    },
  );

  test('up menaikkan 5 optimistic dan menyetel dari balasan', () async {
    final repo = FakeVolumeRepository();
    final c = makeContainer(repo: repo);
    await startPolling(c);

    ctrl(c).up();
    expect(state(c).level, 40, reason: 'optimistic sebelum balasan');
    await settle();

    expect(repo.upCalls, 1);
    expect(state(c).level, 40);
    expect(state(c).confirmed?.level, 40);
  });

  test('up gagal: tanpa retry, rollback, toast perintah gagal', () async {
    final repo = FakeVolumeRepository(script: [const FakeVolumeTimeout()]);
    final c = makeContainer(repo: repo);
    await startPolling(c);

    ctrl(c).up();
    await settle();

    expect(repo.upCalls, 1);
    expect(state(c).level, 35);
    expect(toast(c)?.text, RemoteStrings.toastCommandFailed);
    expect(toast(c)?.actionLabel, RemoteStrings.toastRetry);
  });

  test('tap ulang −/+ saat request berjalan diabaikan', () async {
    final repo = GatedVolumeRepository();
    final c = makeContainer(repo: repo);
    await startPolling(c);

    ctrl(c)
      ..up()
      ..up();
    await settle();

    expect(repo.calls, ['up']);
  });

  test('mute dua kali cepat hanya satu panggilan', () async {
    final repo = GatedVolumeRepository();
    final c = makeContainer(repo: repo);
    await startPolling(c);

    unawaited(ctrl(c).toggleMute());
    unawaited(ctrl(c).toggleMute());
    await settle();

    expect(repo.calls, ['setMuted']);
    expect(state(c).muted, isTrue);
  });

  test('mute gagal dua kali: rollback dan toast', () async {
    final repo = FakeVolumeRepository(
      script: [fakeVolumeError(500, 'audio_failed')],
    );
    final c = makeContainer(repo: repo);
    await startPolling(c);

    await ctrl(c).toggleMute();

    expect(repo.setMutedCalls, 2);
    expect(state(c).muted, isFalse);
    expect(toast(c)?.text, RemoteStrings.toastCommandFailed);
  });

  test('haptic detent saat slider melewati kelipatan 5', () async {
    final c = makeContainer(repo: FakeVolumeRepository());
    await startPolling(c);

    ctrl(c)
      ..dragStart(33)
      ..dragUpdate(37);

    expect(sink.calls, contains('selection'));
  });

  /// Status script: one good poll, then two failed polls (offline, BR-8).
  List<FakeStatusStep> offlineScript({List<FakeStatusStep> then = const []}) =>
      [
        fakeStatusOk(volumeLevel: 35),
        const FakeTransportFailure(UnreachableFailure()),
        const FakeTransportFailure(UnreachableFailure()),
        ...then,
      ];

  /// Two failed polls in a row, so the connection goes offline.
  Future<void> goOffline() async {
    scheduler.tick();
    await settle();
    scheduler.tick();
    await settle();
  }

  test('offline saat drag: drag batal, kembali ke confirmed, tanpa setLevel dan toast', () async {
    final repo = FakeVolumeRepository();
    final c = makeContainer(repo: repo, status: offlineScript());
    await startPolling(c);

    ctrl(c).dragStart(50);
    expect(state(c).dragging, isTrue);

    await goOffline();

    expect(c.read(connectionControllerProvider).phase, ConnectionPhase.offline);
    expect(state(c).dragging, isFalse);
    expect(state(c).level, 35);
    expect(state(c).muted, isFalse);
    expect(repo.setLevelCalls, 0);
    expect(toast(c), isNull);
  });

  test(
    'offline saat request berjalan: balasan sukses diabaikan, tanpa retry',
    () async {
      final repo = GatedVolumeRepository();
      final c = makeContainer(repo: repo, status: offlineScript());
      await startPolling(c);

      ctrl(c)
        ..dragStart(50)
        ..dragUpdate(60);
      await settle();
      expect(repo.calls, ['setLevel']);

      await goOffline();
      expect(state(c).dragging, isFalse);
      expect(state(c).level, 35);

      // The laptop answers after the cancel. The reply must not be applied.
      repo.pending.single.complete(const VolumeStatus(level: 60, muted: false));
      await settle();

      expect(state(c).level, 35);
      expect(state(c).confirmed, const VolumeStatus(level: 35, muted: false));
      expect(repo.calls, ['setLevel'], reason: 'tanpa retry');
      expect(toast(c), isNull);
    },
  );

  test('offline saat request berjalan: balasan gagal diabaikan, tanpa retry dan toast', () async {
    final repo = GatedVolumeRepository();
    final c = makeContainer(repo: repo, status: offlineScript());
    await startPolling(c);

    ctrl(c)
      ..dragStart(50)
      ..dragUpdate(60);
    await settle();

    await goOffline();
    repo.pending.single.completeError(const ServerFailure());
    await settle();

    expect(repo.calls, ['setLevel'], reason: 'tanpa retry');
    expect(state(c).level, 35);
    expect(state(c).dragging, isFalse);
    expect(toast(c), isNull);
  });

  test(
    'offline saat −/+ berjalan: balasan diabaikan, nilai tetap confirmed',
    () async {
      final repo = GatedVolumeRepository();
      final c = makeContainer(repo: repo, status: offlineScript());
      await startPolling(c);

      ctrl(c).up();
      await settle();
      expect(state(c).level, 40, reason: 'optimistic');

      await goOffline();
      expect(state(c).level, 35);

      repo.pending.single.complete(const VolumeStatus(level: 40, muted: false));
      await settle();

      expect(state(c).level, 35);
      expect(state(c).confirmed?.level, 35);
      expect(repo.calls, ['up']);
      expect(toast(c), isNull);
    },
  );

  test(
    'offline saat mute berjalan: balasan diabaikan, tanpa retry dan toast',
    () async {
      final repo = GatedVolumeRepository();
      final c = makeContainer(repo: repo, status: offlineScript());
      await startPolling(c);

      unawaited(ctrl(c).toggleMute());
      await settle();
      expect(state(c).muted, isTrue, reason: 'optimistic');

      await goOffline();
      expect(state(c).muted, isFalse);

      repo.pending.single.completeError(const ServerFailure());
      await settle();

      expect(repo.calls, ['setMuted'], reason: 'tanpa retry setelah cancel');
      expect(state(c).muted, isFalse);
      expect(toast(c), isNull);
    },
  );

  test('tokenRejected saat drag: drag batal, tanpa toast', () async {
    final repo = FakeVolumeRepository();
    final c = makeContainer(
      repo: repo,
      status: [
        fakeStatusOk(volumeLevel: 35),
        fakeErrorReply(401, 'invalid_token'),
      ],
    );
    await startPolling(c);

    ctrl(c).dragStart(50);
    scheduler.tick();
    await settle();

    expect(
      c.read(connectionControllerProvider).phase,
      ConnectionPhase.tokenRejected,
    );
    expect(state(c).dragging, isFalse);
    expect(state(c).level, 35);
    expect(repo.setLevelCalls, 0);
    expect(toast(c), isNull);
  });

  test(
    'perubahan phase tanpa poll baru tidak menimpa balasan perintah',
    () async {
      final repo = FakeVolumeRepository();
      final c = makeContainer(
        repo: repo,
        status: [
          fakeStatusOk(volumeLevel: 35),
          fakeErrorReply(401, 'invalid_token'),
        ],
      );
      await startPolling(c);

      ctrl(c).up();
      await settle();
      expect(state(c).confirmed?.level, 40);

      // The 401 changes only the phase; the status object is the old poll.
      scheduler.tick();
      await settle();

      expect(
        c.read(connectionControllerProvider).phase,
        ConnectionPhase.tokenRejected,
      );
      expect(state(c).level, 40);
      expect(state(c).confirmed?.level, 40);
    },
  );

  test('setelah pulih dari offline, nilai disinkron dari laptop', () async {
    final c = makeContainer(
      repo: FakeVolumeRepository(),
      status: offlineScript(then: [fakeStatusOk(volumeLevel: 40)]),
    );
    await startPolling(c);

    ctrl(c).dragStart(50);
    await goOffline();
    expect(state(c).level, 35);

    scheduler.tick();
    await settle();

    expect(c.read(connectionControllerProvider).phase, ConnectionPhase.back);
    expect(state(c).level, 40);
    expect(state(c).confirmed, const VolumeStatus(level: 40, muted: false));
    expect(state(c).dragging, isFalse);
  });
}
