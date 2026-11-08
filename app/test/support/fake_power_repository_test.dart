import 'package:flutter_test/flutter_test.dart';
import 'package:remotto/core/network/agent_status.dart';
import 'package:remotto/core/network/api_failure.dart';
import 'package:remotto/features/remote/data/power_repository.dart';

import 'fake_power_repository.dart';

void main() {
  test('202 mengembalikan Pending dari balasan agent', () async {
    final repo = FakePowerRepository(
      script: [fakePowerScheduled(PowerAction.shutdown)],
    );

    final pending = await repo.schedule(PowerAction.shutdown);

    expect(
      pending,
      const Pending(
        action: 'shutdown',
        remainingMs: 5000,
        delayMs: 5000,
        scheduledAt: '2026-01-01T23:41:00+07:00',
      ),
    );
    expect(repo.pending, pending);
    expect(repo.scheduleCalls, 1);
    expect(repo.lastScheduled, PowerAction.shutdown);
  });

  test(
    '200 cancel mengembalikan aksi yang dibatalkan dan menghapus jadwal',
    () async {
      final repo = FakePowerRepository(
        script: [const FakePowerOk(), fakePowerCancelled(PowerAction.shutdown)],
      );
      await repo.schedule(PowerAction.shutdown);

      final cancelled = await repo.cancel();

      expect(cancelled, PowerAction.shutdown);
      expect(repo.pending, isNull);
      expect(repo.cancelCalls, 1);
    },
  );

  test(
    '409 power_pending dikenali lewat code dan tidak mengubah jadwal',
    () async {
      final repo = FakePowerRepository(
        script: [fakePowerError(409, 'power_pending')],
      );

      await expectLater(
        repo.schedule(PowerAction.restart),
        throwsA(
          isA<ApiFailure>().having((f) => f.code, 'code', 'power_pending'),
        ),
      );
      expect(repo.pending, isNull);
    },
  );

  test('409 no_pending_power dikenali lewat code', () async {
    final repo = FakePowerRepository(
      script: [fakePowerError(409, 'no_pending_power')],
    );

    await expectLater(
      repo.cancel(),
      throwsA(
        isA<ApiFailure>().having((f) => f.code, 'code', 'no_pending_power'),
      ),
    );
  });

  test('409 power_executing dikenali lewat code', () async {
    final repo = FakePowerRepository(
      script: [fakePowerError(409, 'power_executing')],
    );

    await expectLater(
      repo.cancel(),
      throwsA(
        isA<ApiFailure>().having((f) => f.code, 'code', 'power_executing'),
      ),
    );
  });

  test('500 power_failed melempar ServerFailure dengan code', () async {
    final repo = FakePowerRepository(
      script: [fakePowerError(500, 'power_failed')],
    );

    await expectLater(
      repo.schedule(PowerAction.sleep),
      throwsA(
        isA<ServerFailure>().having((f) => f.code, 'code', 'power_failed'),
      ),
    );
    expect(repo.pending, isNull);
  });

  test('timeout melempar TimeoutFailure dan state tidak berubah', () async {
    final repo = FakePowerRepository(script: const [FakePowerTimeout()]);

    await expectLater(
      repo.schedule(PowerAction.sleep),
      throwsA(isA<TimeoutFailure>()),
    );
    expect(repo.pending, isNull);
  });

  test('202 dengan pending null menjadi ServerFailure', () async {
    final repo = FakePowerRepository(
      script: [const FakePowerReply(202, '{"data":{"pending":null}}')],
    );

    await expectLater(
      repo.schedule(PowerAction.sleep),
      throwsA(isA<ServerFailure>()),
    );
  });

  test('200 cancel dengan aksi tidak dikenal menjadi ServerFailure', () async {
    final repo = FakePowerRepository(
      script: [
        const FakePowerReply(
          200,
          '{"data":{"cancelled":"hibernate","pending":null}}',
        ),
      ],
    );

    await expectLater(repo.cancel(), throwsA(isA<ServerFailure>()));
  });

  test('schedule kedua saat jadwal aktif ditolak power_pending', () async {
    final repo = FakePowerRepository();
    await repo.schedule(PowerAction.shutdown);

    await expectLater(
      repo.schedule(PowerAction.restart),
      throwsA(isA<ApiFailure>().having((f) => f.code, 'code', 'power_pending')),
    );
    expect(repo.pending?.action, 'shutdown');
  });

  test('PowerAction.fromWire mengenali tiga aksi dan menolak nilai lain', () {
    expect(PowerAction.fromWire('sleep'), PowerAction.sleep);
    expect(PowerAction.fromWire('restart'), PowerAction.restart);
    expect(PowerAction.fromWire('shutdown'), PowerAction.shutdown);
    expect(PowerAction.fromWire('hibernate'), isNull);
  });
}
