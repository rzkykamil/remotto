import 'package:flutter/material.dart';

import 'svg_path.dart';

/// Icon geometry as SVG path `d` strings on a 24 x 24 viewBox. Each entry is
/// one path element, so a circle or line from the artboards is written as its
/// own entry or as extra subpaths of one entry.
final class RIconData {
  const RIconData(this.paths);

  final List<String> paths;
}

/// Parsed paths per [RIconData], so each icon is parsed once.
final _pathCache = Expando<List<Path>>('RIconData paths');

List<Path> _pathsOf(RIconData data) {
  return _pathCache[data] ??= [for (final d in data.paths) parseSvgPath(d)];
}

/// Line icon drawn from SVG path data (`design/export/artboards/`).
///
/// Strokes are round-capped and round-joined, and [strokeWidth] is in viewBox
/// units, so it scales with [size] like the SVG does. The icon is decorative,
/// so it is excluded from Semantics; the owning control carries the label.
final class RIcon extends StatelessWidget {
  const RIcon(
    this.data, {
    super.key,
    required this.size,
    required this.color,
    this.strokeWidth = 2,
  });

  final RIconData data;
  final double size;
  final Color color;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _RIconPainter(
            data: data,
            color: color,
            strokeWidth: strokeWidth,
          ),
        ),
      ),
    );
  }
}

final class _RIconPainter extends CustomPainter {
  const _RIconPainter({
    required this.data,
    required this.color,
    required this.strokeWidth,
  });

  final RIconData data;
  final Color color;
  final double strokeWidth;

  static const double _viewBox = 24;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / _viewBox;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    canvas.save();
    canvas.scale(scale, size.height / _viewBox);
    for (final path in _pathsOf(data)) {
      canvas.drawPath(path, paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_RIconPainter oldDelegate) {
    return oldDelegate.data != data ||
        oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}
