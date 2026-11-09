import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:remotto/core/network/api_failure.dart';
import 'package:remotto/core/theme/tokens.g.dart';
import 'package:remotto/features/remote/state/volume_sender.dart';

import '../../../../test/support/fake_poll_scheduler.dart';

final class _Harness {
  _Harness({Duration? timeout}) {
    sender = VolumeSender(
      scheduler: scheduler,
      send: (level) {
        calls.add(level);
        final completer = Completer<void>();
        completers.add(completer);
        return completer.future;
      },
      onFailed: failed.add,
      onIdle: () => idleCount++,
      timeout: timeout ?? RMotion.commandTimeout,
    );
  }

  final FakePollScheduler scheduler = FakePollScheduler();
  final List<int> calls = [];
  final List<Completer<void>> completers = [];
  final List<int> failed = [];
  int idleCount = 0;
  late final VolumeSender sender;

  /// Completes the request at [index] successfully and lets it settle.
  Future<void> succeed(int index) async {
    completers[index].complete();
    await pumpEventQueue();
  }

  /// Fails the request at [index] with [failure] and lets it settle.
  Future<void> fail(int index, Object failure) async {
    completers[index].completeError(failure);
    await pumpEventQueue();
  }
}

void main() {
  group('VolumeSender', () {
    test(
      'BR-14: sepuluh submit beruntun hanya kirim pertama dan terbaru',
      () async {
        final h = _Harness();
        h.sender.submit(1);
        for (var level = 2; level <= 10; level++) {
          h.sender.submit(level);
        }
        expect(h.calls, [1]);
        expect(h.completers.length, 1, reason: 'maks satu request berjalan');

        await h.succeed(0);
        h.scheduler.fireOnce(RMotion.sendThrottle);
        expect(h.calls, [1, 10]);
      },
    );

    test('cancelPending saat request berjalan: hasil gagal dibuang, tanpa retry dan onFailed', () async {
      final h = _Harness();
      h.sender.submit(1);
      h.sender.cancelPending();

      await h.fail(0, const TimeoutFailure());
      expect(h.calls, [1], reason: 'tanpa retry');
      expect(h.failed, isEmpty);
      expect(h.sender.busy, isFalse);
      expect(h.idleCount, 1);
    });

    test('cancelPending saat request berjalan: hasil sukses tidak dihitung terkirim', () async {
      final h = _Harness();
      h.sender.submit(1);
      h.sender.cancelPending();
      await h.succeed(0);

      // Nothing was confirmed, so a finish of the same level is sent.
      h.sender.finish(1);
      expect(h.calls, [1, 1]);
    });

    test(
      'BR-14: kirim kedua menunggu throttle 100 ms sejak kirim pertama',
      () async {
        final h = _Harness();
        h.sender.submit(1);
        await h.succeed(0);

        h.sender.submit(2);
        expect(h.calls, [1], reason: 'masih dalam throttle');
        expect(h.scheduler.hasLiveOnce(RMotion.sendThrottle), isTrue);

        h.scheduler.fireOnce(RMotion.sendThrottle);
        expect(h.calls, [1, 2]);
      },
    );

    test('BR-14: finish terkirim walau request lain sedang berjalan', () async {
      final h = _Harness();
      h.sender.submit(5);
      expect(h.calls, [5]);

      h.sender.finish(40);
      expect(h.calls, [5], reason: 'menunggu request berjalan selesai');

      await h.succeed(0);
      expect(h.calls, [5, 40]);
      expect(h.completers.length, 2);
    });

    test(
      'finish dengan nilai sama seperti sukses terakhir tidak dikirim',
      () async {
        final h = _Harness();
        h.sender.submit(30);
        await h.succeed(0);
        expect(h.idleCount, 1);

        h.sender.finish(30);
        expect(h.calls, [30]);
        expect(h.sender.busy, isFalse);
        expect(h.idleCount, 1);
      },
    );

    test('gagal sekali lalu sukses: tanpa onFailed', () async {
      final h = _Harness();
      h.sender.submit(7);
      await h.fail(0, const TimeoutFailure());
      expect(h.calls, [7, 7], reason: 'retry diam-diam nilai sama');
      expect(h.failed, isEmpty);

      await h.succeed(1);
      expect(h.failed, isEmpty);
      expect(h.sender.busy, isFalse);
    });

    test('gagal dua kali: onFailed sekali dan tertunda dibuang', () async {
      final h = _Harness();
      h.sender.submit(7);
      await h.fail(0, const TimeoutFailure());
      await h.fail(1, const UnreachableFailure());
      expect(h.calls, [7, 7]);
      expect(h.failed, [7]);
      expect(h.sender.busy, isFalse);
      expect(h.idleCount, 1);
    });

    test('401 tidak di-retry, langsung onFailed', () async {
      final h = _Harness();
      h.sender.submit(7);
      await h.fail(0, const UnauthorizedFailure(code: 'invalid_token'));
      expect(h.calls, [7]);
      expect(h.failed, [7]);
    });

    test(
      'TimeoutFailure di-retry sekali lalu onFailed pada gagal kedua',
      () async {
        final h = _Harness();
        h.sender.submit(7);
        await h.fail(0, const TimeoutFailure());
        expect(h.calls, [7, 7], reason: 'retry diam-diam sekali');
        expect(h.failed, isEmpty);

        await h.fail(1, const TimeoutFailure());
        expect(h.calls, [7, 7], reason: 'tanpa retry ketiga');
        expect(h.failed, [7]);
      },
    );

    test(
      '429 (RateLimitedFailure) tidak di-retry, langsung onFailed',
      () async {
        final h = _Harness();
        h.sender.submit(7);
        await h.fail(0, const RateLimitedFailure());
        expect(h.calls, [7]);
        expect(h.failed, [7]);
        expect(h.idleCount, 1);
      },
    );

    test('403 (ForbiddenFailure) tidak di-retry, langsung onFailed', () async {
      final h = _Harness();
      h.sender.submit(7);
      await h.fail(0, const ForbiddenFailure());
      expect(h.calls, [7]);
      expect(h.failed, [7]);
    });

    test('500 (ServerFailure) tidak di-retry, langsung onFailed', () async {
      final h = _Harness();
      h.sender.submit(7);
      await h.fail(0, const ServerFailure());
      expect(h.calls, [7]);
      expect(h.failed, [7]);
    });

    test('timeout dihitung gagal lalu di-retry sekali', () async {
      final h = _Harness(timeout: const Duration(milliseconds: 1));
      h.sender.submit(7);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(h.calls, [7, 7]);
      expect(h.failed, [7]);
    });

    test('cancelPending membuang nilai tertunda', () async {
      final h = _Harness();
      h.sender.submit(1);
      h.sender.submit(2);
      expect(h.sender.busy, isTrue);

      h.sender.cancelPending();
      await h.succeed(0);
      h.scheduler.fireOnce(RMotion.sendThrottle);
      expect(h.calls, [1]);
      expect(h.sender.busy, isFalse);
    });

    test('onIdle sekali setelah semua request dan tertunda selesai', () async {
      final h = _Harness();
      h.sender.submit(1);
      h.sender.submit(2);
      await h.succeed(0);
      expect(h.idleCount, 0, reason: 'nilai 2 masih tertunda');

      h.scheduler.fireOnce(RMotion.sendThrottle);
      expect(h.calls, [1, 2]);
      await h.succeed(1);
      expect(h.idleCount, 1);
    });

    test(
      'setConfirmed: finish ke level yang sudah dikonfirmasi tidak dikirim',
      () async {
        final h = _Harness();
        h.sender.setConfirmed(40);
        h.sender.finish(40);
        expect(h.calls, isEmpty);
        expect(h.sender.busy, isFalse);
        expect(h.idleCount, 0);
      },
    );

    test('setConfirmed(null) membuat finish tetap mengirim', () async {
      final h = _Harness();
      h.sender.setConfirmed(40);
      h.sender.setConfirmed(null);
      h.sender.finish(40);
      expect(h.calls, [40]);
    });

    test('dispose membatalkan tertunda dan mengabaikan hasil', () async {
      final h = _Harness();
      h.sender.submit(1);
      h.sender.submit(2);
      h.sender.dispose();
      await h.succeed(0);
      expect(h.calls, [1]);
      expect(h.failed, isEmpty);
    });

    test('BR-14: 100 submit tiap 10 ms selama 1 detik: maks 11 panggilan, terakhir nilai terakhir', () async {
      final h = _Harness();
      var seen = 0;
      var lastSendMs = 0;

      // Settles every running request and records when a send started.
      Future<void> sync(int nowMs) async {
        for (var i = 0; i < h.completers.length; i++) {
          if (!h.completers[i].isCompleted) await h.succeed(i);
        }
        if (h.calls.length != seen) {
          seen = h.calls.length;
          lastSendMs = nowMs;
        }
      }

      // Virtual clock: step n runs at n * 10 ms. Submits happen at 0..990 ms;
      // step 100 (1000 ms) only lets the throttle timer fire.
      for (var n = 0; n <= 100; n++) {
        final nowMs = n * 10;
        if (h.scheduler.hasLiveOnce(RMotion.sendThrottle) &&
            nowMs >= lastSendMs + RMotion.sendThrottle.inMilliseconds) {
          h.scheduler.fireOnce(RMotion.sendThrottle);
        }
        await sync(nowMs);
        if (n < 100) h.sender.submit(n + 1);
        await sync(nowMs);
      }

      expect(h.calls.length, lessThanOrEqualTo(11));
      expect(h.calls.last, 100, reason: 'nilai terakhir harus terkirim');
      expect(h.calls, [1, for (var v = 10; v <= 90; v += 10) v, 100]);
      expect(h.failed, isEmpty);
      expect(h.sender.busy, isFalse);
    });
  });
}
