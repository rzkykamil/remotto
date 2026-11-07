import 'package:flutter_test/flutter_test.dart';
import 'package:remotto/core/network/api_failure.dart';
import 'package:remotto/features/remote/data/media_repository.dart';

import 'fake_media_repository.dart';

void main() {
  test('wire value tiap aksi sesuai docs/api-spec.md', () {
    expect(MediaAction.playPause.wire, 'play-pause');
    expect(MediaAction.next.wire, 'next');
    expect(MediaAction.prev.wire, 'prev');
  });

  test('balasan 200 dengan action sama berhasil untuk tiap aksi', () async {
    for (final action in MediaAction.values) {
      final repo = FakeMediaRepository([fakeMediaOk(action)]);

      await expectLater(repo.send(action), completes);
    }
  });

  test('echo menjawab dengan aksi yang diminta', () async {
    final repo = FakeMediaRepository(const [FakeMediaEcho()]);

    for (final action in MediaAction.values) {
      await expectLater(repo.send(action), completes);
    }
    expect(repo.calls, MediaAction.values.length);
  });

  test('401 melempar UnauthorizedFailure dengan code', () async {
    final repo = FakeMediaRepository([fakeMediaError(401, 'invalid_token')]);

    await expectLater(
      repo.send(MediaAction.next),
      throwsA(
        isA<UnauthorizedFailure>().having(
          (f) => f.code,
          'code',
          'invalid_token',
        ),
      ),
    );
  });

  test('500 media_failed melempar ServerFailure dengan code', () async {
    final repo = FakeMediaRepository([fakeMediaError(500, 'media_failed')]);

    await expectLater(
      repo.send(MediaAction.playPause),
      throwsA(
        isA<ServerFailure>().having((f) => f.code, 'code', 'media_failed'),
      ),
    );
  });

  test('timeout melempar TimeoutFailure', () async {
    final repo = FakeMediaRepository(const [FakeMediaTimeout()]);

    await expectLater(
      repo.send(MediaAction.prev),
      throwsA(isA<TimeoutFailure>()),
    );
  });

  test(
    'action balasan tidak sama dengan yang dikirim melempar ServerFailure',
    () async {
      final repo = FakeMediaRepository([fakeMediaOk(MediaAction.next)]);

      await expectLater(
        repo.send(MediaAction.prev),
        throwsA(isA<ServerFailure>()),
      );
    },
  );

  test('langkah dipakai berurutan lalu langkah terakhir diulang', () async {
    final repo = FakeMediaRepository([
      fakeMediaError(500, 'media_failed'),
      fakeMediaOk(MediaAction.next),
    ]);

    await expectLater(
      repo.send(MediaAction.next),
      throwsA(isA<ServerFailure>()),
    );
    await expectLater(repo.send(MediaAction.next), completes);
    await expectLater(
      repo.send(MediaAction.prev),
      throwsA(isA<ServerFailure>()),
    );
    expect(repo.calls, 3);
  });

  test('calls dan lastAction mencatat pemanggilan terakhir', () async {
    final repo = FakeMediaRepository(const [FakeMediaEcho()]);

    expect(repo.calls, 0);
    expect(repo.lastAction, isNull);

    await repo.send(MediaAction.playPause);

    expect(repo.calls, 1);
    expect(repo.lastAction, MediaAction.playPause);
  });
}
