import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotto/core/connection/connection_controller.dart';
import 'package:remotto/core/connection/connection_providers.dart';
import 'package:remotto/core/connection/connection_state.dart';
import 'package:remotto/core/storage/pairing_data.dart';
import 'package:remotto/core/storage/storage_providers.dart';
import 'package:remotto/core/theme/r_behavior.dart';
import 'package:remotto/core/theme/tokens.g.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_agent_server.dart';

/// Tes integrasi resume (FR-6.6, BR-21): `ConnectionController` asli, scheduler
/// `TimerPollScheduler` asli, `HttpStatusRepository` asli ke server loopback.
/// Tidak ada scheduler palsu; waktu nyata dipakai, tapi tidak ada tes yang
/// menunggu hasil dengan sleep. Hasil ditunggu lewat `pollOnce()`, yang
/// mengembalikan poll yang sedang berjalan.
void main() {
  late FakeAgentServer server;
  late ProviderContainer container;

  Future<void> startContainer() async {
    server = await FakeAgentServer.start();
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    container = ProviderContainer(
      overrides: [
        // Dibaca saat offline (lastPowerCommand), jadi harus dioverride.
        sharedPreferencesProvider.overrideWithValue(prefs),
        initialPairingProvider.overrideWithValue(
          PairingData(
            host: '127.0.0.1',
            port: server.port,
            token: fakeAgentToken,
            laptopName: 'Laptop-Kamil',
          ),
        ),
        pollSchedulerProvider.overrideWithValue(const TimerPollScheduler()),
      ],
    );
  }

  ConnectionController ctrl() =>
      container.read(connectionControllerProvider.notifier);

  ConnectionState state() => container.read(connectionControllerProvider);

  /// Mulai polling dan tunggu poll pertama selesai.
  Future<void> start() async {
    ctrl().start();
    await ctrl().pollOnce();
  }

  /// Jendela diam nyata untuk membuktikan "tidak ada request". Bukan untuk
  /// menunggu hasil; hasil selalu ditunggu lewat `pollOnce()`.
  Future<void> quietWindow(Duration window) {
    final done = Completer<void>();
    Timer(window, done.complete);
    return done.future;
  }

  tearDown(() async {
    container.dispose();
    await server.close();
  });

  test('resume kembali online dalam resumeWait, lewat connecting', () async {
    await startContainer();
    await start();
    expect(state().phase, ConnectionPhase.online);

    ctrl().pause();
    final before = server.requests;
    await quietWindow(const Duration(milliseconds: 600));
    expect(server.requests, before, reason: 'pause tidak boleh polling');
    expect(
      state().phase,
      ConnectionPhase.online,
      reason: 'pause tidak ubah fase',
    );

    final phases = <ConnectionPhase>[];
    container.listen(
      connectionControllerProvider,
      (_, next) => phases.add(next.phase),
    );

    final watch = Stopwatch()..start();
    ctrl().resume();
    await ctrl().pollOnce();
    watch.stop();

    expect(state().phase, ConnectionPhase.online);
    expect(state().status?.name, 'Laptop-Kamil');
    expect(watch.elapsed, lessThan(RBehavior.resumeWait));
    expect(phases, [ConnectionPhase.connecting, ConnectionPhase.online]);
  });

  test(
    'poll resume yang melewati resumeWait gagal, tetap connecting',
    () async {
      await startContainer();
      await start();
      expect(state().phase, ConnectionPhase.online);

      ctrl().pause();
      server.hold = Completer<void>();

      final watch = Stopwatch()..start();
      ctrl().resume();
      // Menunggu poll resume selesai: hanya timeout 2 detik yang menyelesaikannya.
      await ctrl().pollOnce();
      watch.stop();

      expect(watch.elapsed, greaterThanOrEqualTo(RBehavior.resumeWait));
      expect(
        state().phase,
        ConnectionPhase.connecting,
        reason: 'satu kegagalan belum offline',
      );

      // Lepas hold; poll berikutnya harus sukses dan membawa ke online.
      server.hold!.complete();
      await ctrl().pollOnce();

      expect(state().phase, ConnectionPhase.online);
      expect(state().status?.name, 'Laptop-Kamil');
    },
  );

  test('server mati saat pause: dua kegagalan cepat jadi offline', () async {
    await startContainer();
    await start();
    expect(state().phase, ConnectionPhase.online);

    ctrl().pause();
    await server.close();

    ctrl().resume();
    await ctrl().pollOnce();
    expect(
      state().phase,
      ConnectionPhase.connecting,
      reason: 'kegagalan pertama belum offline',
    );

    await ctrl().pollOnce();
    expect(state().phase, ConnectionPhase.offline);
  });

  test(
    'token berubah saat resume: tokenRejected cepat, tanpa request lanjutan',
    () async {
      await startContainer();
      await start();
      expect(state().phase, ConnectionPhase.online);

      ctrl().pause();
      server.token = 'b' * 64;

      final watch = Stopwatch()..start();
      ctrl().resume();
      await ctrl().pollOnce();
      watch.stop();

      expect(state().phase, ConnectionPhase.tokenRejected);
      expect(watch.elapsed, lessThan(RBehavior.resumeWait));

      final before = server.requests;
      await ctrl().pollOnce();
      await quietWindow(const Duration(milliseconds: 600));
      expect(server.requests, before, reason: 'tidak ada request setelah 401');
      expect(state().phase, ConnectionPhase.tokenRejected);
    },
  );

  group('429 dan timeout pada poll', () {
    test(
      'rateLimited dua poll berturut-turut jadi offline, tanpa retry',
      () async {
        await startContainer();
        await start();
        expect(state().phase, ConnectionPhase.online);

        server.mode = FakeAgentMode.rateLimited;
        final before = server.requests;

        await ctrl().pollOnce();
        expect(
          state().phase,
          ConnectionPhase.online,
          reason: 'kegagalan pertama belum offline',
        );

        await ctrl().pollOnce();
        expect(state().phase, ConnectionPhase.offline);
        expect(server.requests - before, 2, reason: 'satu request per poll');

        await quietWindow(const Duration(milliseconds: 600));
        expect(
          server.requests - before,
          2,
          reason: 'tidak ada request di luar jadwal',
        );
      },
    );

    test(
      '429 sekali lalu sukses tetap online, dan kegagalan direset',
      () async {
        await startContainer();
        await start();
        expect(state().phase, ConnectionPhase.online);
        final before = server.requests;

        server.mode = FakeAgentMode.rateLimited;
        await ctrl().pollOnce();
        expect(state().phase, ConnectionPhase.online);

        server.mode = FakeAgentMode.ok;
        await ctrl().pollOnce();
        expect(state().phase, ConnectionPhase.online);
        expect(state().status?.name, 'Laptop-Kamil');

        // Setelah sukses, hitungan kembali nol: satu 429 lagi belum offline.
        server.mode = FakeAgentMode.rateLimited;
        await ctrl().pollOnce();
        expect(
          state().phase,
          ConnectionPhase.online,
          reason: 'kegagalan sebelumnya sudah direset',
        );
        expect(server.requests - before, 3, reason: 'satu request per poll');
      },
    );

    test('timeout reguler dihitung sebagai kegagalan', () async {
      await startContainer();
      await start();
      expect(state().phase, ConnectionPhase.online);
      final before = server.requests;

      server.hold = Completer<void>();
      final watch = Stopwatch()..start();
      await ctrl().pollOnce();
      watch.stop();

      expect(watch.elapsed, greaterThanOrEqualTo(RMotion.commandTimeout));
      expect(
        state().phase,
        ConnectionPhase.online,
        reason: 'satu timeout belum offline',
      );

      // Lepas hold, lalu kegagalan kedua (429) harus membawa ke offline.
      server.hold!.complete();
      server.hold = null;
      server.mode = FakeAgentMode.rateLimited;
      await ctrl().pollOnce();

      expect(state().phase, ConnectionPhase.offline);
      expect(server.requests - before, 2, reason: 'satu request per poll');
    });
  });
}
