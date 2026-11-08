import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:remotto/core/connection/connection_providers.dart';
import 'package:remotto/core/connection/connection_state.dart';
import 'package:remotto/core/connection/status_repository.dart';
import 'package:remotto/core/haptics/r_haptics.dart';
import 'package:remotto/core/network/api_failure.dart';
import 'package:remotto/core/network/network_providers.dart';
import 'package:remotto/core/storage/pairing_data.dart';
import 'package:remotto/core/storage/storage_providers.dart';
import 'package:remotto/core/strings/remote_strings.dart';
import 'package:remotto/core/theme/app_theme.dart';
import 'package:remotto/core/theme/tokens.g.dart';
import 'package:remotto/features/remote/data/media_repository.dart';

import '../../support/fake_media_repository.dart';
import '../../support/fake_power_repository.dart';

import 'package:remotto/features/remote/power/power_providers.dart';
import 'package:remotto/features/remote/remote_screen.dart';
import 'package:remotto/features/remote/state/media_controller.dart';
import 'package:remotto/features/remote/state/media_providers.dart';
import 'package:remotto/features/remote/widgets/media_dock.dart';
import 'package:remotto/ui/play_key.dart';
import 'package:remotto/ui/r_icon.dart';
import 'package:remotto/ui/r_icons_data.dart';
import 'package:remotto/ui/toast_host.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_poll_scheduler.dart';
import '../../support/fake_status_repository.dart';
import '../../support/fakes.dart';
import '../../support/volume_overrides.dart';

const _pairing = PairingData(
  host: '192.168.1.10',
  port: 8765,
  token: 'test-token',
  laptopName: 'Laptop Uji',
);

const _toastFailed = RemoteStrings.toastCommandFailed;

/// Repository that holds each media reply until the test completes it.
final class _GatedMediaRepository implements MediaRepository {
  final List<MediaAction> sent = [];
  final List<Completer<void>> replies = [];

  @override
  Future<void> send(MediaAction action) {
    sent.add(action);
    final reply = Completer<void>();
    replies.add(reply);
    return reply.future;
  }
}

final class _Harness {
  _Harness(this.container, this.scheduler, this.sink);

  final ProviderContainer container;
  final FakePollScheduler scheduler;
  final RecordingHapticSink sink;

  MediaState get media => container.read(mediaControllerProvider);
  ConnectionPhase get phase =>
      container.read(connectionControllerProvider).phase;
}

/// Runs [body] with the semantics tree on, so finders by label work. The
/// handle is disposed inside the test body, as the framework requires.
void _flowTest(
  String description,
  Future<void> Function(WidgetTester tester) body,
) {
  testWidgets(description, (tester) async {
    final semantics = tester.ensureSemantics();
    await body(tester);
    semantics.dispose();
  });
}

/// Pumps the full Remote screen with the toast host, as in the app shell.
/// Status and media are fakes; polling is driven by the test.
Future<_Harness> _pumpRemote(
  WidgetTester tester, {
  required StatusRepository status,
  required MediaRepository media,
  Size size = const Size(412, 892),
  bool dark = false,
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final scheduler = FakePollScheduler();
  final sink = RecordingHapticSink();

  final overrides = <Override>[
    statusRepositoryProvider.overrideWithValue(status),
    mediaRepositoryProvider.overrideWithValue(media),
    pollSchedulerProvider.overrideWithValue(scheduler),
    volumeOverride(),
    powerRepositoryProvider.overrideWithValue(FakePowerRepository()),
    hapticSinkProvider.overrideWithValue(sink),
    sharedPreferencesProvider.overrideWithValue(prefs),
    initialPairingProvider.overrideWithValue(_pairing),
    connectionStorageProvider.overrideWithValue(
      InMemoryConnectionStorage(_pairing),
    ),
  ];

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: ToastHost(child: child!),
        ),
        home: const Scaffold(body: RemoteScreen()),
      ),
    ),
  );
  await _settle(tester);

  final container = ProviderScope.containerOf(
    tester.element(find.byType(RemoteScreen)),
  );
  return _Harness(container, scheduler, sink);
}

/// Lets queued futures finish and rebuilds the frame.
Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(() => pumpEventQueue());
  await tester.pumpAndSettle();
}

Finder get _play => find.byType(PlayKey);
Finder get _prev => find.bySemanticsLabel(RemoteStrings.prevLabel);
Finder get _next => find.bySemanticsLabel(RemoteStrings.nextLabel);
Finder get _ring => find.byKey(const ValueKey('play-key-ring'));
Finder get _retry => find.text(RemoteStrings.toastRetry);

bool Function(Widget) _iconIs(RIconData data) =>
    (w) => w is RIcon && identical(w.data, data);

/// True when the semantics node with [label] is enabled.
bool _isEnabled(WidgetTester tester, String label) {
  final data = tester
      .getSemantics(find.bySemanticsLabel(label).first)
      .getSemanticsData();
  return data.flagsCollection.isEnabled == Tristate.isTrue;
}

void main() {
  group('S03 play diproses', () {
    _flowTest(
      'ikon langsung berganti, cincin muncul setelah 400 dtk, tap ulang diabaikan, prev/next tetap jalan',
      (tester) async {
        final repo = _GatedMediaRepository();
        final h = await _pumpRemote(
          tester,
          status: FakeStatusRepository([fakeStatusOk()]),
          media: repo,
        );

        expect(find.byWidgetPredicate(_iconIs(RIcons.pause)), findsOneWidget);
        await tester.tap(_play);
        await tester.pump();

        // Optimistic: the icon flips before the laptop answers.
        expect(h.media.playing, isFalse);
        expect(find.byWidgetPredicate(_iconIs(RIcons.play)), findsOneWidget);
        expect(_ring, findsNothing);

        // Ring only after the processing hint delay.
        h.scheduler.fireOnce(RMotion.processingHint);
        await tester.pump();
        expect(_ring, findsOneWidget);

        // A second tap while play is in flight is ignored.
        await tester.tap(_play);
        await tester.pump();
        expect(repo.sent, [MediaAction.playPause]);
        expect(h.media.playing, isFalse);

        // Prev and next still work while play is in flight.
        await tester.tap(_prev);
        await tester.pump();
        expect(repo.sent, [MediaAction.playPause, MediaAction.prev]);
        await tester.tap(_next);
        await tester.pump();
        expect(repo.sent, [
          MediaAction.playPause,
          MediaAction.prev,
          MediaAction.next,
        ]);

        // Laptop answers all three requests: ring gone, icon stays, no toast.
        // The timeout timers of the skip requests must finish too.
        for (final reply in repo.replies) {
          reply.complete();
        }
        await _settle(tester);
        expect(_ring, findsNothing);
        expect(h.media.playing, isFalse);
        expect(h.media.playProcessing, isFalse);
        expect(find.text(_toastFailed), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    _flowTest('ring tidak muncul bila respons datang sebelum 400 dtk', (
      tester,
    ) async {
      final repo = _GatedMediaRepository();
      final h = await _pumpRemote(
        tester,
        status: FakeStatusRepository([fakeStatusOk()]),
        media: repo,
      );

      await tester.tap(_play);
      await tester.pump();
      repo.replies[0].complete();
      await _settle(tester);

      // The hint job was cancelled when the reply came in.
      expect(h.scheduler.hasLiveOnce(RMotion.processingHint), isFalse);
      expect(_ring, findsNothing);
    });
  });

  group('S04 gagal kirim', () {
    _flowTest(
      '500 media_failed: ikon kembali, toast Ulangi, Ulangi kirim ulang dan berhasil',
      (tester) async {
        final repo = FakeMediaRepository([
          fakeMediaError(500, 'media_failed'),
          fakeMediaOk(MediaAction.playPause),
        ]);
        final h = await _pumpRemote(
          tester,
          status: FakeStatusRepository([fakeStatusOk()]),
          media: repo,
        );

        await tester.tap(_play);
        await _settle(tester);

        // Rollback: back to pause, toast with retry.
        expect(h.media.playing, isTrue);
        expect(find.byWidgetPredicate(_iconIs(RIcons.pause)), findsOneWidget);
        expect(find.text(_toastFailed), findsOneWidget);
        expect(_retry, findsOneWidget);
        expect(h.sink.calls, contains('vibrate'));

        // Ulangi sends the same action again, and it succeeds.
        await tester.tap(_retry);
        await _settle(tester);
        expect(repo.calls, 2);
        expect(repo.lastAction, MediaAction.playPause);
        expect(h.media.playing, isFalse);
        expect(find.text(_toastFailed), findsNothing);
        expect(_retry, findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    _flowTest(
      'timeout 3 dtk tanpa jawaban: rollback dan toast, tanpa retry otomatis',
      (tester) async {
        final repo = _GatedMediaRepository();
        final h = await _pumpRemote(
          tester,
          status: FakeStatusRepository([fakeStatusOk()]),
          media: repo,
        );

        await tester.tap(_play);
        await tester.pump();
        expect(h.media.playing, isFalse);

        await tester.pump(RMotion.commandTimeout);
        await tester.pump();

        expect(h.media.playing, isTrue);
        expect(h.media.playProcessing, isFalse);
        expect(find.text(_toastFailed), findsOneWidget);
        expect(_retry, findsOneWidget);
        // No automatic retry: still exactly one request.
        expect(repo.sent, [MediaAction.playPause]);
        expect(tester.takeException(), isNull);
      },
    );

    _flowTest(
      'prev gagal: Ulangi mengirim prev lagi, ikon play tidak berubah',
      (tester) async {
        final repo = FakeMediaRepository([
          fakeMediaError(500, 'media_failed'),
          fakeMediaOk(MediaAction.prev),
        ]);
        final h = await _pumpRemote(
          tester,
          status: FakeStatusRepository([fakeStatusOk()]),
          media: repo,
        );

        await tester.tap(_prev);
        await _settle(tester);
        expect(find.text(_toastFailed), findsOneWidget);
        expect(h.media.playing, isTrue);

        await tester.tap(_retry);
        await _settle(tester);
        expect(repo.calls, 2);
        expect(repo.lastAction, MediaAction.prev);
        expect(h.media.playing, isTrue);
        expect(find.text(_toastFailed), findsNothing);
      },
    );

    _flowTest('Ulangi pada play mengulang toggle dari keadaan rollback', (
      tester,
    ) async {
      final repo = FakeMediaRepository([
        fakeMediaError(500, 'media_failed'),
        fakeMediaOk(MediaAction.playPause),
      ]);
      final h = await _pumpRemote(
        tester,
        status: FakeStatusRepository([fakeStatusOk()]),
        media: repo,
      );

      await tester.tap(_play);
      await _settle(tester);
      expect(h.media.playing, isTrue);

      await tester.tap(_retry);
      await _settle(tester);
      expect(repo.calls, 2);
      expect(h.media.playing, isFalse);
    });
  });

  group('401 dan offline', () {
    _flowTest('401 dari media: token ditolak, tanpa toast Ulangi', (
      tester,
    ) async {
      final repo = FakeMediaRepository([fakeMediaError(401, 'invalid_token')]);
      final h = await _pumpRemote(
        tester,
        status: FakeStatusRepository([fakeStatusOk()]),
        media: repo,
      );

      await tester.tap(_play);
      await _settle(tester);

      expect(h.phase, ConnectionPhase.tokenRejected);
      expect(_retry, findsNothing);
      expect(find.text(_toastFailed), findsNothing);
      expect(_isEnabled(tester, RemoteStrings.prevLabel), isFalse);
      expect(tester.takeException(), isNull);
    });

    _flowTest('offline: dock nonaktif dan tap tidak mengirim perintah', (
      tester,
    ) async {
      final repo = FakeMediaRepository([fakeMediaOk(MediaAction.prev)]);
      final h = await _pumpRemote(
        tester,
        status: FakeStatusRepository([
          const FakeTransportFailure(TimeoutFailure()),
        ]),
        media: repo,
      );
      // The start poll failed once (still connecting). The next periodic poll
      // fails again and the screen turns offline (S10).
      h.scheduler.periodicJob!.run();
      await _settle(tester);
      expect(find.text('Laptop nggak kejangkau'), findsOneWidget);

      await tester.tap(_prev);
      await tester.tap(_next);
      await tester.tap(_play);
      await tester.pump();
      expect(repo.calls, 0);
      expect(_isEnabled(tester, RemoteStrings.pauseLabel), isFalse);
    });
  });

  group('Semantics', () {
    _flowTest(
      'label Jeda/Putar, hint Ngirim ke laptop, grup Media, toast liveRegion',
      (tester) async {
        final repo = _GatedMediaRepository();
        await _pumpRemote(
          tester,
          status: FakeStatusRepository([fakeStatusOk()]),
          media: repo,
        );

        expect(
          find.bySemanticsLabel(RemoteStrings.mediaGroupLabel),
          findsOneWidget,
        );
        expect(find.bySemanticsLabel(RemoteStrings.prevLabel), findsOneWidget);
        expect(find.bySemanticsLabel(RemoteStrings.nextLabel), findsOneWidget);
        expect(find.bySemanticsLabel(RemoteStrings.pauseLabel), findsOneWidget);

        await tester.tap(_play);
        await tester.pump();
        final playData = tester
            .getSemantics(find.bySemanticsLabel(RemoteStrings.playLabel).first)
            .getSemanticsData();
        expect(playData.hint, RemoteStrings.playSendingHint);

        repo.replies[0].completeError(const ServerFailure());
        await _settle(tester);
        final liveRegion = find.ancestor(
          of: find.text(_toastFailed),
          matching: find.byWidgetPredicate(
            (w) => w is Semantics && w.properties.liveRegion == true,
          ),
        );
        expect(liveRegion, findsWidgets);
        final toastData = tester
            .getSemantics(liveRegion.first)
            .getSemanticsData();
        expect(toastData.flagsCollection.isLiveRegion, isTrue);
      },
    );
  });

  group('layout 412 dan 360, terang dan gelap, teks 130%', () {
    for (final width in [360.0, 412.0]) {
      for (final dark in [false, true]) {
        _flowTest('lebar $width dark=$dark: dock dan toast tanpa overflow', (
          tester,
        ) async {
          await _pumpRemote(
            tester,
            status: FakeStatusRepository([fakeStatusOk()]),
            media: FakeMediaRepository([fakeMediaError(500, 'media_failed')]),
            size: Size(width, 800),
            dark: dark,
            textScale: 1.3,
          );

          expect(find.byType(MediaDock), findsOneWidget);
          expect(
            find.bySemanticsLabel(RemoteStrings.mediaGroupLabel),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);

          await tester.tap(_prev);
          await _settle(tester);
          expect(find.text(_toastFailed), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }
    }
  });
}
