import 'package:flutter_test/flutter_test.dart';
import 'package:remotto/core/connection/mock_status_repository.dart';
import 'package:remotto/core/network/api_failure.dart';

void main() {
  test('langkah dipakai berurutan lalu langkah terakhir diulang', () async {
    final repo = MockStatusRepository([
      mockStatusOk(name: 'Satu'),
      mockStatusOk(name: 'Dua'),
    ]);

    expect((await repo.fetchStatus()).name, 'Satu');
    expect((await repo.fetchStatus()).name, 'Dua');
    expect((await repo.fetchStatus()).name, 'Dua');
    expect(repo.calls, 3);
  });

  test('balasan 401 melempar UnauthorizedFailure', () async {
    final repo = MockStatusRepository([mockErrorReply(401, 'invalid_token')]);

    await expectLater(repo.fetchStatus(), throwsA(isA<UnauthorizedFailure>()));
  });

  test('volume null tetap sukses dan volume bernilai null', () async {
    final repo = MockStatusRepository([mockStatusOk(volumeUnavailable: true)]);

    final status = await repo.fetchStatus();

    expect(status.volume, isNull);
  });

  test('timeout tanpa respons melempar TimeoutFailure', () async {
    final repo = MockStatusRepository([
      const MockTransportFailure(TimeoutFailure()),
    ]);

    await expectLater(repo.fetchStatus(), throwsA(isA<TimeoutFailure>()));
  });

  test('agent tidak terjangkau melempar UnreachableFailure', () async {
    final repo = MockStatusRepository([
      const MockTransportFailure(UnreachableFailure()),
    ]);

    await expectLater(repo.fetchStatus(), throwsA(isA<UnreachableFailure>()));
  });
}
