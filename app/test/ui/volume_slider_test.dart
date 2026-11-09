import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotto/ui/volume_slider.dart';

import '../support/test_app.dart';

/// Track width used by the tests. Left edge of the track is the widget's
/// left edge, so tap offsets are plain local dx values.
const double _width = 300;

const _handleKey = ValueKey('volume-slider-handle');
const _trackKey = ValueKey('volume-slider-track');

/// The slider's own Semantics widget, found by its label.
final _sliderSemantics = find.byWidgetPredicate(
  (w) => w is Semantics && w.properties.label == 'Volume',
);

final class _Log {
  final events = <String>[];
  int detents = 0;
  int limits = 0;
}

VolumeSlider _slider({
  required _Log log,
  int value = 35,
  bool muted = false,
  bool enabled = true,
  bool dragging = false,
  String semanticsValue = '35 persen',
  VoidCallback? onIncrease,
  VoidCallback? onDecrease,
}) => VolumeSlider(
  value: value,
  muted: muted,
  enabled: enabled,
  dragging: dragging,
  semanticsLabel: 'Volume',
  semanticsValue: semanticsValue,
  semanticsIncreasedValue: '40 persen',
  semanticsDecreasedValue: '30 persen',
  onIncrease: onIncrease,
  onDecrease: onDecrease,
  onChanged: (v) => log.events.add('changed:$v'),
  onChangeStart: (v) => log.events.add('start:$v'),
  onChangeEnd: (v) => log.events.add('end:$v'),
  onCancel: () => log.events.add('cancel'),
  onDetent: (_) => log.detents++,
  onLimit: () => log.limits++,
);

Future<void> _pump(
  WidgetTester tester,
  VolumeSlider slider, {
  bool dark = false,
}) => pumpApp(
  tester,
  SizedBox(width: _width, child: slider),
  dark: dark,
);

Offset _at(WidgetTester tester, double dx) {
  final topLeft = tester.getTopLeft(find.byType(VolumeSlider));
  final centre = tester.getCenter(find.byType(VolumeSlider));
  return Offset(topLeft.dx + dx, centre.dy);
}

void main() {
  group('levelFromDx', () {
    test('maps positions to 0 to 100 with rounding and clamping', () {
      expect(levelFromDx(0, _width), 0);
      expect(levelFromDx(150, _width), 50);
      expect(levelFromDx(_width, _width), 100);
      expect(levelFromDx(-10, _width), 0);
      expect(levelFromDx(_width + 40, _width), 100);
      expect(levelFromDx(1.4, _width), 0);
      expect(levelFromDx(1.6, _width), 1);
    });

    test('zero width gives 0', () {
      expect(levelFromDx(50, 0), 0);
    });
  });

  testWidgets('tap at left edge gives 0 with start, changed, end', (
    tester,
  ) async {
    final log = _Log();
    await _pump(tester, _slider(log: log));
    await tester.tapAt(_at(tester, 1));
    await tester.pump();
    expect(log.events, ['start:0', 'changed:0', 'end:0']);
  });

  testWidgets('tap at middle gives 50', (tester) async {
    final log = _Log();
    await _pump(tester, _slider(log: log));
    await tester.tapAt(_at(tester, 150));
    await tester.pump();
    expect(log.events, ['start:50', 'changed:50', 'end:50']);
  });

  testWidgets('tap at right edge gives 100', (tester) async {
    final log = _Log();
    await _pump(tester, _slider(log: log));
    await tester.tapAt(_at(tester, _width - 1));
    await tester.pump();
    expect(log.events, ['start:100', 'changed:100', 'end:100']);
  });

  testWidgets('horizontal drag emits start, ordered changes, then end', (
    tester,
  ) async {
    final log = _Log();
    await _pump(tester, _slider(log: log));
    final gesture = await tester.startGesture(_at(tester, 150));
    await gesture.moveBy(const Offset(30, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(30, 0));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(log.events, ['start:50', 'changed:60', 'changed:70', 'end:70']);
  });

  testWidgets('vertical drag calls nothing', (tester) async {
    final log = _Log();
    await _pump(tester, _slider(log: log));
    final gesture = await tester.startGesture(_at(tester, 150));
    await gesture.moveBy(const Offset(0, 40));
    await tester.pump();
    await gesture.moveBy(const Offset(0, 40));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(log.events, isEmpty);
  });

  testWidgets('disabled slider ignores taps and drags', (tester) async {
    final log = _Log();
    await _pump(tester, _slider(log: log, enabled: false));
    await tester.tapAt(_at(tester, 150));
    await tester.pump();
    final gesture = await tester.startGesture(_at(tester, 150));
    await gesture.moveBy(const Offset(60, 0));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(log.events, isEmpty);
  });

  testWidgets('detent and limit haptic callbacks fire during a drag', (
    tester,
  ) async {
    final log = _Log();
    await _pump(tester, _slider(log: log, value: 0));
    // Start at 0, drag to level 7: crosses 5 once (detent), no limit.
    final gesture = await tester.startGesture(_at(tester, 1));
    await gesture.moveBy(const Offset(20, 0));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(log.detents, 1);
    expect(log.limits, 0);
  });

  testWidgets('handle is hidden at 6 and shown at 7', (tester) async {
    final log = _Log();
    await _pump(tester, _slider(log: log, value: 6));
    expect(tester.widget<Opacity>(find.byKey(_handleKey)).opacity, 0);

    await _pump(tester, _slider(log: log, value: 7));
    expect(tester.widget<Opacity>(find.byKey(_handleKey)).opacity, 1);
  });

  testWidgets('track is 60 dp at rest and 68 dp while dragging', (
    tester,
  ) async {
    final log = _Log();
    await _pump(tester, _slider(log: log));
    expect(tester.getSize(find.byKey(_trackKey)).height, 60);

    await _pump(tester, _slider(log: log, dragging: true));
    expect(tester.getSize(find.byKey(_trackKey)).height, 68);
  });

  testWidgets('semantics expose slider role, value and actions', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    var ups = 0;
    var downs = 0;
    final log = _Log();
    await _pump(
      tester,
      _slider(log: log, onIncrease: () => ups++, onDecrease: () => downs++),
    );

    final node = tester.getSemantics(_sliderSemantics);
    final data = node.getSemanticsData();
    expect(data.flagsCollection.isSlider, isTrue);
    expect(node.value, '35 persen');
    expect(data.hasAction(SemanticsAction.increase), isTrue);
    expect(data.hasAction(SemanticsAction.decrease), isTrue);

    tester.semantics.performAction(
      find.semantics.byLabel('Volume'),
      SemanticsAction.increase,
    );
    tester.semantics.performAction(
      find.semantics.byLabel('Volume'),
      SemanticsAction.decrease,
    );
    expect(ups, 1);
    expect(downs, 1);
    handle.dispose();
  });

  testWidgets('semantics value does not change while dragging', (tester) async {
    final handle = tester.ensureSemantics();
    final log = _Log();
    await _pump(tester, _slider(log: log));
    await _pump(
      tester,
      _slider(log: log, dragging: true, value: 60, semanticsValue: '60 persen'),
    );
    expect(tester.getSemantics(_sliderSemantics).value, '35 persen');
    handle.dispose();
  });

  testWidgets('renders without overflow in light and dark themes', (
    tester,
  ) async {
    final log = _Log();
    await _pump(tester, _slider(log: log, muted: true));
    expect(tester.takeException(), isNull);
    await _pump(tester, _slider(log: log), dark: true);
    expect(tester.takeException(), isNull);
  });
}
