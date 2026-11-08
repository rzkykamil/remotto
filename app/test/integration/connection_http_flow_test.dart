import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotto/core/connection/connection_controller.dart';
import 'package:remotto/core/connection/connection_providers.dart';
import 'package:remotto/core/connection/connection_state.dart';
import 'package:remotto/core/storage/pairing_data.dart';
import 'package:remotto/core/storage/storage_providers.dart';
import 'package:remotto/core/theme/r_behavior.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_poll_scheduler.dart';
import 'fake_agent_server.dart';

/// Tes integrasi: `ConnectionController` memakai `HttpStatusRepository` asli
/// yang bicara ke server loopback. Hanya scheduler yang palsu.
void main() {
  late FakeAgentServer server;
  late FakePollScheduler sched;
  late ProviderContainer container;

  Future<void> startContainer() async {
    server = await FakeAgentServer.start();
    sched = FakePollScheduler();
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    container = ProviderContainer(
      overrides: [
        // Read when offline (lastPowerCommand), so it must be overridden.
        sharedPreferencesProvider.overrideWithValue(prefs),
        initialPairingProvider.overrideWithValue(
          PairingData(
            host: '127.0.0.1',
            port: server.port,
            token: fakeAgentToken,
            laptopName: 'Laptop-Kamil',
          ),
        ),
        pollSchedulerProvider.overrideWithValue(sched),
      ],
    );
  }

  ConnectionController ctrl() =>
      container.read(connectionControllerProvider.notifier);

  ConnectionState state() => container.read(connectionControllerProvider);

  /// Memulai polling dan menunggu poll pertama selesai. [ConnectionController.pollOnce]
  /// mengembalikan poll yang sedang berjalan, jadi tidak ada request ganda.
  Future<void> start() async {
    ctrl().start();
    await ctrl().pollOnce();
  }

  /// Memicu satu poll periodik dan menunggu hasilnya.
  Future<void> tick() async {
    sched.tick();
    await ctrl().pollOnce();
  }

  tearDown(() async {
    container.dispose();
    await server.close();
  });

  test('server sehat: connecting lalu online dengan nama dan uptime', () async {
    await startContainer();
    expect(state().phase, ConnectionPhase.connecting);

    await start();

    expect(state().phase, ConnectionPhase.online);
    expect(state().status?.name, 'Laptop-Kamil');
    expect(state().status?.uptimeSeconds, 120);
    expect(server.requests, 1);
  });

  test('dua kegagalan berturut ke offline, lalu pulih ke back', () async {
    await startContainer();
    await start();
    expect(state().phase, ConnectionPhase.online);

    // Agent mati: satu kegagalan tetap online (BR-8), dua kegagalan offline.
    await server.close();
    await tick();
    expect(state().phase, ConnectionPhase.online);

    await tick();
    expect(state().phase, ConnectionPhase.offline);

    // Agent hidup lagi di port yang sama.
    server = await server.restart();
    await tick();
    expect(state().phase, ConnectionPhase.back);
    expect(state().status?.name, 'Laptop-Kamil');

    sched.fireOnce(RBehavior.reconnectedPill);
    expect(state().phase, ConnectionPhase.online);
  });

  test('401 menghentikan polling dan masuk tokenRejected', () async {
    await startContainer();
    await start();
    expect(state().phase, ConnectionPhase.online);

    // Token di laptop berubah (mis. reset-token): app masih memakai token lama.
    server.token = 'b' * 64;
    await tick();

    expect(state().phase, ConnectionPhase.tokenRejected);
    expect(sched.periodicJob, isNull, reason: 'polling harus berhenti');

    final before = server.requests;
    sched.tick();
    await ctrl().pollOnce();
    expect(server.requests, before, reason: 'tidak ada request setelah 401');
  });

  test('maksimum satu request in-flight walau tick berulang', () async {
    await startContainer();
    server.hold = Completer<void>();

    ctrl().start();
    await server.untilRequests(1);

    // Dua tick lagi saat poll pertama masih menunggu balasan.
    sched.tick();
    sched.tick();
    expect(server.requests, 1);

    server.hold!.complete();
    await ctrl().pollOnce();

    expect(state().phase, ConnectionPhase.online);
    expect(server.requests, 1);
    expect(server.maxInFlight, 1);
  });
}
