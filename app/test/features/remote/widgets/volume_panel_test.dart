import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotto/core/connection/connection_providers.dart';
import 'package:remotto/core/connection/connection_state.dart';
import 'package:remotto/core/haptics/r_haptics.dart';
import 'package:remotto/core/network/agent_status.dart';
import 'package:remotto/core/network/network_providers.dart';
import 'package:remotto/core/strings/remote_strings.dart';
import 'package:remotto/core/theme/app_theme.dart';
import 'package:remotto/core/theme/tokens.g.dart';
import 'package:remotto/features/remote/state/volume_providers.dart';
import 'package:remotto/features/remote/widgets/offline_content.dart';
import 'package:remotto/features/remote/widgets/volume_panel.dart';
import 'package:remotto/ui/glass_key.dart';
import 'package:remotto/ui/glass_panel.dart';
import 'package:remotto/ui/volume_readout.dart';
import 'package:remotto/ui/volume_slider.dart';

import '../../../support/fake_poll_scheduler.dart';
import '../../../support/fake_status_repository.dart';
import '../../../support/fake_volume_repository.dart';
import '../../../support/fakes.dart';

/// Pumps [VolumePanel] inside the screen's glass panel. When [volume] is set,
/// the connection is started so that the controller learns the value.
Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required ConnectionPhase phase,
  VolumeStatus? volume,
  FakeVolumeRepository? repo,
  VoidCallback? onRetry,
  VoidCallback? onRepair,
  bool compact = false,
  bool dark = false,
  double textScale = 1.0,
  Size size = const Size(412, 892),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  final container = ProviderContainer(
    overrides: [
      volumeRepositoryProvider.overrideWithValue(
        repo ?? FakeVolumeRepository(),
      ),
      pollSchedulerProvider.overrideWithValue(FakePollScheduler()),
      statusRepositoryProvider.overrideWithValue(
        FakeStatusRepository([
          fakeStatusOk(
            volumeLevel: volume?.level ?? 0,
            volumeMuted: volume?.muted ?? false,
            volumeUnavailable: volume == null,
          ),
        ]),
      ),
      hapticsProvider.overrideWithValue(
        RHaptics(sink: RecordingHapticSink(), enabled: () => false),
      ),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: SizedBox.expand(
            child: GlassPanel(
              padding: const EdgeInsets.all(RSpace.s5),
              child: VolumePanel(
                phase: phase,
                onRetry: onRetry ?? () {},
                onRepair: onRepair ?? () {},
                compact: compact,
              ),
            ),
          ),
        ),
      ),
    ),
  );

  if (volume != null) {
    // Runs the first poll; the controller picks the value up from the connection.
    await tester.runAsync(() async {
      container.read(connectionControllerProvider.notifier).start();
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pump();
  }
  return container;
}

GlassKey _key(WidgetTester tester, String label) => tester.widget<GlassKey>(
  find.byWidgetPredicate((w) => w is GlassKey && w.semanticsLabel == label),
);

bool _keyEnabled(WidgetTester tester, String label) =>
    _key(tester, label).onPressed != null;

VolumeSlider _slider(WidgetTester tester) =>
    tester.widget<VolumeSlider>(find.byType(VolumeSlider));

void main() {
  const online = ConnectionPhase.online;

  testWidgets('idle hint at a middle level, number and slider shown', (
    tester,
  ) async {
    await _pump(
      tester,
      phase: online,
      volume: const VolumeStatus(level: 35, muted: false),
    );

    expect(
      find.byWidgetPredicate(
        (w) => w is RichText && w.text.toPlainText() == '35%',
      ),
      findsOneWidget,
    );
    expect(find.text(RemoteStrings.hintIdle), findsOneWidget);
    expect(_slider(tester).value, 35);
    expect(_keyEnabled(tester, RemoteStrings.volumeDownLabel), isTrue);
    expect(_keyEnabled(tester, RemoteStrings.volumeUpLabel), isTrue);
  });

  testWidgets('connecting shows the waiting hint and disables controls', (
    tester,
  ) async {
    await _pump(tester, phase: ConnectionPhase.connecting);

    expect(find.text(RemoteStrings.hintWaiting), findsOneWidget);
    expect(_slider(tester).enabled, isFalse);
    expect(_keyEnabled(tester, RemoteStrings.volumeDownLabel), isFalse);
    expect(_keyEnabled(tester, RemoteStrings.volumeUpLabel), isFalse);
    expect(_keyEnabled(tester, RemoteStrings.muteLabel), isFalse);
  });

  testWidgets('minimum level shows the min hint and disables minus', (
    tester,
  ) async {
    await _pump(
      tester,
      phase: online,
      volume: const VolumeStatus(level: 0, muted: false),
    );

    expect(find.text(RemoteStrings.hintMin), findsOneWidget);
    expect(_keyEnabled(tester, RemoteStrings.volumeDownLabel), isFalse);
    expect(_keyEnabled(tester, RemoteStrings.volumeUpLabel), isTrue);
  });

  testWidgets('maximum level shows the max hint and disables plus', (
    tester,
  ) async {
    await _pump(
      tester,
      phase: online,
      volume: const VolumeStatus(level: 100, muted: false),
    );

    expect(find.text(RemoteStrings.hintMax), findsOneWidget);
    expect(_keyEnabled(tester, RemoteStrings.volumeDownLabel), isTrue);
    expect(_keyEnabled(tester, RemoteStrings.volumeUpLabel), isFalse);
  });

  testWidgets('muted shows the badge, the muted hint and the unmute label', (
    tester,
  ) async {
    await _pump(
      tester,
      phase: online,
      volume: const VolumeStatus(level: 35, muted: true),
    );

    expect(find.text(RemoteStrings.mutedBadge), findsOneWidget);
    expect(find.text(RemoteStrings.hintMuted), findsOneWidget);
    expect(find.text(RemoteStrings.unmuteLabel), findsOneWidget);
    expect(find.text(RemoteStrings.muteLabel), findsNothing);
  });

  testWidgets('unmuted hides the badge and shows the mute label', (
    tester,
  ) async {
    await _pump(
      tester,
      phase: online,
      volume: const VolumeStatus(level: 35, muted: false),
    );

    expect(find.text(RemoteStrings.mutedBadge), findsNothing);
    expect(find.text(RemoteStrings.muteLabel), findsOneWidget);
  });

  testWidgets('offline shows OfflineContent and disables every control', (
    tester,
  ) async {
    var retried = 0;
    await _pump(
      tester,
      phase: ConnectionPhase.offline,
      volume: const VolumeStatus(level: 35, muted: false),
      onRetry: () => retried++,
    );

    expect(find.byType(OfflineContent), findsOneWidget);
    expect(find.byType(VolumeReadout), findsNothing);
    expect(_slider(tester).enabled, isFalse);
    expect(_keyEnabled(tester, RemoteStrings.muteLabel), isFalse);
    expect(_keyEnabled(tester, RemoteStrings.volumeDownLabel), isFalse);
    expect(_keyEnabled(tester, RemoteStrings.volumeUpLabel), isFalse);

    await tester.tap(find.text(RemoteStrings.offlineRetry));
    expect(retried, 1);
    expect(find.text(RemoteStrings.repairPairing), findsOneWidget);
  });

  testWidgets('tapping plus sends up and shows the new level', (tester) async {
    final repo = FakeVolumeRepository();
    await _pump(
      tester,
      phase: online,
      volume: const VolumeStatus(level: 35, muted: false),
      repo: repo,
    );

    await tester.tap(find.bySemanticsLabel(RemoteStrings.volumeUpLabel));
    await tester.pumpAndSettle();

    expect(repo.upCalls, 1);
    expect(_slider(tester).value, 40);
  });

  testWidgets('tapping mute sends setMuted and shows the badge', (
    tester,
  ) async {
    final repo = FakeVolumeRepository();
    await _pump(
      tester,
      phase: online,
      volume: const VolumeStatus(level: 35, muted: false),
      repo: repo,
    );

    await tester.tap(find.bySemanticsLabel(RemoteStrings.muteLabel));
    await tester.pumpAndSettle();

    expect(repo.setMutedCalls, 1);
    expect(repo.lastMuted, isTrue);
    expect(find.text(RemoteStrings.mutedBadge), findsOneWidget);
  });

  testWidgets('tapping the slider track sends the tapped level', (
    tester,
  ) async {
    final repo = FakeVolumeRepository();
    await _pump(
      tester,
      phase: online,
      volume: const VolumeStatus(level: 35, muted: false),
      repo: repo,
    );

    await tester.tapAt(tester.getCenter(find.byType(VolumeSlider)));
    await tester.pumpAndSettle();

    expect(repo.lastLevel, closeTo(50, 2));
    expect(repo.setLevelCalls, 1);
  });

  testWidgets('short screen hides the hint and shrinks the number', (
    tester,
  ) async {
    await _pump(
      tester,
      phase: online,
      volume: const VolumeStatus(level: 35, muted: false),
      size: const Size(360, 640),
    );

    expect(find.text(RemoteStrings.hintIdle), findsNothing);
    final rich = tester.widget<RichText>(
      find.byWidgetPredicate(
        (w) => w is RichText && w.text.toPlainText() == '35%',
      ),
    );
    final span = (rich.text as TextSpan).children!.first as TextSpan;
    expect(span.style!.fontSize, 96);
  });

  testWidgets('tall screen keeps the hint', (tester) async {
    await _pump(
      tester,
      phase: online,
      volume: const VolumeStatus(level: 35, muted: false),
      size: const Size(412, 892),
    );

    expect(find.text(RemoteStrings.hintIdle), findsOneWidget);
  });

  for (final dark in [false, true]) {
    testWidgets('130% text at 360 dp does not overflow (dark: $dark)', (
      tester,
    ) async {
      await _pump(
        tester,
        phase: online,
        volume: const VolumeStatus(level: 100, muted: true),
        compact: true,
        dark: dark,
        textScale: 1.3,
        size: const Size(360, 640),
      );

      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('slider exposes value and actions through Semantics', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(
      tester,
      phase: online,
      volume: const VolumeStatus(level: 35, muted: false),
    );

    final node = tester.getSemantics(
      find.bySemanticsLabel(RemoteStrings.volumeGroupLabel),
    );
    expect(node.value, '35 persen');
    expect(node.increasedValue, '40 persen');
    expect(node.decreasedValue, '30 persen');
    handle.dispose();
  });

  testWidgets('hint shows the dragging text while the slider is held', (
    tester,
  ) async {
    await _pump(
      tester,
      phase: online,
      volume: const VolumeStatus(level: 35, muted: false),
    );

    final center = tester.getCenter(find.byType(VolumeSlider));
    final gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(60, 0));
    await tester.pump();

    expect(find.text(RemoteStrings.hintDragging), findsOneWidget);
    expect(find.text(RemoteStrings.hintIdle), findsNothing);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text(RemoteStrings.hintDragging), findsNothing);
  });

  testWidgets('360x780 compact: 108 sp number and hint are shown', (
    tester,
  ) async {
    await _pump(
      tester,
      phase: online,
      volume: const VolumeStatus(level: 35, muted: false),
      compact: true,
      size: const Size(360, 780),
    );

    expect(find.text(RemoteStrings.hintIdle), findsOneWidget);
    final rich = tester.widget<RichText>(
      find.byWidgetPredicate(
        (w) => w is RichText && w.text.toPlainText() == '35%',
      ),
    );
    final span = (rich.text as TextSpan).children!.first as TextSpan;
    expect(span.style!.fontSize, 108);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mute key reports toggled state through Semantics', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(
      tester,
      phase: online,
      volume: const VolumeStatus(level: 35, muted: false),
    );

    final unmuted = tester
        .getSemantics(find.bySemanticsLabel(RemoteStrings.muteLabel))
        .getSemanticsData();
    expect(unmuted.flagsCollection.isToggled, Tristate.isFalse);

    final repo = FakeVolumeRepository(initialLevel: 35, initialMuted: true);
    await _pump(
      tester,
      phase: online,
      volume: const VolumeStatus(level: 35, muted: true),
      repo: repo,
    );
    final muted = tester
        .getSemantics(find.bySemanticsLabel(RemoteStrings.unmuteLabel))
        .getSemanticsData();
    expect(muted.flagsCollection.isToggled, Tristate.isTrue);
    handle.dispose();
  });
}
