import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:remotto/ui/r_icons_data.dart';
import 'package:remotto/ui/r_icon.dart';
import 'package:remotto/ui/svg_path.dart';

/// Tight bounds from sampled points. [Path.getBounds] includes curve control
/// points, so arcs and curves overshoot it.
Rect _tightBounds(Path path) {
  var minX = double.infinity;
  var minY = double.infinity;
  var maxX = -double.infinity;
  var maxY = -double.infinity;
  for (final metric in path.computeMetrics()) {
    final steps = math.max(200, (metric.length * 20).ceil());
    for (var k = 0; k <= steps; k++) {
      final tangent = metric.getTangentForOffset(metric.length * k / steps);
      if (tangent == null) continue;
      final p = tangent.position;
      minX = math.min(minX, p.dx);
      minY = math.min(minY, p.dy);
      maxX = math.max(maxX, p.dx);
      maxY = math.max(maxY, p.dy);
    }
  }
  return Rect.fromLTRB(minX, minY, maxX, maxY);
}

void _expectBounds(String d, Rect expected) {
  final bounds = _tightBounds(parseSvgPath(d));
  const tol = 0.05;
  expect(bounds.left, closeTo(expected.left, tol), reason: '$d left');
  expect(bounds.top, closeTo(expected.top, tol), reason: '$d top');
  expect(bounds.right, closeTo(expected.right, tol), reason: '$d right');
  expect(bounds.bottom, closeTo(expected.bottom, tol), reason: '$d bottom');
}

void main() {
  group('line commands', () {
    test('absolute M, L, H, V and Z', () {
      _expectBounds('M2 3 L10 3 V7 H4 Z', const Rect.fromLTRB(2, 3, 10, 7));
    });

    test('relative m, l, v, h and z', () {
      _expectBounds('m2 3 l8 0 v4 h-8z', const Rect.fromLTRB(2, 3, 10, 7));
    });

    test('relative m after a point moves from the current point', () {
      // The moveTo point (6, 6) is the start of the drawn segment; the path
      // metrics only cover drawn geometry, so the bounds start at (6, 6).
      _expectBounds('M5 5 m1 1 l1 1', const Rect.fromLTRB(6, 6, 7, 7));
    });

    test('smooth cubic S reflects the previous control point', () {
      // The first C bulges down to y = 7.5. The S first control point reflects
      // (10, 10) about (10, 0) to (10, -10), so the second bulge goes up to
      // y = -7.5.
      _expectBounds(
        'M0 0 C0 10 10 10 10 0 s10 -10 10 0',
        const Rect.fromLTRB(0, -7.5, 20, 7.5),
      );
    });

    test('implicit lineto after M, absolute and relative', () {
      _expectBounds('M0 0 10 0 10 10', const Rect.fromLTRB(0, 0, 10, 10));
      _expectBounds('m1 1 2 2', const Rect.fromLTRB(1, 1, 3, 3));
    });

    test('compact numbers: sign and dot separate numbers', () {
      _expectBounds('M10-5l-5.5.5', const Rect.fromLTRB(4.5, -5, 10, -4.5));
    });
  });

  group('cubic curve', () {
    test('absolute C reaches its midpoint extremum at t = 0.5', () {
      _expectBounds(
        'M0 0 C0 10 10 10 10 0',
        const Rect.fromLTRB(0, 0, 10, 7.5),
      );
    });

    test('relative c gives the same curve', () {
      _expectBounds(
        'M0 0 c0 10 10 10 10 0',
        const Rect.fromLTRB(0, 0, 10, 7.5),
      );
    });
  });

  group('arc commands', () {
    test('sweep flag 1 bends the semicircle up (negative y)', () {
      _expectBounds(
        'M0 0 A10 10 0 0 1 20 0',
        const Rect.fromLTRB(0, -10, 20, 0),
      );
    });

    test('sweep flag 0 bends the semicircle down (positive y)', () {
      _expectBounds(
        'M0 0 A10 10 0 0 0 20 0',
        const Rect.fromLTRB(0, 0, 20, 10),
      );
    });

    test('relative a matches absolute A', () {
      _expectBounds(
        'M0 0 a10 10 0 0 1 20 0',
        const Rect.fromLTRB(0, -10, 20, 0),
      );
    });

    test('two half arcs form a full circle (large-arc flag)', () {
      _expectBounds(
        'M3 12a9 9 0 1 0 18 0a9 9 0 1 0-18 0',
        const Rect.fromLTRB(3, 3, 21, 21),
      );
    });

    test('compact flags "1010" read as large=1 sweep=0 then x=10', () {
      _expectBounds('M0 0a5 5 0 1010 0', const Rect.fromLTRB(0, 0, 10, 5));
    });
  });

  group('invalid input', () {
    test('path must start with M or m', () {
      expect(() => parseSvgPath('L5 5'), throwsFormatException);
    });

    test('unknown command letter is rejected', () {
      expect(() => parseSvgPath('M0 0 X1 1'), throwsFormatException);
    });

    test('incomplete coordinate pair is rejected', () {
      expect(() => parseSvgPath('M0'), throwsFormatException);
    });

    test('numbers after Z without a command are rejected', () {
      expect(() => parseSvgPath('M0 0 Z 5 5'), throwsFormatException);
    });

    test('arc flag other than 0 or 1 is rejected', () {
      expect(() => parseSvgPath('M0 0 A5 5 0 2 0 10 0'), throwsFormatException);
    });
  });

  group('RIcons data', () {
    final icons = <String, RIconData>{
      'back': RIcons.back,
      'flashlight': RIcons.flashlight,
      'camera': RIcons.camera,
      'cameraOff': RIcons.cameraOff,
      'wifi': RIcons.wifi,
      'wifiOff': RIcons.wifiOff,
      'key': RIcons.key,
      'plug': RIcons.plug,
      'check': RIcons.check,
      'alertTriangle': RIcons.alertTriangle,
      'alertCircle': RIcons.alertCircle,
      'eye': RIcons.eye,
      'settingsSliders': RIcons.settingsSliders,
      'power': RIcons.power,
      'skipPrev': RIcons.skipPrev,
      'skipNext': RIcons.skipNext,
      'play': RIcons.play,
      'pause': RIcons.pause,
    };

    test('media icons have the expected path counts', () {
      expect(RIcons.skipPrev.paths, hasLength(2));
      expect(RIcons.skipNext.paths, hasLength(2));
      expect(RIcons.play.paths, hasLength(1));
      expect(RIcons.pause.paths, hasLength(2));
    });

    test('every icon parses and its geometry stays inside the 24 x 24 viewBox', () {
      for (final entry in icons.entries) {
        for (final d in entry.value.paths) {
          final bounds = _tightBounds(parseSvgPath(d));
          // Horizontal or vertical lines have zero-width or zero-height bounds,
          // so check for drawn geometry instead of a non-empty rect.
          expect(
            parseSvgPath(d).computeMetrics(),
            isNotEmpty,
            reason: '${entry.key}: $d',
          );
          expect(bounds.left, greaterThanOrEqualTo(-0.05), reason: entry.key);
          expect(bounds.top, greaterThanOrEqualTo(-0.05), reason: entry.key);
          expect(bounds.right, lessThanOrEqualTo(24.05), reason: entry.key);
          expect(bounds.bottom, lessThanOrEqualTo(24.05), reason: entry.key);
        }
      }
    });
  });
}
