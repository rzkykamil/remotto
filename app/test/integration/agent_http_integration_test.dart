import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/io_client.dart';
import 'package:remotto/core/network/agent_http_client.dart';
import 'package:remotto/core/network/agent_status.dart';
import 'package:remotto/core/network/api_failure.dart';

import 'fake_agent_server.dart';

/// Tes integrasi: `AgentHttpClient` dengan `IOClient` asli ke server loopback.
void main() {
  late FakeAgentServer server;
  late IOClient io;
  late AgentHttpClient client;

  setUp(() async {
    server = await FakeAgentServer.start();
    io = IOClient();
    client = AgentHttpClient(io);
  });

  tearDown(() async {
    io.close();
    await server.close();
  });

  Future<AgentStatus> fetch({
    String? token,
    Duration timeout = const Duration(seconds: 3),
    int? port,
  }) {
    return client.getStatus(
      host: '127.0.0.1',
      port: port ?? server.port,
      token: token ?? fakeAgentToken,
      timeout: timeout,
    );
  }

  test('token benar mengembalikan AgentStatus terisi', () async {
    final status = await fetch();

    expect(status.name, 'Laptop-Kamil');
    expect(status.version, '1.0.0');
    expect(status.uptimeSeconds, 120);
    expect(status.volume, const VolumeStatus(level: 35, muted: false));
    expect(status.pending, isNull);
    expect(server.requests, 1);
  });

  test('volume null dari agent tetap sukses dengan volume null', () async {
    server.volumeAvailable = false;

    final status = await fetch();

    expect(status.volume, isNull);
    expect(status.name, 'Laptop-Kamil');
  });

  test('token salah menghasilkan UnauthorizedFailure', () async {
    await expectLater(
      fetch(token: 'b' * 64),
      throwsA(
        isA<UnauthorizedFailure>().having(
          (f) => f.code,
          'code',
          'invalid_token',
        ),
      ),
    );
  });

  test('mode 403 menghasilkan ForbiddenFailure', () async {
    server.mode = FakeAgentMode.forbidden;

    await expectLater(
      fetch(),
      throwsA(
        isA<ForbiddenFailure>().having(
          (f) => f.code,
          'code',
          'forbidden_network',
        ),
      ),
    );
  });

  test(
    'mode 429 menghasilkan RateLimitedFailure dengan Retry-After 2 detik',
    () async {
      server.mode = FakeAgentMode.rateLimited;

      await expectLater(
        fetch(),
        throwsA(
          isA<RateLimitedFailure>().having(
            (f) => f.retryAfter,
            'retryAfter',
            const Duration(seconds: 2),
          ),
        ),
      );
    },
  );

  test('mode 500 menghasilkan ServerFailure', () async {
    server.mode = FakeAgentMode.serverError;

    await expectLater(
      fetch(),
      throwsA(isA<ServerFailure>().having((f) => f.code, 'code', 'internal')),
    );
  });

  test('body bukan JSON pada 200 menghasilkan ServerFailure', () async {
    server.mode = FakeAgentMode.badBody;

    await expectLater(fetch(), throwsA(isA<ServerFailure>()));
  });

  test('path lain mengembalikan 404 dan tidak lolos sebagai status', () async {
    // Path tidak dikenal tidak dipakai client; dicek langsung lewat HttpClient
    // untuk memastikan server palsu membalas 404 seperti agent.
    final response = await io.get(
      Uri.http('127.0.0.1:${server.port}', '/api/v1/tidak-ada'),
      headers: {'Authorization': 'Bearer $fakeAgentToken'},
    );
    expect(response.statusCode, 404);
  });

  test('handler lebih lama dari timeout menghasilkan TimeoutFailure', () async {
    server.hold = Completer<void>();

    await expectLater(
      fetch(timeout: const Duration(milliseconds: 200)),
      throwsA(isA<TimeoutFailure>()),
    );
  });

  test('port yang ditutup menghasilkan UnreachableFailure', () async {
    final closed = await FakeAgentServer.start();
    final port = closed.port;
    await closed.close();

    await expectLater(fetch(port: port), throwsA(isA<UnreachableFailure>()));
  });
}
