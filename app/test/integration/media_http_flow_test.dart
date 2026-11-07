import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotto/core/connection/connection_providers.dart';
import 'package:remotto/core/connection/connection_state.dart';
import 'package:remotto/core/haptics/r_haptics.dart';
import 'package:remotto/core/storage/pairing_data.dart';
import 'package:remotto/core/storage/storage_providers.dart';
import 'package:remotto/core/strings/remote_strings.dart';
import 'package:remotto/core/toast/toast_controller.dart';
import 'package:remotto/features/remote/data/http_media_repository.dart';
import 'package:remotto/features/remote/state/media_controller.dart';
import 'package:remotto/features/remote/state/media_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_poll_scheduler.dart';
import '../support/fakes.dart';
import 'fake_agent_server.dart';

/// Integration test: the media dock goes through the real default
/// `mediaRepositoryProvider` (HttpMediaRepository -> AgentHttpClient -> IOClient)
/// to a loopback fake agent. Only polling and haptics are fakes. Nothing
/// overrides the repository or the HTTP client, and no real agent or media key
/// is touched.
void main() {
  late FakeAgentServer server;
  late FakePollScheduler scheduler;
  late RecordingHapticSink sink;
  ProviderContainer? container;

  const playPath = '/api/v1/media/play-pause';
  const nextPath = '/api/v1/media/next';
  const prevPath = '/api/v1/media/prev';

  late SharedPreferences prefs;

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
        pollSchedulerProvider.overrideWithValue(scheduler),
        hapticSinkProvider.overrideWithValue(sink),
      ],
    );
  }

  ProviderContainer c() => container!;

  MediaController ctrl() => c().read(mediaControllerProvider.notifier);

  MediaState media() => c().read(mediaControllerProvider);

  ToastMessage? toast() => c().read(toastControllerProvider);

  ConnectionPhase phase() => c().read(connectionControllerProvider).phase;

  /// Polls [done] until it is true. Fails after 5 seconds.
  Future<void> waitUntil(bool Function() done, String what) async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (!done()) {
      if (DateTime.now().isAfter(deadline)) fail('timeout waiting for $what');
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  /// Waits until the server has replied to [count] requests and no handler is
  /// still running, then gives the client a moment to read the reply. Used for
  /// prev/next, which have no state change on success.
  Future<void> untilReplied(int count) async {
    await server.untilRequests(count);
    await waitUntil(() => server.inFlight == 0, 'server reply');
    await Future<void>.delayed(const Duration(milliseconds: 50));
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

  test('default provider adalah HttpMediaRepository (tanpa override)', () {
    boot();

    expect(c().read(mediaRepositoryProvider), isA<HttpMediaRepository>());
  });

  test(
    'play sukses: satu request ke play-pause, ikon berubah, tanpa toast',
    () async {
      boot();

      ctrl().togglePlay();
      await waitUntil(() => !media().playProcessing, 'play reply');

      expect(server.requests, 1);
      expect(server.mediaPaths, [playPath]);
      expect(media().playing, isFalse);
      expect(toast(), isNull);
      expect(sink.calls, isEmpty);
    },
  );

  test(
    'prev dan next: masing-masing satu request ke path yang benar',
    () async {
      boot();

      ctrl().prev();
      await untilReplied(1);
      ctrl().next();
      await untilReplied(2);

      expect(server.requests, 2);
      expect(server.mediaPaths, [prevPath, nextPath]);
      expect(media().blinkPrev, 1);
      expect(media().blinkNext, 1);
      expect(toast(), isNull);
    },
  );

  test(
    'token diganti: 401 masuk tokenRejected, tanpa toast, play di-rollback',
    () async {
      boot();
      server.token = 'b' * 64;

      ctrl().togglePlay();
      await waitUntil(() => phase() == ConnectionPhase.tokenRejected, 'token');

      expect(server.requests, 1);
      expect(server.mediaPaths, [playPath]);
      expect(media().playing, isTrue);
      expect(media().playProcessing, isFalse);
      expect(toast(), isNull);
    },
  );

  test(
    'mode 500 media_failed: rollback, toast gagal, tanpa retry otomatis',
    () async {
      boot();
      server.mode = FakeAgentMode.mediaFailed;

      ctrl().togglePlay();
      await waitUntil(() => toast() != null, 'failure toast');

      expect(server.requests, 1);
      expect(media().playing, isTrue);
      expect(media().playProcessing, isFalse);
      expect(toast()?.text, RemoteStrings.toastCommandFailed);
      expect(toast()?.actionLabel, RemoteStrings.toastRetry);
      expect(toast()?.variant, ToastVariant.error);
      expect(sink.calls, ['vibrate']);
    },
  );

  test('mode 403 forbidden: rollback, toast gagal, satu request', () async {
    boot();
    server.mode = FakeAgentMode.forbidden;

    ctrl().togglePlay();
    await waitUntil(() => toast() != null, 'failure toast');

    expect(server.requests, 1);
    expect(media().playing, isTrue);
    expect(toast()?.text, RemoteStrings.toastCommandFailed);
  });

  test('mode 429 rate limited: rollback, toast gagal, satu request', () async {
    boot();
    server.mode = FakeAgentMode.rateLimited;

    ctrl().togglePlay();
    await waitUntil(() => toast() != null, 'failure toast');

    expect(server.requests, 1);
    expect(media().playing, isTrue);
    expect(toast()?.text, RemoteStrings.toastCommandFailed);
  });

  test('server ditutup: connection refused menjadi toast gagal', () async {
    boot();
    await server.close();

    ctrl().togglePlay();
    await waitUntil(() => toast() != null, 'failure toast');

    expect(server.requests, 0);
    expect(media().playing, isTrue);
    expect(toast()?.text, RemoteStrings.toastCommandFailed);
  });

  test(
    'server tidak membalas: setelah 3 detik rollback dan toast gagal',
    () async {
      boot();
      server.hold = Completer<void>();

      ctrl().togglePlay();
      await server.untilRequests(1);
      expect(media().playProcessing, isTrue);
      expect(toast(), isNull);

      await waitUntil(() => toast() != null, 'timeout toast');

      expect(server.requests, 1);
      expect(media().playing, isTrue);
      expect(media().playProcessing, isFalse);
      expect(toast()?.text, RemoteStrings.toastCommandFailed);
      expect(sink.calls, ['vibrate']);
    },
  );

  test('dua tap play cepat saat request jalan: tetap satu request', () async {
    boot();
    server.hold = Completer<void>();

    ctrl()
      ..togglePlay()
      ..togglePlay();
    await server.untilRequests(1);
    expect(server.requests, 1);

    server.hold!.complete();
    await waitUntil(() => !media().playProcessing, 'play reply');

    expect(server.requests, 1);
    expect(server.maxInFlight, 1);
    expect(media().playing, isFalse);
    expect(toast(), isNull);
  });

  test(
    '"Ulangi" setelah gagal mengirim request kedua (retry manual)',
    () async {
      boot();
      server.mode = FakeAgentMode.mediaFailed;

      ctrl().togglePlay();
      await waitUntil(() => toast() != null, 'failure toast');
      expect(server.requests, 1);

      server.mode = FakeAgentMode.ok;
      toast()!.onAction!();
      await waitUntil(() => !media().playProcessing, 'retry reply');

      expect(server.requests, 2);
      expect(server.mediaPaths, [playPath, playPath]);
      expect(media().playing, isFalse);
      expect(toast(), isNull);
    },
  );

  test('tanpa pairing: toast gagal dan tidak ada request ke server', () async {
    boot(paired: false);

    ctrl().togglePlay();
    await waitUntil(() => toast() != null, 'failure toast');

    expect(server.requests, 0);
    expect(media().playing, isTrue);
    expect(media().playProcessing, isFalse);
    expect(toast()?.text, RemoteStrings.toastCommandFailed);
    expect(sink.calls, ['vibrate']);
  });
}
