import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotto/core/connection/connection_providers.dart';
import 'package:remotto/core/connection/connection_state.dart';
import 'package:remotto/core/connection/connection_controller.dart';
import 'package:remotto/core/haptics/r_haptics.dart';
import 'package:remotto/core/network/api_failure.dart';
import 'package:remotto/core/storage/pairing_data.dart';
import 'package:remotto/core/storage/storage_providers.dart';
import 'package:remotto/core/strings/remote_strings.dart';
import 'package:remotto/core/toast/toast_controller.dart';
import 'package:remotto/features/remote/data/http_volume_repository.dart';
import 'package:remotto/features/remote/state/volume_controller.dart';
import 'package:remotto/features/remote/state/volume_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_poll_scheduler.dart';
import '../support/fakes.dart';
import 'fake_agent_server.dart';

/// Integration test: the volume panel goes through the real default
/// `volumeRepositoryProvider` (HttpVolumeRepository -> AgentHttpClient ->
/// IOClient) to a loopback fake agent. Only polling, haptics and the
/// connection storage are fakes. Nothing overrides the repository or the HTTP
/// client, and no real laptop volume is touched.
void main() {
  late FakeAgentServer server;
  late FakePollScheduler scheduler;
  late RecordingHapticSink sink;
  ProviderContainer? container;
  late SharedPreferences prefs;

  const volumePath = '/api/v1/volume';
  const upPath = '/api/v1/volume/up';
  const downPath = '/api/v1/volume/down';
  const mutePath = '/api/v1/volume/mute';

  ProviderContainer c() => container!;

  void boot({bool paired = true}) {
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        initialPairingProvider.overrideWithValue(
          paired
              ? PairingData(
                  host: '127.0.0.1',
                  port: server.port,
                  token: fakeAgentToken,
                  laptopName: 'Laptop-Kamil',
                )
              : null,
        ),
        connectionStorageProvider.overrideWithValue(
          InMemoryConnectionStorage(),
        ),
        pollSchedulerProvider.overrideWithValue(scheduler),
        hapticSinkProvider.overrideWithValue(sink),
      ],
    );
    // Reading the controller starts its listener on the connection status.
    c().read(volumeControllerProvider);
  }

  VolumeController vctrl() => c().read(volumeControllerProvider.notifier);

  VolumeState vol() => c().read(volumeControllerProvider);

  ToastMessage? toast() => c().read(toastControllerProvider);

  ConnectionPhase phase() => c().read(connectionControllerProvider).phase;

  ConnectionController conn() =>
      c().read(connectionControllerProvider.notifier);

  /// Polls [done] until it is true. Fails after 5 seconds.
  Future<void> waitUntil(bool Function() done, String what) async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (!done()) {
      if (DateTime.now().isAfter(deadline)) fail('timeout waiting for $what');
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  /// Starts status polling and waits for the first poll, so the volume panel
  /// learns the level 35 from the server.
  Future<void> connect() async {
    conn().start();
    await conn().pollOnce();
  }

  /// Triggers one periodic poll and waits for it to finish.
  Future<void> tick() async {
    scheduler.tick();
    await conn().pollOnce();
  }

  setUp(() async {
    server = await FakeAgentServer.start();
    scheduler = FakePollScheduler();
    sink = RecordingHapticSink();
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  tearDown(() async {
    container?.dispose();
    container = null;
    await server.close();
  });

  test('default provider adalah HttpVolumeRepository (tanpa override)', () {
    boot();

    expect(c().read(volumeRepositoryProvider), isA<HttpVolumeRepository>());
  });

  test('status awal: level 35 dari server dipakai panel', () async {
    boot();
    expect(vol().known, isFalse);

    await connect();

    expect(vol().known, isTrue);
    expect(vol().level, 35);
    expect(vol().muted, isFalse);
    expect(server.volumeRequests, isEmpty);
  });

  test(
    'slider drag/tap ke 60: satu PUT {"level":60}, confirmed 60, tanpa toast',
    () async {
      boot();
      await connect();
      final before = server.requests;

      vctrl()
        ..dragStart(60)
        ..dragEnd(60);
      await waitUntil(() => vol().confirmed?.level == 60, 'level 60 reply');

      expect(server.requests - before, 1);
      expect(server.volumeRequests.single.method, 'PUT');
      expect(server.volumeRequests.single.path, volumePath);
      expect(server.volumeRequests.single.body, '{"level":60}');
      expect(server.volumeLevel, 60);
      expect(server.maxInFlight, 1);
      expect(vol().level, 60);
      expect(toast(), isNull);
      expect(sink.calls, isEmpty);
    },
  );

  test(
    'PUT gagal 500 sekali: tanpa retry, satu PUT, toast gagal, rollback ke 35',
    () async {
      boot();
      await connect();
      server.failNextVolumeRequests = 1;

      vctrl()
        ..dragStart(60)
        ..dragEnd(60);
      await waitUntil(() => toast() != null, 'failure toast');

      expect(server.volumeRequests.length, 1, reason: '500 tidak di-retry');
      expect(server.volumeRequests.single.method, 'PUT');
      expect(vol().level, 35);
      expect(vol().confirmed?.level, 35);
      expect(toast()?.text, RemoteStrings.toastVolumeFailed(35));
    },
  );

  test('PUT gagal 500: toast volume gagal, rollback ke 35', () async {
    boot();
    await connect();
    server.failNextVolumeRequests = 2;

    vctrl()
      ..dragStart(60)
      ..dragEnd(60);
    await waitUntil(() => toast() != null, 'failure toast');

    expect(server.volumeRequests.length, 1, reason: '500 tidak di-retry');
    expect(toast()?.text, RemoteStrings.toastVolumeFailed(35));
    expect(toast()?.actionLabel, RemoteStrings.toastRetry);
    expect(vol().level, 35);
    expect(vol().confirmed?.level, 35);
    expect(sink.calls, ['vibrate']);
  });

  test('tombol + sukses: POST up, level 35 jadi 40', () async {
    boot();
    await connect();

    vctrl().up();
    await waitUntil(() => vol().confirmed?.level == 40, 'up reply');

    expect(server.volumeRequests.length, 1);
    expect(server.volumeRequests.single.method, 'POST');
    expect(server.volumeRequests.single.path, upPath);
    expect(server.volumeRequests.single.body, isEmpty);
    expect(vol().level, 40);
    expect(toast(), isNull);
  });

  test('tombol - sukses: POST down, level 35 jadi 30', () async {
    boot();
    await connect();

    vctrl().down();
    await waitUntil(() => vol().confirmed?.level == 30, 'down reply');

    expect(server.volumeRequests.length, 1);
    expect(server.volumeRequests.single.method, 'POST');
    expect(server.volumeRequests.single.path, downPath);
    expect(vol().level, 30);
    expect(toast(), isNull);
  });

  test(
    'up mode audio gagal: satu request, rollback 35, toast gagal, haptic',
    () async {
      boot();
      await connect();
      server.mode = FakeAgentMode.audioFailed;

      vctrl().up();
      await waitUntil(() => toast() != null, 'failure toast');

      expect(server.volumeRequests.length, 1);
      expect(vol().level, 35);
      expect(vol().confirmed?.level, 35);
      expect(toast()?.text, RemoteStrings.toastCommandFailed);
      expect(toast()?.actionLabel, RemoteStrings.toastRetry);
      expect(sink.calls, ['vibrate']);
    },
  );

  test(
    '"Ulangi" setelah up gagal: request kedua manual, sukses ke 40',
    () async {
      boot();
      await connect();
      server.mode = FakeAgentMode.audioFailed;

      vctrl().up();
      await waitUntil(() => toast() != null, 'failure toast');
      expect(server.volumeRequests.length, 1);

      server.mode = FakeAgentMode.ok;
      toast()!.onAction!();
      await waitUntil(() => vol().confirmed?.level == 40, 'retry reply');

      expect(server.volumeRequests.length, 2);
      expect(server.volumeRequests.map((r) => r.path), [upPath, upPath]);
      expect(vol().level, 40);
      expect(toast(), isNull);
    },
  );

  test('mute sukses: satu POST {"muted":true}, panel muted', () async {
    boot();
    await connect();

    await vctrl().toggleMute();

    expect(server.volumeRequests.length, 1);
    expect(server.volumeRequests.single.method, 'POST');
    expect(server.volumeRequests.single.path, mutePath);
    expect(server.volumeRequests.single.body, '{"muted":true}');
    expect(vol().muted, isTrue);
    expect(server.volumeMuted, isTrue);
    expect(toast(), isNull);
  });

  test(
    'mute gagal sekali: retry silent, dua request, tanpa toast, muted',
    () async {
      boot();
      await connect();
      server.failNextVolumeRequests = 1;

      await vctrl().toggleMute();

      expect(server.volumeRequests.length, 2);
      expect(vol().muted, isTrue);
      expect(vol().confirmed?.muted, isTrue);
      expect(toast(), isNull);
      expect(sink.calls, isEmpty);
    },
  );

  test(
    'mute gagal dua kali: dua request, rollback ke tidak muted, toast',
    () async {
      boot();
      await connect();
      server.failNextVolumeRequests = 2;

      await vctrl().toggleMute();

      expect(server.volumeRequests.length, 2);
      expect(vol().muted, isFalse);
      expect(toast()?.text, RemoteStrings.toastCommandFailed);
      expect(sink.calls, ['vibrate']);
    },
  );

  test(
    'setLevel 150 langsung ke repo: 400 invalid_level, satu request',
    () async {
      boot();
      await connect();
      final repo = c().read(volumeRepositoryProvider);

      await expectLater(
        repo.setLevel(150),
        throwsA(
          isA<ServerFailure>().having((f) => f.code, 'code', 'invalid_level'),
        ),
      );

      expect(server.volumeRequests.length, 1);
      expect(server.volumeRequests.single.body, '{"level":150}');
      expect(server.volumeLevel, 35);
    },
  );

  test('429 pada up: satu request, toast gagal', () async {
    boot();
    await connect();
    server.mode = FakeAgentMode.rateLimited;

    vctrl().up();
    await waitUntil(() => toast() != null, 'failure toast');

    expect(server.volumeRequests.length, 1);
    expect(vol().level, 35);
    expect(toast()?.text, RemoteStrings.toastCommandFailed);
    expect(sink.calls, ['vibrate']);
  });

  test('429 pada mute: dua request (retry mute), lalu toast', () async {
    boot();
    await connect();
    server.mode = FakeAgentMode.rateLimited;

    await vctrl().toggleMute();

    expect(server.volumeRequests.length, 2);
    expect(vol().muted, isFalse);
    expect(toast()?.text, RemoteStrings.toastCommandFailed);
  });

  test('401 (token diganti) pada up: tokenRejected, tanpa toast, rollback, satu request', () async {
    boot();
    await connect();
    server.token = 'b' * 64;

    vctrl().up();
    await waitUntil(() => phase() == ConnectionPhase.tokenRejected, 'token');

    expect(server.volumeRequests.length, 1);
    expect(vol().level, 35);
    expect(toast(), isNull);
  });

  test(
    '401 (token diganti) pada slider: tokenRejected, satu PUT, tanpa toast',
    () async {
      boot();
      await connect();
      server.token = 'b' * 64;

      vctrl()
        ..dragStart(60)
        ..dragEnd(60);
      await waitUntil(() => phase() == ConnectionPhase.tokenRejected, 'token');

      expect(server.volumeRequests.length, 1);
      expect(server.volumeRequests.single.method, 'PUT');
      expect(vol().level, 35);
      expect(toast(), isNull);
    },
  );

  test('403 pada up: satu request, toast, rollback', () async {
    boot();
    await connect();
    server.mode = FakeAgentMode.forbidden;

    vctrl().up();
    await waitUntil(() => toast() != null, 'failure toast');

    expect(server.volumeRequests.length, 1);
    expect(vol().level, 35);
    expect(toast()?.text, RemoteStrings.toastCommandFailed);
  });

  test('500 pada up: satu request, toast, rollback', () async {
    boot();
    await connect();
    server.mode = FakeAgentMode.serverError;

    vctrl().up();
    await waitUntil(() => toast() != null, 'failure toast');

    expect(server.volumeRequests.length, 1);
    expect(vol().level, 35);
    expect(toast()?.text, RemoteStrings.toastCommandFailed);
  });

  test('server ditutup saat up: toast gagal dan rollback', () async {
    boot();
    await connect();
    await server.close();

    vctrl().up();
    await waitUntil(() => toast() != null, 'failure toast');

    expect(server.volumeRequests, isEmpty);
    expect(vol().level, 35);
    expect(toast()?.text, RemoteStrings.toastCommandFailed);
  });

  test('server tidak membalas saat up: rollback dan toast setelah timeout, tanpa retry', () async {
    boot();
    await connect();
    server.hold = Completer<void>();

    vctrl().up();
    await server.untilRequests(server.requests + 1);
    expect(toast(), isNull);

    await waitUntil(() => toast() != null, 'timeout toast');

    expect(server.volumeRequests.length, 1);
    expect(vol().level, 35);
    expect(toast()?.text, RemoteStrings.toastCommandFailed);
    expect(sink.calls, ['vibrate']);
  });

  test('tanpa pairing: toast gagal dan tidak ada request ke server', () async {
    boot();
    await connect();
    expect(vol().known, isTrue);
    await c().read(pairingProvider.notifier).clear();
    final before = server.requests;

    vctrl().up();
    await waitUntil(() => toast() != null, 'failure toast');

    expect(server.requests, before);
    expect(server.volumeRequests.length, 0);
    expect(vol().level, 35);
    expect(toast()?.text, RemoteStrings.toastCommandFailed);
  });

  test(
    'status volume null: level tetap 35, lalu level 50 dari server',
    () async {
      boot();
      await connect();
      expect(vol().level, 35);

      server.volumeAvailable = false;
      await tick();

      expect(vol().level, 35);
      expect(vol().known, isTrue);
      expect(toast(), isNull);

      server.volumeAvailable = true;
      server.volumeLevel = 50;
      await tick();

      expect(vol().level, 50);
      expect(vol().confirmed?.level, 50);
      expect(toast(), isNull);
    },
  );
}
