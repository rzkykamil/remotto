import 'package:flutter_test/flutter_test.dart';
import 'package:remotto/core/network/api_failure.dart';

import 'fake_pairing_repository.dart';

import 'package:remotto/features/pairing/domain/pairing_target.dart';

PairingTarget _target({String host = '192.168.1.20', String? token}) {
  return PairingTarget(
    host: host,
    port: AgentDefaults.port,
    token: token ?? 'a' * 64,
  );
}

void main() {
  const repo = FakePairingRepository(delay: Duration.zero);

  test('pairing sukses mengembalikan nama laptop dari respons', () async {
    final status = await repo.testConnection(_target());

    expect(status.name, fakePairingLaptopName);
    expect(status.name, 'Laptop-Kamil');
  });

  test('host 10.0.0.1 selalu timeout', () async {
    await expectLater(
      repo.testConnection(_target(host: fakePairingTimeoutHost)),
      throwsA(isA<TimeoutFailure>()),
    );
  });

  test('token 64 nol ditolak dengan UnauthorizedFailure', () async {
    await expectLater(
      repo.testConnection(_target(token: fakePairingRejectedToken)),
      throwsA(isA<UnauthorizedFailure>()),
    );
  });
}
