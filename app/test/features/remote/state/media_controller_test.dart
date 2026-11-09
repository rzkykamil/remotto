import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotto/core/connection/connection_providers.dart';
import 'package:remotto/core/connection/connection_state.dart';
import 'package:remotto/core/haptics/r_haptics.dart';
import 'package:remotto/core/network/api_failure.dart';
import 'package:remotto/core/network/network_providers.dart';
import 'package:remotto/core/strings/remote_strings.dart';
import 'package:remotto/core/theme/tokens.g.dart';
import 'package:remotto/core/toast/toast_controller.dart';
import 'package:remotto/features/remote/data/media_repository.dart';

import '../../../support/fake_media_repository.dart';

import 'package:remotto/features/remote/state/media_controller.dart';
import 'package:remotto/features/remote/state/media_providers.dart';

import '../../../support/fake_poll_scheduler.dart';
import '../../../support/fake_status_repository.dart';
import '../../../support/fakes.dart';

/// Repository whose replies the test completes by hand.
final class GatedMediaRepository implements MediaRepository {
  final List<MediaAction> sent = [];
  final List<Completer<void>> pending = [];

  @override
  Future<void> send(MediaAction action) {
    sent.add(action);
    final gate = Completer<void>();
    pending.add(gate);
    return gate.future;
  }
}

void main() {
  late FakePollScheduler scheduler;
  late RecordingHapticSink sink;

  ProviderContainer makeContainer(
    MediaRepository repo, {
    FakeStatusRepository? status,
  }) {
    scheduler = FakePollScheduler();
    sink = RecordingHapticSink();
    final container = ProviderContainer(
      overrides: [
        mediaRepositoryProvider.overrideWithValue(repo),
        pollSchedulerProvider.overrideWithValue(scheduler),
        statusRepositoryProvider.overrideWithValue(
          status ??
              FakeStatusRepository(const [
                FakeTransportFailure(TimeoutFailure()),
              ]),
        ),
        hapticsProvider.overrideWithValue(
          RHaptics(sink: sink, enabled: () => true),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  MediaController ctrl(ProviderContainer c) =>
      c.read(mediaControllerProvider.notifier);

  MediaState state(ProviderContainer c) => c.read(mediaControllerProvider);

  ToastMessage? toast(ProviderContainer c) => c.read(toastControllerProvider);

  /// Lets queued microtasks (the repository reply) run.
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('state awal: playing true dan tanpa proses', () {
    final c = makeContainer(FakeMediaRepository(const [FakeMediaEcho()]));

    expect(state(c).playing, isTrue);
    expect(state(c).playProcessing, isFalse);
    expect(state(c).ringVisible, isFalse);
  });

  test('togglePlay membalik ikon langsung sebelum balasan datang', () {
    final gate = GatedMediaRepository();
    final c = makeContainer(gate);

    ctrl(c).togglePlay();

    expect(state(c).playing, isFalse);
    expect(state(c).playProcessing, isTrue);
    expect(sink.calls, isEmpty);
  });

  test(
    'cincin muncul hanya setelah processingHint dan belum muncul sebelumnya',
    () {
      final gate = GatedMediaRepository();
      final c = makeContainer(gate);

      ctrl(c).togglePlay();
      expect(state(c).ringVisible, isFalse);
      expect(scheduler.hasLiveOnce(RMotion.processingHint), isTrue);

      scheduler.fireOnce(RMotion.processingHint);
      expect(state(c).ringVisible, isTrue);
    },
  );

  test('cincin tidak muncul bila balasan lebih cepat', () async {
    final c = makeContainer(FakeMediaRepository(const [FakeMediaEcho()]));

    ctrl(c).togglePlay();
    await settle();

    expect(state(c).playProcessing, isFalse);
    expect(state(c).ringVisible, isFalse);
    expect(scheduler.hasLiveOnce(RMotion.processingHint), isFalse);
  });

  test('tap ulang play saat diproses diabaikan', () async {
    final repo = FakeMediaRepository(const [FakeMediaEcho()]);
    final c = makeContainer(repo);

    ctrl(c)
      ..togglePlay()
      ..togglePlay();
    await settle();

    expect(repo.calls, 1);
    expect(state(c).playing, isFalse);
  });

  test('sukses: ikon tetap di keadaan optimistic dan flag bersih', () async {
    final repo = FakeMediaRepository(const [FakeMediaEcho()]);
    final c = makeContainer(repo);

    ctrl(c).togglePlay();
    await settle();

    expect(repo.lastAction, MediaAction.playPause);
    expect(state(c).playing, isFalse);
    expect(state(c).playProcessing, isFalse);
    expect(toast(c), isNull);
    expect(sink.calls, isEmpty);
  });

  test('500 pada play: rollback, toast Ulangi, haptic gagal', () async {
    final repo = FakeMediaRepository([fakeMediaError(500, 'media_failed')]);
    final c = makeContainer(repo);

    ctrl(c).togglePlay();
    await settle();

    expect(state(c).playing, isTrue);
    expect(state(c).playProcessing, isFalse);
    expect(toast(c)?.text, RemoteStrings.toastCommandFailed);
    expect(toast(c)?.actionLabel, RemoteStrings.toastRetry);
    expect(toast(c)?.variant, ToastVariant.error);
    expect(sink.calls, ['vibrate']);
  });

  test('timeout pada play: rollback dan toast', () async {
    final repo = FakeMediaRepository(const [FakeMediaTimeout()]);
    final c = makeContainer(repo);

    ctrl(c).togglePlay();
    await settle();

    expect(state(c).playing, isTrue);
    expect(toast(c)?.text, RemoteStrings.toastCommandFailed);
  });

  testWidgets('repository that never replies hits the command timeout', (
    tester,
  ) async {
    final gate = GatedMediaRepository();
    final c = makeContainer(gate);

    ctrl(c).togglePlay();
    await tester.pump(RMotion.commandTimeout - const Duration(milliseconds: 1));
    expect(state(c).playProcessing, isTrue);
    expect(toast(c), isNull);

    await tester.pump(const Duration(milliseconds: 2));
    expect(state(c).playing, isTrue);
    expect(state(c).playProcessing, isFalse);
    expect(toast(c)?.text, RemoteStrings.toastCommandFailed);
    expect(sink.calls, ['vibrate']);
  });

  test('401 pada play: token ditolak dan tanpa toast', () async {
    final repo = FakeMediaRepository([fakeMediaError(401, 'invalid_token')]);
    final c = makeContainer(repo);

    ctrl(c).togglePlay();
    await settle();

    expect(state(c).playing, isTrue);
    expect(toast(c), isNull);
    expect(
      c.read(connectionControllerProvider).phase,
      ConnectionPhase.tokenRejected,
    );
  });

  test(
    '"Ulangi" pada play memanggil togglePlay lagi dengan aksi sama',
    () async {
      final repo = FakeMediaRepository([
        fakeMediaError(500, 'media_failed'),
        const FakeMediaEcho(),
      ]);
      final c = makeContainer(repo);

      ctrl(c).togglePlay();
      await settle();
      toast(c)!.onAction!();
      await settle();

      expect(repo.calls, 2);
      expect(repo.lastAction, MediaAction.playPause);
      expect(state(c).playing, isFalse);
      expect(toast(c), isNull);
    },
  );

  test('prev/next memajukan tick kedip dan mengirim aksi yang benar', () async {
    final repo = FakeMediaRepository(const [FakeMediaEcho()]);
    final c = makeContainer(repo);

    ctrl(c).prev();
    await settle();
    ctrl(c).next();
    await settle();

    expect(state(c).blinkPrev, 1);
    expect(state(c).blinkNext, 1);
    expect(repo.calls, 2);
    expect(repo.lastAction, MediaAction.next);
    expect(sink.calls, isEmpty);
  });

  test('prev/next tetap aktif saat play diproses', () async {
    final gate = GatedMediaRepository();
    final c = makeContainer(gate);

    ctrl(c).togglePlay();
    ctrl(c).next();

    expect(gate.sent, [MediaAction.playPause, MediaAction.next]);
    expect(state(c).playProcessing, isTrue);
  });

  test('prev tidak dobel sampai balasan datang', () async {
    final gate = GatedMediaRepository();
    final c = makeContainer(gate);

    ctrl(c)
      ..prev()
      ..prev();

    expect(gate.sent, [MediaAction.prev]);
    expect(state(c).blinkPrev, 1);

    gate.pending.single.complete();
    await settle();
    ctrl(c).prev();
    expect(gate.sent, [MediaAction.prev, MediaAction.prev]);
  });

  test('gagal prev: toast Ulangi mengirim prev lagi', () async {
    final repo = FakeMediaRepository([
      fakeMediaError(500, 'media_failed'),
      const FakeMediaEcho(),
    ]);
    final c = makeContainer(repo);

    ctrl(c).prev();
    await settle();
    expect(toast(c)?.text, RemoteStrings.toastCommandFailed);

    toast(c)!.onAction!();
    await settle();
    expect(repo.calls, 2);
    expect(repo.lastAction, MediaAction.prev);
  });

  test('balasan setelah dispose tidak melempar', () async {
    final gate = GatedMediaRepository();
    final c = makeContainer(gate);

    ctrl(c).togglePlay();
    c.dispose();
    gate.pending.single.completeError(const ServerFailure());

    await expectLater(settle(), completes);
  });
}
