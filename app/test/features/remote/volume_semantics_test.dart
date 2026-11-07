import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
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
import 'package:remotto/features/remote/widgets/volume_panel.dart';
import 'package:remotto/ui/glass_key.dart';
import 'package:remotto/ui/glass_panel.dart';
import 'package:remotto/ui/volume_readout.dart';
import 'package:remotto/ui/volume_slider.dart';

import '../../support/fake_poll_scheduler.dart';
import '../../support/fake_status_repository.dart';
import '../../support/fake_volume_repository.dart';
import '../../support/fakes.dart';

/// Pumps the panel the way RemoteScreen does: inside a [GlassPanel] that
/// carries the group label "Volume".
Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required VolumeStatus volume,
  FakeVolumeRepository? repo,
  Size size = const Size(412, 892),
  double textScale = 1.0,
  bool compact = false,
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
          fakeStatusOk(volumeLevel: volume.level, volumeMuted: volume.muted),
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
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: SizedBox.expand(
            child: GlassPanel(
              padding: const EdgeInsets.all(RSpace.s5),
              semanticsLabel: RemoteStrings.volumeGroupLabel,
              child: VolumePanel(
                phase: ConnectionPhase.online,
                onRetry: () {},
                onRepair: () {},
                compact: compact,
              ),
            ),
          ),
        ),
      ),
    ),
  );

  // Runs the first poll; the controller picks the value up from the connection.
  await tester.runAsync(() async {
    container.read(connectionControllerProvider.notifier).start();
    await Future<void>.delayed(Duration.zero);
  });
  await tester.pump();
  return container;
}

/// The slider's own Semantics node: slider flag, label "Volume".
SemanticsFinder get _sliderNode => find.semantics.byPredicate(
  (n) => n.getSemanticsData().flagsCollection.isSlider,
);

/// Semantics widget of the group (GlassPanel with the "Volume" label).
Finder get _groupNode => find.byWidgetPredicate(
  (w) =>
      w is Semantics &&
      w.properties.slider != true &&
      w.properties.label == RemoteStrings.volumeGroupLabel,
);

/// Semantics widget of the slider (the one with the slider flag).
Finder get _sliderWidget => find.byWidgetPredicate(
  (w) => w is Semantics && w.properties.slider == true,
);

/// Walks the group's subtree in traversal order and returns every labelled
/// node, depth first. The group itself is not included. Excluded nodes do not
/// appear.
List<String> _labelsInOrder(WidgetTester tester) {
  final labels = <String>[];
  void visit(SemanticsNode node) {
    final data = node.getSemanticsData();
    if (data.label.isNotEmpty) labels.add(data.label);
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  tester.getSemantics(_groupNode).visitChildren((child) {
    visit(child);
    return true;
  });
  return labels;
}

/// Every label and value text in the semantics subtree of the group.
List<String> _allSemanticsText(WidgetTester tester) {
  final texts = <String>[];
  void visit(SemanticsNode node) {
    final data = node.getSemanticsData();
    if (data.label.isNotEmpty) texts.add(data.label);
    if (data.value.isNotEmpty) texts.add(data.value);
    if (data.hint.isNotEmpty) texts.add(data.hint);
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  visit(tester.getSemantics(_groupNode));
  return texts;
}

SemanticsNode _sliderSemantics(WidgetTester tester) =>
    tester.getSemantics(_sliderWidget);

GlassKey _key(WidgetTester tester, String label) => tester.widget<GlassKey>(
  find.byWidgetPredicate((w) => w is GlassKey && w.semanticsLabel == label),
);

void main() {
  late SemanticsHandle handle;

  group('slider semantics', () {
    testWidgets('isSlider, value "N persen", increased and decreased values', (
      tester,
    ) async {
      handle = tester.ensureSemantics();
      await _pump(tester, volume: const VolumeStatus(level: 35, muted: false));

      final data = _sliderSemantics(tester).getSemanticsData();
      expect(data.flagsCollection.isSlider, isTrue);
      expect(data.label, RemoteStrings.volumeGroupLabel);
      expect(data.value, '35 persen');
      expect(data.increasedValue, '40 persen');
      expect(data.decreasedValue, '30 persen');
      handle.dispose();
    });

    testWidgets('increase and decrease actions call the controller', (
      tester,
    ) async {
      handle = tester.ensureSemantics();
      final repo = FakeVolumeRepository();
      await _pump(
        tester,
        volume: const VolumeStatus(level: 35, muted: false),
        repo: repo,
      );

      tester.semantics.performAction(_sliderNode, SemanticsAction.increase);
      await tester.pumpAndSettle();
      expect(repo.upCalls, 1);
      expect(_sliderSemantics(tester).getSemanticsData().value, '40 persen');

      tester.semantics.performAction(_sliderNode, SemanticsAction.decrease);
      await tester.pumpAndSettle();
      expect(repo.downCalls, 1);
      expect(_sliderSemantics(tester).getSemanticsData().value, '35 persen');
      handle.dispose();
    });

    testWidgets('value is not pushed to Semantics per frame while dragging', (
      tester,
    ) async {
      handle = tester.ensureSemantics();
      await _pump(tester, volume: const VolumeStatus(level: 35, muted: false));

      final center = tester.getCenter(find.byType(VolumeSlider));
      final gesture = await tester.startGesture(center);
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump();
      // The readout shows the live value, Semantics keeps the last announced.
      final draggingValue = _sliderSemantics(tester).getSemanticsData().value;
      expect(draggingValue, '35 persen');

      await gesture.moveBy(const Offset(40, 0));
      await tester.pump();
      expect(_sliderSemantics(tester).getSemanticsData().value, '35 persen');

      await gesture.up();
      await tester.pumpAndSettle();
      expect(
        _sliderSemantics(tester).getSemanticsData().value,
        '${_currentLevel(tester)} persen',
      );
      expect(_currentLevel(tester), isNot(35));
      handle.dispose();
    });
  });

  group('mute', () {
    testWidgets('mute key is toggled and its label follows the state', (
      tester,
    ) async {
      handle = tester.ensureSemantics();
      final repo = FakeVolumeRepository();
      await _pump(
        tester,
        volume: const VolumeStatus(level: 35, muted: false),
        repo: repo,
      );

      var data = tester
          .getSemantics(find.bySemanticsLabel(RemoteStrings.muteLabel))
          .getSemanticsData();
      expect(data.flagsCollection.isToggled, Tristate.isFalse);

      await tester.tap(find.bySemanticsLabel(RemoteStrings.muteLabel));
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel(RemoteStrings.muteLabel), findsNothing);
      data = tester
          .getSemantics(find.bySemanticsLabel(RemoteStrings.unmuteLabel))
          .getSemanticsData();
      expect(data.flagsCollection.isToggled, Tristate.isTrue);
      handle.dispose();
    });
  });

  group('tree content', () {
    testWidgets('number and hint are not in the Semantics tree', (
      tester,
    ) async {
      handle = tester.ensureSemantics();
      await _pump(tester, volume: const VolumeStatus(level: 35, muted: false));

      final texts = _allSemanticsText(tester);
      expect(texts.where((t) => t.contains('35%')), isEmpty);
      expect(texts, isNot(contains(RemoteStrings.hintIdle)));
      expect(texts, isNot(contains(RemoteStrings.volumeLabel)));
      expect(find.byType(VolumeReadout), findsOneWidget);
      handle.dispose();
    });

    testWidgets('group is labelled "Volume" and wraps the controls', (
      tester,
    ) async {
      handle = tester.ensureSemantics();
      await _pump(tester, volume: const VolumeStatus(level: 35, muted: false));

      final group = tester.getSemantics(_groupNode).getSemanticsData();
      expect(group.label, RemoteStrings.volumeGroupLabel);
      expect(_labelsInOrder(tester), contains(RemoteStrings.muteLabel));
      handle.dispose();
    });

    testWidgets('focus order is slider, mute, minus, plus', (tester) async {
      handle = tester.ensureSemantics();
      await _pump(tester, volume: const VolumeStatus(level: 35, muted: false));

      expect(_labelsInOrder(tester), [
        RemoteStrings.volumeGroupLabel, // slider, same label as the group
        RemoteStrings.muteLabel,
        RemoteStrings.volumeDownLabel,
        RemoteStrings.volumeUpLabel,
      ]);
      handle.dispose();
    });

    testWidgets('every control is at least 48 dp tall and wide', (
      tester,
    ) async {
      await _pump(tester, volume: const VolumeStatus(level: 35, muted: false));

      for (final label in [
        RemoteStrings.muteLabel,
        RemoteStrings.volumeDownLabel,
        RemoteStrings.volumeUpLabel,
      ]) {
        final size = tester.getSize(
          find.byWidgetPredicate(
            (w) => w is GlassKey && w.semanticsLabel == label,
          ),
        );
        expect(
          size.height,
          greaterThanOrEqualTo(RSize.touchMin),
          reason: label,
        );
        expect(size.width, greaterThanOrEqualTo(RSize.touchMin), reason: label);
      }
      expect(
        tester.getSize(find.byType(VolumeSlider)).height,
        greaterThanOrEqualTo(RSize.touchMin),
      );
      expect(_key(tester, RemoteStrings.muteLabel).size, GlassKeySize.control);
    });
  });

  group('layout', () {
    testWidgets('130% text at 360x640 does not overflow', (tester) async {
      await _pump(
        tester,
        volume: const VolumeStatus(level: 100, muted: true),
        size: const Size(360, 640),
        textScale: 1.3,
        compact: true,
      );

      expect(tester.takeException(), isNull);
    });

    for (final width in [360.0, 412.0]) {
      testWidgets('short screen ${width.toInt()}x640: no hint, number 96', (
        tester,
      ) async {
        await _pump(
          tester,
          volume: const VolumeStatus(level: 35, muted: false),
          size: Size(width, 640),
          compact: width <= 360,
        );

        expect(find.text(RemoteStrings.hintIdle), findsNothing);
        final rich = tester.widget<RichText>(
          find.byWidgetPredicate(
            (w) => w is RichText && w.text.toPlainText() == '35%',
          ),
        );
        final span = (rich.text as TextSpan).children!.first as TextSpan;
        expect(span.style!.fontSize, 96);
        expect(tester.takeException(), isNull);
      });
    }
  });
}

int _currentLevel(WidgetTester tester) {
  final rich = tester.widget<RichText>(
    find.byWidgetPredicate(
      (w) => w is RichText && RegExp(r'^\d+%$').hasMatch(w.text.toPlainText()),
    ),
  );
  return int.parse(rich.text.toPlainText().replaceAll('%', ''));
}
