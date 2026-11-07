import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:remotto/core/haptics/r_haptics.dart';
import 'package:remotto/core/storage/app_preferences.dart';
import 'package:remotto/core/storage/storage_providers.dart';
import 'package:remotto/core/strings/remote_strings.dart';
import 'package:remotto/core/connection/connection_providers.dart';
import 'package:remotto/core/theme/tokens.g.dart';
import 'package:remotto/features/remote/data/media_repository.dart';
import 'package:remotto/features/remote/data/mock_media_repository.dart';
import 'package:remotto/features/remote/state/media_providers.dart';
import 'package:remotto/features/remote/widgets/media_dock.dart';
import 'package:remotto/ui/glass_key.dart';
import 'package:remotto/ui/play_key.dart';
import 'package:remotto/ui/r_icon.dart';
import 'package:remotto/ui/r_icons_data.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/fake_poll_scheduler.dart';
import '../../../support/fakes.dart';
import '../../../support/test_app.dart';

/// Repository whose reply the test completes by hand.
final class _GatedMediaRepository implements MediaRepository {
  final List<MediaAction> sent = [];
  Completer<void>? gate;

  @override
  Future<void> send(MediaAction action) {
    sent.add(action);
    return (gate = Completer<void>()).future;
  }
}

Future<List<Override>> _overrides({
  required MediaRepository repo,
  required FakePollScheduler scheduler,
  required RecordingHapticSink sink,
}) async {
  SharedPreferences.setMockInitialValues({
    AppPreferences.keyHapticEnabled: true,
  });
  final prefs = await SharedPreferences.getInstance();
  return [
    mediaRepositoryProvider.overrideWithValue(repo),
    pollSchedulerProvider.overrideWithValue(scheduler),
    hapticSinkProvider.overrideWithValue(sink),
    sharedPreferencesProvider.overrideWithValue(prefs),
  ];
}

Future<void> _pumpDock(
  WidgetTester tester, {
  required MediaRepository repo,
  required FakePollScheduler scheduler,
  required RecordingHapticSink sink,
  bool enabled = true,
  bool compact = false,
  bool dark = false,
  bool disableAnimations = false,
  Size size = const Size(412, 892),
}) async {
  await pumpApp(
    tester,
    MediaDock(enabled: enabled, compact: compact),
    overrides: await _overrides(repo: repo, scheduler: scheduler, sink: sink),
    dark: dark,
    disableAnimations: disableAnimations,
    size: size,
  );
}

Finder get _prev => find.bySemanticsLabel(RemoteStrings.prevLabel);
Finder get _next => find.bySemanticsLabel(RemoteStrings.nextLabel);
Finder get _play => find.byType(PlayKey);
Finder get _ring => find.byKey(const ValueKey('play-key-ring'));

bool Function(Widget) _iconIs(RIconData data) =>
    (w) => w is RIcon && identical(w.data, data);

void main() {
  late MockMediaRepository repo;
  late FakePollScheduler scheduler;
  late RecordingHapticSink sink;

  setUp(() {
    repo = MockMediaRepository(const [MockMediaEcho()]);
    scheduler = FakePollScheduler();
    sink = RecordingHapticSink();
  });

  testWidgets('prev, play and next send the matching action', (tester) async {
    final handle = tester.ensureSemantics();
    await _pumpDock(tester, repo: repo, scheduler: scheduler, sink: sink);

    await tester.tap(_prev);
    await tester.pumpAndSettle();
    expect(repo.lastAction, MediaAction.prev);

    await tester.tap(_next);
    await tester.pumpAndSettle();
    expect(repo.lastAction, MediaAction.next);

    await tester.tap(_play);
    await tester.pumpAndSettle();
    expect(repo.lastAction, MediaAction.playPause);
    expect(repo.calls, 3);
    handle.dispose();
  });

  testWidgets('each tap fires exactly one press haptic', (tester) async {
    await _pumpDock(tester, repo: repo, scheduler: scheduler, sink: sink);

    for (final finder in [_prev, _play, _next]) {
      sink.calls.clear();
      await tester.tap(finder);
      await tester.pumpAndSettle();
      expect(sink.calls, ['light']);
    }
  });

  testWidgets('disabled dock sends nothing and reports disabled semantics', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pumpDock(
      tester,
      repo: repo,
      scheduler: scheduler,
      sink: sink,
      enabled: false,
    );

    await tester.tap(_prev);
    await tester.tap(_play);
    await tester.tap(_next);
    await tester.pump();
    expect(repo.calls, 0);

    for (final label in [
      RemoteStrings.prevLabel,
      RemoteStrings.pauseLabel,
      RemoteStrings.nextLabel,
    ]) {
      final data = tester
          .getSemantics(find.bySemanticsLabel(label))
          .getSemanticsData();
      expect(data.flagsCollection.isEnabled, Tristate.isFalse, reason: label);
    }
    handle.dispose();
  });

  testWidgets('play label and glyph flip at once after a tap', (tester) async {
    final handle = tester.ensureSemantics();
    await _pumpDock(tester, repo: repo, scheduler: scheduler, sink: sink);

    expect(find.bySemanticsLabel(RemoteStrings.pauseLabel), findsOneWidget);
    expect(find.byWidgetPredicate(_iconIs(RIcons.pause)), findsOneWidget);

    await tester.tap(_play);
    await tester.pump();
    expect(find.bySemanticsLabel(RemoteStrings.playLabel), findsOneWidget);
    expect(find.byWidgetPredicate(_iconIs(RIcons.play)), findsOneWidget);
    await tester.pumpAndSettle();
    handle.dispose();
  });

  testWidgets('processing ring appears only after the hint delay', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final gated = _GatedMediaRepository();
    await _pumpDock(tester, repo: gated, scheduler: scheduler, sink: sink);

    await tester.tap(_play);
    await tester.pump();
    expect(_ring, findsNothing);
    final playData = tester
        .getSemantics(find.bySemanticsLabel(RemoteStrings.playLabel))
        .getSemanticsData();
    expect(playData.hint, RemoteStrings.playSendingHint);

    scheduler.fireOnce(RMotion.processingHint);
    await tester.pump();
    expect(_ring, findsOneWidget);

    gated.gate!.complete();
    await tester.pumpAndSettle();
    expect(_ring, findsNothing);
    handle.dispose();
  });

  testWidgets('prev blinks once over the blink duration', (tester) async {
    await _pumpDock(tester, repo: repo, scheduler: scheduler, sink: sink);

    expect(
      tester
          .widget<FadeTransition>(find.byType(FadeTransition).first)
          .opacity
          .value,
      1.0,
    );

    await tester.tap(_prev);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    final mid = tester
        .widget<FadeTransition>(find.byType(FadeTransition).first)
        .opacity
        .value;
    expect(mid, closeTo(0.35, 0.01));

    await tester.pump(const Duration(milliseconds: 240));
    final end = tester
        .widget<FadeTransition>(find.byType(FadeTransition).first)
        .opacity
        .value;
    expect(end, 1.0);
    await tester.pumpAndSettle();
  });

  testWidgets('next does not blink under reduced motion', (tester) async {
    await _pumpDock(
      tester,
      repo: repo,
      scheduler: scheduler,
      sink: sink,
      disableAnimations: true,
    );

    await tester.tap(_next);
    await tester.pump();
    expect(find.byType(FadeTransition), findsNothing);
    await tester.pumpAndSettle();
    expect(repo.lastAction, MediaAction.next);
  });

  testWidgets('sizes are 80 and 96 dp at 412 dp and 72 and 88 dp at 360 dp', (
    tester,
  ) async {
    await _pumpDock(tester, repo: repo, scheduler: scheduler, sink: sink);
    final keys = find.byType(GlassKey);
    expect(tester.getSize(keys.at(0)).width, RSize.media);
    expect(tester.getSize(_play).width, RSize.play);
    expect(tester.getSize(keys.at(2)).width, RSize.media);
    expect(MediaDock.heightFor(false), RSize.play + RSpace.s2 * 2);

    await _pumpDock(
      tester,
      repo: repo,
      scheduler: scheduler,
      sink: sink,
      compact: true,
      size: const Size(360, 800),
    );
    expect(
      tester.getSize(find.byType(GlassKey).at(0)).width,
      RSize.mediaCompact,
    );
    expect(tester.getSize(_play).width, RSize.playCompact);
    expect(
      tester.getSize(find.byType(GlassKey).at(2)).width,
      RSize.mediaCompact,
    );
    expect(MediaDock.heightFor(true), RSize.playCompact + RSpace.s2 * 2);
  });

  testWidgets('dock is a Media group and lays out in light and dark', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    for (final dark in [false, true]) {
      await _pumpDock(
        tester,
        repo: repo,
        scheduler: scheduler,
        sink: sink,
        dark: dark,
        compact: true,
        size: const Size(360, 800),
      );
      expect(
        find.bySemanticsLabel(RemoteStrings.mediaGroupLabel),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }
    handle.dispose();
  });
}
