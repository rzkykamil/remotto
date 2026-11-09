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
import 'package:remotto/core/theme/theme_extensions.dart';
import 'package:remotto/features/remote/data/media_repository.dart';
import 'package:remotto/features/remote/power/power_providers.dart';
import 'package:remotto/features/remote/remote_screen.dart';
import 'package:remotto/features/remote/state/media_providers.dart';
import 'package:remotto/features/remote/state/volume_controller.dart';
import 'package:remotto/features/remote/state/volume_providers.dart';
import 'package:remotto/features/remote/widgets/media_dock.dart';
import 'package:remotto/features/remote/widgets/offline_content.dart';
import 'package:remotto/features/remote/widgets/volume_panel.dart';
import 'package:remotto/ui/toast_host.dart';
import 'package:remotto/ui/volume_readout.dart';
import 'package:remotto/ui/volume_slider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_media_repository.dart';
import '../../support/fake_power_repository.dart';
import '../../support/fake_poll_scheduler.dart';
import '../../support/fake_status_repository.dart';
import '../../support/fake_volume_repository.dart';
import '../../support/fakes.dart';

const _pairing = PairingData(
  host: '192.168.1.10',
  port: 8765,
  token: 'test-token',
  laptopName: 'Laptop Uji',
);

const _toast35 = 'Volume nggak kekirim, balik ke 35%';

final class _Harness {
  _Harness(this.container, this.scheduler, this.volume);

  final ProviderContainer container;
  final FakePollScheduler scheduler;
  final FakeVolumeRepository volume;

  VolumeState get state => container.read(volumeControllerProvider);
  ConnectionPhase get phase =>
      container.read(connectionControllerProvider).phase;
}

/// Runs [body] with the semantics tree on, so finders by label work.
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

/// Runs [body] once in the light theme and once in the dark theme (S01, S05,
/// S07, S08, S09, S10 must hold in both).
void _themedFlowTest(
  String description,
  Future<void> Function(WidgetTester tester, bool dark) body,
) {
  for (final dark in [false, true]) {
    _flowTest(
      '$description (${dark ? 'gelap' : 'terang'})',
      (tester) => body(tester, dark),
    );
  }
}

/// Pumps the full Remote screen with the toast host, as in the app shell.
/// Status and volume are fakes; polling is driven by the test.
Future<_Harness> _pumpRemote(
  WidgetTester tester, {
  required StatusRepository status,
  FakeVolumeRepository? volume,
  Size size = const Size(412, 892),
  bool dark = false,
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
  final repo = volume ?? FakeVolumeRepository();

  final overrides = <Override>[
    statusRepositoryProvider.overrideWithValue(status),
    volumeRepositoryProvider.overrideWithValue(repo),
    mediaRepositoryProvider.overrideWithValue(
      FakeMediaRepository([fakeMediaOk(MediaAction.playPause)]),
    ),
    pollSchedulerProvider.overrideWithValue(scheduler),
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
        builder: (context, child) => ToastHost(child: child!),
        home: const Scaffold(body: RemoteScreen()),
      ),
    ),
  );
  await _settle(tester);

  final container = ProviderScope.containerOf(
    tester.element(find.byType(RemoteScreen)),
  );
  return _Harness(container, scheduler, repo);
}

/// Lets queued futures finish and rebuilds the frame.
Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(() => pumpEventQueue());
  await tester.pumpAndSettle();
}

VolumeSlider _slider(WidgetTester tester) =>
    tester.widget<VolumeSlider>(find.byType(VolumeSlider));

Finder _number(String text) => find.byWidgetPredicate(
  (w) => w is RichText && w.text.toPlainText() == text,
);

/// The number's own colour: the first child span holds the number style,
/// the root span only carries the default text colour.
Color _numberColor(WidgetTester tester, String text) {
  final rich = tester.widget<RichText>(_number(text));
  final number = (rich.text as TextSpan).children!.first as TextSpan;
  return number.style!.color!;
}

/// True when the semantics node with [label] is enabled.
bool _isEnabled(WidgetTester tester, String label) {
  final data = tester
      .getSemantics(find.bySemanticsLabel(label).first)
      .getSemanticsData();
  return data.flagsCollection.isEnabled == Tristate.isTrue;
}

/// Start point at [fraction] of the slider width.
Offset _at(WidgetTester tester, double fraction) {
  final rect = tester.getRect(find.byType(VolumeSlider));
  return Offset(rect.left + rect.width * fraction, rect.center.dy);
}

/// Drags from the 35% point to [target] fraction, and returns the gesture
/// so the test can release it.
Future<TestGesture> _dragFrom35To(WidgetTester tester, double target) async {
  final rect = tester.getRect(find.byType(VolumeSlider));
  final start = _at(tester, 0.35);
  final gesture = await tester.startGesture(start);
  await gesture.moveBy(Offset((target - 0.35) * rect.width, 0));
  await tester.pump();
  return gesture;
}

Finder get _mute => find.bySemanticsLabel(RemoteStrings.muteLabel);
Finder get _retry => find.text(RemoteStrings.toastRetry);

void main() {
  group('S01 terhubung', () {
    _themedFlowTest('35%, mute, -, + dan slider aktif', (tester, dark) async {
      final h = await _pumpRemote(
        tester,
        dark: dark,
        status: FakeStatusRepository([fakeStatusOk(volumeLevel: 35)]),
      );

      final brightness = Theme.of(tester.element(find.byType(VolumePanel)))
          .brightness;
      expect(brightness, dark ? Brightness.dark : Brightness.light);
      expect(_number('35%'), findsOneWidget);
      expect(find.text(RemoteStrings.hintIdle), findsOneWidget);
      expect(_slider(tester).enabled, isTrue);
      expect(_isEnabled(tester, RemoteStrings.muteLabel), isTrue);
      expect(_isEnabled(tester, RemoteStrings.volumeDownLabel), isTrue);
      expect(_isEnabled(tester, RemoteStrings.volumeUpLabel), isTrue);
      expect(find.byType(MediaDock), findsOneWidget);
      expect(h.phase, ConnectionPhase.online);
      expect(tester.takeException(), isNull);
    });
  });

  group('S05 geser', () {
    _themedFlowTest(
      'angka dan warna aksen berubah saat geser, request terkirim saat lepas',
      (tester, dark) async {
        final h = await _pumpRemote(
          tester,
          dark: dark,
          status: FakeStatusRepository([fakeStatusOk(volumeLevel: 35)]),
        );
        final context = tester.element(find.byType(VolumeReadout));
        final accent = context.accent.text;

        final gesture = await _dragFrom35To(tester, 0.6);
        expect(h.state.dragging, isTrue);
        expect(_number('60%'), findsOneWidget);
        expect(_numberColor(tester, '60%'), accent);
        expect(find.text(RemoteStrings.hintDragging), findsOneWidget);

        await gesture.up();
        await _settle(tester);

        expect(h.volume.lastLevel, 60);
        expect(h.volume.setLevelCalls, 1);
        expect(h.state.dragging, isFalse);
        expect(h.state.level, 60);
        expect(_number('60%'), findsOneWidget);
        expect(_numberColor(tester, '60%'), isNot(accent));
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('S06 gagal kirim', () {
    _flowTest('angka balik ke 35, toast dengan Ulangi; Ulangi berhasil', (
      tester,
    ) async {
      final volume = FakeVolumeRepository(
        script: [
          const FakeVolumeTimeout(),
          const FakeVolumeTimeout(),
          const FakeVolumeOk(),
        ],
      );
      final h = await _pumpRemote(
        tester,
        status: FakeStatusRepository([fakeStatusOk(volumeLevel: 35)]),
        volume: volume,
      );

      final gesture = await _dragFrom35To(tester, 0.6);
      await gesture.up();
      await _settle(tester);

      // The silent retry ran once, then the failure is shown.
      expect(volume.setLevelCalls, 2);
      expect(h.state.dragging, isFalse);
      expect(h.state.level, 35);
      expect(_number('35%'), findsOneWidget);
      expect(find.text(_toast35), findsOneWidget);
      expect(_retry, findsOneWidget);

      // Ulangi sends the failed value again, and it succeeds.
      await tester.tap(_retry);
      await _settle(tester);
      expect(volume.setLevelCalls, 3);
      expect(volume.lastLevel, 60);
      expect(h.state.level, 60);
      expect(_number('60%'), findsOneWidget);
      expect(find.text(_toast35), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('S07 mute', () {
    _themedFlowTest(
      'mute menampilkan BISU dan hint; geser saat muted menghapus BISU',
      (tester, dark) async {
        final h = await _pumpRemote(
          tester,
          dark: dark,
          status: FakeStatusRepository([fakeStatusOk(volumeLevel: 35)]),
        );

        await tester.tap(_mute);
        await _settle(tester);
        expect(h.volume.setMutedCalls, 1);
        expect(h.volume.lastMuted, isTrue);
        expect(find.text(RemoteStrings.mutedBadge), findsOneWidget);
        expect(find.text(RemoteStrings.hintMuted), findsOneWidget);
        expect(find.text(RemoteStrings.unmuteLabel), findsOneWidget);

        // BR-15: a drag while muted unmutes locally.
        final gesture = await _dragFrom35To(tester, 0.5);
        expect(find.text(RemoteStrings.mutedBadge), findsNothing);
        expect(find.text(RemoteStrings.hintDragging), findsOneWidget);
        expect(find.text(RemoteStrings.muteLabel), findsOneWidget);

        await gesture.up();
        await _settle(tester);
        expect(h.volume.lastLevel, 50);
        expect(h.state.muted, isFalse);
        expect(find.text(RemoteStrings.mutedBadge), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('S08 dan S09 batas', () {
    _themedFlowTest('level 0: - nonaktif, hint minimum', (tester, dark) async {
      await _pumpRemote(
        tester,
        dark: dark,
        status: FakeStatusRepository([fakeStatusOk(volumeLevel: 0)]),
        volume: FakeVolumeRepository(initialLevel: 0),
      );

      expect(find.text(RemoteStrings.hintMin), findsOneWidget);
      expect(_isEnabled(tester, RemoteStrings.volumeDownLabel), isFalse);
      expect(_isEnabled(tester, RemoteStrings.volumeUpLabel), isTrue);
    });

    _themedFlowTest('level 100: + nonaktif, hint maksimum', (
      tester,
      dark,
    ) async {
      await _pumpRemote(
        tester,
        dark: dark,
        status: FakeStatusRepository([fakeStatusOk(volumeLevel: 100)]),
        volume: FakeVolumeRepository(initialLevel: 100),
      );

      expect(find.text(RemoteStrings.hintMax), findsOneWidget);
      expect(_isEnabled(tester, RemoteStrings.volumeDownLabel), isTrue);
      expect(_isEnabled(tester, RemoteStrings.volumeUpLabel), isFalse);
    });
  });

  group('S10 offline saat geser', () {
    _themedFlowTest(
      'gesture dibatalkan, slider balik ke nilai terakhir, tanpa toast',
      (tester, dark) async {
        // The reply of the drag takes one second, so the drag is still in
        // flight when the laptop goes offline.
        final volume = FakeVolumeRepository(delay: const Duration(seconds: 1));
        final h = await _pumpRemote(
          tester,
          dark: dark,
          status: FakeStatusRepository([
            fakeStatusOk(volumeLevel: 35),
            const FakeTransportFailure(UnreachableFailure()),
            const FakeTransportFailure(UnreachableFailure()),
          ]),
          volume: volume,
        );

        final gesture = await _dragFrom35To(tester, 0.6);
        expect(h.state.dragging, isTrue);

        // Two failed polls in a row: offline (BR-8).
        h.scheduler.tick();
        await _settle(tester);
        expect(h.phase, ConnectionPhase.online);
        h.scheduler.tick();
        await _settle(tester);

        expect(h.phase, ConnectionPhase.offline);
        expect(find.byType(OfflineContent), findsOneWidget);
        expect(h.state.dragging, isFalse);
        expect(h.state.level, 35);
        expect(_slider(tester).enabled, isFalse);
        expect(_isEnabled(tester, RemoteStrings.muteLabel), isFalse);
        expect(_isEnabled(tester, RemoteStrings.volumeDownLabel), isFalse);
        expect(_isEnabled(tester, RemoteStrings.volumeUpLabel), isFalse);
        expect(find.text(_toast35), findsNothing);

        // Releasing the finger after the cancel sends nothing new.
        await gesture.up();
        await _settle(tester);
        expect(volume.setLevelCalls, 1);
        expect(find.textContaining('Volume nggak kekirim'), findsNothing);

        // Let the in-flight request finish so no timer is left pending.
        await tester.pump(const Duration(seconds: 1));
        await _settle(tester);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('T7 offline dan tokenRejected saat geser', () {
    _flowTest(
      'tokenRejected saat geser: slider balik, kontrol nonaktif, tanpa toast',
      (tester) async {
        final volume = FakeVolumeRepository();
        final h = await _pumpRemote(
          tester,
          status: FakeStatusRepository([
            fakeStatusOk(volumeLevel: 35),
            fakeErrorReply(401, 'invalid_token'),
          ]),
          volume: volume,
        );

        final gesture = await _dragFrom35To(tester, 0.6);
        expect(h.state.dragging, isTrue);
        // The drag sends levels while it runs; let those replies land.
        await _settle(tester);
        final callsBefore = volume.setLevelCalls;

        h.scheduler.tick();
        await _settle(tester);

        expect(h.phase, ConnectionPhase.tokenRejected);
        expect(h.state.dragging, isFalse);
        expect(h.state.level, volume.current.level, reason: 'nilai laptop');
        expect(
          _number('${volume.current.level}%'),
          findsOneWidget,
          reason: 'angka sama dengan nilai laptop',
        );
        expect(_slider(tester).enabled, isFalse);
        expect(_isEnabled(tester, RemoteStrings.muteLabel), isFalse);
        expect(_retry, findsNothing);
        expect(find.textContaining('Volume nggak kekirim'), findsNothing);

        await gesture.up();
        await _settle(tester);
        expect(
          volume.setLevelCalls,
          callsBefore,
          reason: 'tanpa setLevel baru',
        );
        expect(tester.takeException(), isNull);
      },
    );

    _flowTest('setelah pulih dari offline, angka disinkron dari laptop (40)', (
      tester,
    ) async {
      final volume = FakeVolumeRepository();
      final h = await _pumpRemote(
        tester,
        status: FakeStatusRepository([
          fakeStatusOk(volumeLevel: 35),
          const FakeTransportFailure(UnreachableFailure()),
          const FakeTransportFailure(UnreachableFailure()),
          fakeStatusOk(volumeLevel: 40),
        ]),
        volume: volume,
      );

      final gesture = await _dragFrom35To(tester, 0.6);
      // The drag sends levels while it runs; let those replies land.
      await _settle(tester);
      final callsBefore = volume.setLevelCalls;

      h.scheduler.tick();
      await _settle(tester);
      h.scheduler.tick();
      await _settle(tester);
      expect(h.phase, ConnectionPhase.offline);
      expect(h.state.dragging, isFalse);
      expect(find.byType(OfflineContent), findsOneWidget);

      await gesture.up();
      await _settle(tester);
      expect(volume.setLevelCalls, callsBefore, reason: 'tanpa setLevel baru');

      h.scheduler.tick();
      await _settle(tester);
      expect(h.phase, ConnectionPhase.back);
      expect(_number('40%'), findsOneWidget);
      expect(_slider(tester).value, 40);
      expect(_slider(tester).enabled, isTrue);
      expect(tester.takeException(), isNull);
    });
  });

  group('S11 polling', () {
    _flowTest(
      'poll saat idle menyinkronkan angka; poll saat geser tidak mengubah angka',
      (tester) async {
        final volume = FakeVolumeRepository(delay: const Duration(seconds: 1));
        final h = await _pumpRemote(
          tester,
          status: FakeStatusRepository([
            fakeStatusOk(volumeLevel: 35),
            fakeStatusOk(volumeLevel: 20),
            fakeStatusOk(volumeLevel: 40),
          ]),
          volume: volume,
        );
        expect(_number('35%'), findsOneWidget);

        // Drag to 60 while the reply is in flight; a poll arrives meanwhile.
        final gesture = await _dragFrom35To(tester, 0.6);
        h.scheduler.tick();
        await _settle(tester);
        expect(_number('60%'), findsOneWidget);
        expect(_slider(tester).value, 60);
        expect(h.state.dragging, isTrue);

        // The reply lands during the drag, then the finger is released.
        await tester.pump(const Duration(seconds: 1));
        await _settle(tester);
        await gesture.up();
        await _settle(tester);
        expect(_number('60%'), findsOneWidget);
        expect(h.state.dragging, isFalse);

        // Idle poll: the laptop value 40 is shown.
        h.scheduler.tick();
        await _settle(tester);
        expect(_number('40%'), findsOneWidget);
        expect(_slider(tester).value, 40);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
