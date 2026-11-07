import 'package:flutter/material.dart';

/// Default frame side (`design/components.md` C16: 248 dp).
const double _defaultSize = 248;

/// Length of each corner arm from the frame edge.
const double _armLength = 44;

/// Outer radius of the rounded corner, equal to half the corner box in the artboard.
const double _outerRadius = 22;

/// Corner stroke thickness (artboard: 4 dp).
const double _strokeWidth = 4;

/// 4-corner frame for the scan area (`design/components.md` C16). Drawing
/// only; color comes from the caller (fg.primary normal, accent.text when the QR is wrong).
///
/// Decorative, so excluded from Semantics. The hint and banner are what is read out.
final class QrViewfinderFrame extends StatelessWidget {
  const QrViewfinderFrame({
    super.key,
    required this.color,
    this.size = _defaultSize,
  });

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: _CornerPainter(color: color)),
      ),
    );
  }
}

final class _CornerPainter extends CustomPainter {
  const _CornerPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    // One top-left corner, then mirrored for the other three.
    final inset = _strokeWidth / 2;
    final radius = _outerRadius - inset;
    final corner = Path()
      ..moveTo(inset, _armLength)
      ..lineTo(inset, inset + radius)
      ..arcToPoint(
        Offset(inset + radius, inset),
        radius: Radius.circular(radius),
        clockwise: true,
      )
      ..lineTo(_armLength, inset);

    final w = size.width;
    final h = size.height;
    final mirrors = <(Offset, Offset)>[
      (Offset.zero, const Offset(1, 1)),
      (Offset(w, 0), const Offset(-1, 1)),
      (Offset(0, h), const Offset(1, -1)),
      (Offset(w, h), const Offset(-1, -1)),
    ];
    for (final (origin, flip) in mirrors) {
      canvas.save();
      canvas.translate(origin.dx, origin.dy);
      canvas.scale(flip.dx, flip.dy);
      canvas.drawPath(corner, paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_CornerPainter oldDelegate) => oldDelegate.color != color;
}
