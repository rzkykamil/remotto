import 'dart:async';

import 'package:flutter/material.dart';

import 'dart:ui' show Tristate;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:remotto/app.dart';
import 'package:remotto/core/connection/connection_controller.dart';
import 'package:remotto/core/connection/connection_providers.dart';
import 'package:remotto/core/connection/connection_state.dart';
import 'package:remotto/core/connection/status_repository.dart';
import 'package:remotto/core/network/agent_status.dart';
import 'package:remotto/core/network/api_failure.dart';
import 'package:remotto/core/network/network_providers.dart';
import 'package:remotto/core/router/app_router.dart';
import 'package:remotto/core/storage/pairing_data.dart';
import 'package:remotto/core/storage/storage_providers.dart';
import 'package:remotto/core/theme/app_theme.dart';
import 'package:remotto/core/theme/r_behavior.dart';
import 'package:remotto/core/theme/tokens.g.dart';
import 'package:remotto/core/strings/pairing_strings.dart';
import 'package:remotto/core/strings/remote_strings.dart';
import 'package:remotto/core/toast/toast_controller.dart';
import 'package:remotto/features/remote/remote_screen.dart';
import 'package:remotto/features/remote/widgets/media_dock.dart';
import 'package:remotto/ui/glass_toast.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_status_repository.dart';
import '../../support/fakes.dart';
import '../../support/volume_overrides.dart';

const _pairing = PairingData(
  host: '192.168.1.10',
  port: 8765,
  token: 'test-token',
  laptopName: 'Laptop Uji',
);

/// Fake scheduler: timers do not run on their own. The test triggers them.
final class _ManualScheduler implements PollScheduler {
  final List<_Job> jobs = [];

  @override
  ScheduledJob every(Duration interval, void Function() tick) {
    final job = _Job(tick, periodic: true);
    jobs.add(job);
    return job;
  }

  @override
  ScheduledJob after(Duration delay, void Function() callback) {
    final job = _Job(callback, periodic: false, delay: delay);
    jobs.add(job);
    return job;
  }

  bool get hasLivePeriodic => jobs.any((j) => j.periodic && j.live);

  /// Run the periodic polling ticks that are still alive.
  void tick() {
    final job = jobs.lastWhere((j) => j.periodic && j.live);
    job.callback();
  }

  /// Run the one-shot timer that is still alive with [delay].
  void fire(Duration delay) {
    final job = jobs.lastWhere(
      (j) => !j.periodic && j.live && j.delay == delay,
    );
    job.run();
  }
}

final class _Job implements ScheduledJob {
  _Job(this.callback, {required this.periodic, this.delay});

  final void Function() callback;
  final bool periodic;
  final Duration? delay;
  bool _done = false;

  bool get live => !_done;

  @override
  void cancel() => _done = true;

  void run() {
    if (!periodic) _done = true;
    callback();
  }
}

/// Repository that holds every reply until the test answers it.
final class _GatedRepository implements StatusRepository {
  final List<Completer<AgentStatus>> requests = [];

  @override
  Future<AgentStatus> fetchStatus() {
    final completer = Completer<AgentStatus>();
    requests.add(completer);
    return completer.future;
  }

  void answerOk([String name = 'Laptop-Kamil', int uptimeSeconds = 0]) {
    final last = requests.last;
    last.complete(
      parseStatusResponse(
        200,
        fakeStatusOk(name: name, uptimeSeconds: uptimeSeconds).body,
      ),
    );
  }
}

final class _Harness {
  _Harness(this.container, this.scheduler, this.storage);

  final ProviderContainer container;
  final _ManualScheduler scheduler;
  final InMemoryConnectionStorage storage;
}

/// Waits for ready futures, then rebuilds the frame.
Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(() => pumpEventQueue());
  await tester.pumpAndSettle();
}

/// Opens the full app (router, ToastHost) with Remote as the initial route.
Future<_Harness> _pumpApp(
  WidgetTester tester, {
  required StatusRepository repo,
  List<Override> extra = const [],
}) async {
  tester.view.physicalSize = const Size(412, 892);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  final prefs = (await tester.runAsync(() async {
    SharedPreferences.setMockInitialValues({});
    return SharedPreferences.getInstance();
  }))!;
  final scheduler = _ManualScheduler();
  final storage = InMemoryConnectionStorage(_pairing);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        initialPairingProvider.overrideWithValue(_pairing),
        connectionStorageProvider.overrideWithValue(storage),
        statusRepositoryProvider.overrideWithValue(repo),
        pollSchedulerProvider.overrideWithValue(scheduler),
        volumeOverride(),
        ...extra,
      ],
      child: const RemottoApp(),
    ),
  );
  await _settle(tester);
  final container = ProviderScope.containerOf(
    tester.element(find.byType(RemottoApp)),
  );
  return _Harness(container, scheduler, storage);
}

void main() {
  testWidgets(
    'S01 terhubung: nama laptop dan pill uptime, tanpa panel offline',
    (tester) async {
      await _pumpApp(
        tester,
        repo: FakeStatusRepository([
          fakeStatusOk(name: 'Laptop-Kamil', uptimeSeconds: 3 * 3600 + 12 * 60),
        ]),
      );

      expect(find.byType(RemoteScreen), findsOneWidget);
      expect(find.text('Laptop-Kamil'), findsOneWidget);
      expect(find.text('NYAMBUNG · 3J 12M'), findsOneWidget);
      expect(find.text('Laptop nggak kejangkau'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'S02 menyambung: kicker menunggu, pill MENYAMBUNG sampai dijawab',
    (tester) async {
      final repo = _GatedRepository();
      await _pumpApp(tester, repo: repo);

      expect(find.text('MENYAMBUNG…'), findsOneWidget);
      expect(find.text('Nunggu jawaban dari laptop…'), findsOneWidget);

      repo.answerOk();
      await _settle(tester);

      expect(find.text('Nunggu jawaban dari laptop…'), findsNothing);
      expect(find.text('NYAMBUNG · 0M'), findsOneWidget);
    },
  );

  testWidgets(
    'gagal 2x -> S10; Coba lagi menampilkan Nyoba…; pulih -> S11 toast',
    (tester) async {
      final repo = _GatedRepository();
      final harness = await _pumpApp(tester, repo: repo);

      // First poll failed: still connecting (BR-8 counts 2 failures).
      repo.requests.last.completeError(const TimeoutFailure());
      await _settle(tester);
      expect(find.text('MENYAMBUNG…'), findsOneWidget);

      // Second periodic poll failed: offline (S10).
      harness.scheduler.tick();
      repo.requests.last.completeError(const UnreachableFailure());
      await _settle(tester);
      expect(find.text('Laptop nggak kejangkau'), findsOneWidget);
      expect(find.text('NGGAK KEJANGKAU'), findsOneWidget);

      // Coba lagi: manual poll in progress, the button shows Nyoba….
      await tester.tap(find.text('Coba lagi'));
      await tester.pump();
      expect(find.text('Nyoba…'), findsOneWidget);
      expect(find.text('Coba lagi'), findsNothing);

      // Laptop recovered: pill NYAMBUNG LAGI, info toast appears (S11).
      repo.answerOk();
      await _settle(tester);
      expect(find.text('NYAMBUNG LAGI'), findsOneWidget);
      expect(find.text('Laptop nyambung lagi'), findsOneWidget);
      expect(find.text('Laptop nggak kejangkau'), findsNothing);

      // 2 seconds later the pill returns to normal.
      harness.scheduler.fire(RBehavior.reconnectedPill);
      await _settle(tester);
      expect(find.text('NYAMBUNG LAGI'), findsNothing);
      expect(find.text('NYAMBUNG · 0M'), findsOneWidget);

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    '401 dari layar Remote nyata: Q12, polling berhenti, data tetap',
    (tester) async {
      final repo = FakeStatusRepository([
        fakeStatusOk(),
        fakeErrorReply(401, 'unauthorized'),
      ]);
      final harness = await _pumpApp(tester, repo: repo);
      expect(find.byType(RemoteScreen), findsOneWidget);

      harness.scheduler.tick();
      await _settle(tester);

      expect(find.byType(RemoteScreen), findsNothing);
      expect(find.text(PairingStrings.expiredTitle), findsOneWidget);
      expect(
        harness.container.read(connectionControllerProvider).phase,
        ConnectionPhase.tokenRejected,
      );
      expect(harness.storage.data, _pairing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('keluar dari Remote menghentikan polling berkala', (
    tester,
  ) async {
    final harness = await _pumpApp(
      tester,
      repo: FakeStatusRepository([fakeStatusOk()]),
    );
    expect(harness.scheduler.hasLivePeriodic, isTrue);

    await tester.runAsync(() async {
      harness.container.read(routerProvider).go('/pairing');
    });
    await _settle(tester);

    expect(find.byType(RemoteScreen), findsNothing);
    expect(harness.scheduler.hasLivePeriodic, isFalse);
  });

  testWidgets('dock tampil dan aktif saat online', (tester) async {
    final handle = tester.ensureSemantics();
    await _pumpApp(tester, repo: FakeStatusRepository([fakeStatusOk()]));

    expect(find.byType(MediaDock), findsOneWidget);
    expect(
      find.bySemanticsLabel(RemoteStrings.mediaGroupLabel),
      findsOneWidget,
    );
    expect(_isEnabled(tester, RemoteStrings.prevLabel), isTrue);
    expect(_isEnabled(tester, RemoteStrings.nextLabel), isTrue);
    expect(_isEnabled(tester, RemoteStrings.pauseLabel), isTrue);
    handle.dispose();
  });

  testWidgets('dock nonaktif saat menyambung (S02)', (tester) async {
    final handle = tester.ensureSemantics();
    await _pumpApp(tester, repo: _GatedRepository());

    expect(find.byType(MediaDock), findsOneWidget);
    expect(_isEnabled(tester, RemoteStrings.prevLabel), isFalse);
    expect(_isEnabled(tester, RemoteStrings.pauseLabel), isFalse);
    expect(_isEnabled(tester, RemoteStrings.nextLabel), isFalse);
    handle.dispose();
  });

  testWidgets('dock nonaktif saat offline (S10)', (tester) async {
    final handle = tester.ensureSemantics();
    final repo = _GatedRepository();
    final harness = await _pumpApp(tester, repo: repo);

    repo.requests.last.completeError(const TimeoutFailure());
    await _settle(tester);
    harness.scheduler.tick();
    repo.requests.last.completeError(const UnreachableFailure());
    await _settle(tester);
    expect(find.text('Laptop nggak kejangkau'), findsOneWidget);

    expect(_isEnabled(tester, RemoteStrings.prevLabel), isFalse);
    expect(_isEnabled(tester, RemoteStrings.pauseLabel), isFalse);
    expect(_isEnabled(tester, RemoteStrings.nextLabel), isFalse);
    handle.dispose();
  });

  testWidgets('toast 12 dp di atas dock, inset kembali 0 saat layar ditutup', (
    tester,
  ) async {
    final harness = await _pumpApp(
      tester,
      repo: FakeStatusRepository([fakeStatusOk()]),
    );
    expect(
      harness.container.read(toastBottomInsetProvider),
      MediaDock.heightFor(false) + RSpace.s6,
    );

    harness.container
        .read(toastControllerProvider.notifier)
        .show(const ToastMessage(text: 'Uji posisi'));
    await _settle(tester);

    final dockTop = tester.getTopLeft(find.byType(MediaDock)).dy;
    final toastBottom = tester.getBottomLeft(find.byType(GlassToast)).dy;
    expect(dockTop - toastBottom, closeTo(RSpace.s3, 0.01));

    await tester.runAsync(() async {
      harness.container.read(routerProvider).go('/pairing');
    });
    await _settle(tester);
    expect(harness.container.read(toastBottomInsetProvider), 0);
    expect(tester.takeException(), isNull);
  });

  for (final width in [360.0, 412.0]) {
    testWidgets('lebar $width, teks 130%: nama panjang tanpa overflow', (
      tester,
    ) async {
      await _pumpLayout(
        tester,
        width,
        FakeStatusRepository([
          fakeStatusOk(name: 'Laptop-Gaming-Kamil-ROG-Strix'),
        ]),
        _ManualScheduler(),
      );
      expect(find.text('Laptop-Gaming-Kamil-ROG-Strix'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('lebar $width, teks 130%: panel offline tanpa overflow', (
      tester,
    ) async {
      final scheduler = _ManualScheduler();
      await _pumpLayout(
        tester,
        width,
        FakeStatusRepository([const FakeTransportFailure(TimeoutFailure())]),
        scheduler,
      );
      scheduler.tick();
      await _settle(tester);
      expect(find.text('Laptop nggak kejangkau'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

/// True when the semantics node with [label] is enabled.
bool _isEnabled(WidgetTester tester, String label) {
  final data = tester
      .getSemantics(find.bySemanticsLabel(label))
      .getSemanticsData();
  return data.flagsCollection.isEnabled == Tristate.isTrue;
}

/// Remote without a router at width [width] and 130% text.
Future<void> _pumpLayout(
  WidgetTester tester,
  double width,
  StatusRepository repo,
  _ManualScheduler scheduler,
) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        statusRepositoryProvider.overrideWithValue(repo),
        pollSchedulerProvider.overrideWithValue(scheduler),
        volumeOverride(),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.3)),
          child: child!,
        ),
        home: const Scaffold(body: RemoteScreen()),
      ),
    ),
  );
  await _settle(tester);
}
