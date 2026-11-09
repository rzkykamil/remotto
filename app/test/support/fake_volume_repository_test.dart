import 'package:flutter_test/flutter_test.dart';
import 'package:remotto/core/network/agent_status.dart';
import 'package:remotto/core/network/api_failure.dart';

import 'fake_volume_repository.dart';

void main() {
  test(
    'balasan 200 mengubah state dan dikembalikan sebagai VolumeStatus',
    () async {
      final repo = FakeVolumeRepository(script: [fakeVolumeData(60, true)]);

      final status = await repo.setLevel(60);

      expect(status, const VolumeStatus(level: 60, muted: true));
      expect(repo.current, const VolumeStatus(level: 60, muted: true));
    },
  );

  test('401 melempar UnauthorizedFailure dengan code', () async {
    final repo = FakeVolumeRepository(
      script: [fakeVolumeError(401, 'invalid_token')],
    );

    await expectLater(
      repo.up(),
      throwsA(
        isA<UnauthorizedFailure>().having(
          (f) => f.code,
          'code',
          'invalid_token',
        ),
      ),
    );
    expect(repo.current.level, 35, reason: 'gagal tidak mengubah state');
  });

  test('500 audio_failed melempar ServerFailure dengan code', () async {
    final repo = FakeVolumeRepository(
      script: [fakeVolumeError(500, 'audio_failed')],
    );

    await expectLater(
      repo.down(),
      throwsA(
        isA<ServerFailure>().having((f) => f.code, 'code', 'audio_failed'),
      ),
    );
  });

  test('timeout melempar TimeoutFailure dan state tidak berubah', () async {
    final repo = FakeVolumeRepository(script: const [FakeVolumeTimeout()]);

    await expectLater(repo.setMuted(true), throwsA(isA<TimeoutFailure>()));
    expect(repo.current, const VolumeStatus(level: 35, muted: false));
  });

  test('level 101 dan -1 ditolak tanpa clamp (BR-3)', () async {
    final repo = FakeVolumeRepository();

    await expectLater(
      repo.setLevel(101),
      throwsA(
        isA<ServerFailure>().having((f) => f.code, 'code', 'invalid_level'),
      ),
    );
    await expectLater(
      repo.setLevel(-1),
      throwsA(
        isA<ServerFailure>().having((f) => f.code, 'code', 'invalid_level'),
      ),
    );
    expect(repo.current.level, 35);
  });

  test('setLevel mematikan mute (BR-15)', () async {
    final repo = FakeVolumeRepository(initialMuted: true);

    final status = await repo.setLevel(50);

    expect(status, const VolumeStatus(level: 50, muted: false));
  });

  test('up dan down naik/turun 5 dan mematikan mute (BR-16)', () async {
    final repo = FakeVolumeRepository(initialMuted: true);

    expect(await repo.up(), const VolumeStatus(level: 40, muted: false));
    expect(await repo.down(), const VolumeStatus(level: 35, muted: false));
    expect(await repo.down(), const VolumeStatus(level: 30, muted: false));
  });

  test('up di 100 tetap 100 dan down di 0 tetap 0 (BR-16)', () async {
    final top = FakeVolumeRepository(initialLevel: 100);
    expect((await top.up()).level, 100);

    final bottom = FakeVolumeRepository(initialLevel: 0);
    expect((await bottom.down()).level, 0);
  });

  test(
    'setMuted dua kali berturut-turut tetap pada nilai yang diminta',
    () async {
      final repo = FakeVolumeRepository();

      await repo.setMuted(true);
      final status = await repo.setMuted(true);

      expect(status.muted, isTrue);
      expect(repo.setMutedCalls, 2);
      expect(repo.lastMuted, isTrue);
    },
  );

  test('setMuted hanya mengubah muted, level tetap', () async {
    final repo = FakeVolumeRepository();

    final status = await repo.setMuted(true);

    expect(status, const VolumeStatus(level: 35, muted: true));
  });

  test('langkah terakhir diulang dan setiap metode dihitung', () async {
    final repo = FakeVolumeRepository(
      script: [const FakeVolumeOk(), fakeVolumeError(500, 'audio_failed')],
    );

    await repo.up();
    await expectLater(repo.up(), throwsA(isA<ServerFailure>()));
    await expectLater(repo.up(), throwsA(isA<ServerFailure>()));

    expect(repo.upCalls, 3);
    expect(repo.current.level, 40);
  });
}
