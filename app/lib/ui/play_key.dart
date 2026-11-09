import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme/reduced_motion.dart';
import '../core/theme/theme_extensions.dart';
import '../core/theme/tokens.g.dart';
import 'glass_key.dart';
import 'r_icon.dart';
import 'r_icons_data.dart';

/// Glyph size inside the play key (`design/components.md` C03). No token.
const double _iconSize = 36;

/// Ring sits 7 dp outside the key edge (`States-light.dc.html` inset -7px).
const double _ringInset = 7;

/// Rotation of the ring in degrees, from the artboard (`rotate(20deg)`).
const double _ringTiltDegrees = 20;

/// The visible part of the ring is a 180 degree arc: the top and left border
/// sides, with the right and bottom sides transparent. Measured clockwise
/// from +x, so the arc runs from 135 to 315 degrees before the tilt.
const double _ringArcStartDegrees = 135;
const double _ringArcSweepDegrees = 180;

/// Time for one full turn of the processing ring. Not in the design tokens.
const Duration _ringTurn = Duration(milliseconds: 900);

/// Nudges the play glyph right so it looks centred (`margin-left: 4px`).
const double _playGlyphNudge = RSpace.s1;

/// Toggle key for play and pause: the single accent element of the media dock
/// (`design/components.md` C03).
///
/// Pure UI primitive: the caller owns the state. [playing] picks the glyph,
/// [ringVisible] shows the processing ring, and [onPressed] null disables the
/// key. While [processing] is true the Semantics hint is [processingHint].
final class PlayKey extends StatelessWidget {
  const PlayKey({
    super.key,
    required this.playing,
    required this.semanticsLabel,
    required this.processingHint,
    this.processing = false,
    this.ringVisible = false,
    this.onPressed,
    this.compact = false,
  });

  /// True shows the pause glyph, false shows play.
  final bool playing;

  /// True while a command is in flight. Only changes the Semantics hint.
  final bool processing;

  /// True draws the processing ring. The caller decides when (C03: after
  /// `duration.processingHint`).
  final bool ringVisible;

  /// Null disables the key.
  final VoidCallback? onPressed;

  /// Uses the 88 dp size (360 dp screens) instead of 96 dp.
  final bool compact;

  final String semanticsLabel;

  /// Semantics hint announced while [processing] is true.
  final String processingHint;

  @override
  Widget build(BuildContext context) {
    final size = compact ? GlassKeySize.playCompact : GlassKeySize.play;
    final iconColor = onPressed == null
        ? context.control.fgDisabled
        : Theme.of(context).colorScheme.onPrimary;

    final glyph = playing ? RIcons.pause : RIcons.play;

    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        GlassKey(
          semanticsLabel: semanticsLabel,
          semanticsHint: processing ? processingHint : null,
          onPressed: onPressed,
          variant: GlassKeyVariant.accent,
          size: size,
          icon: Padding(
            padding: EdgeInsets.only(left: playing ? 0 : _playGlyphNudge),
            child: RIcon(
              glyph,
              size: _iconSize,
              color: iconColor,
              strokeWidth: 0,
              filled: true,
            ),
          ),
        ),
        if (ringVisible)
          Positioned(
            key: const ValueKey('play-key-ring'),
            left: -_ringInset,
            top: -_ringInset,
            right: -_ringInset,
            bottom: -_ringInset,
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: _ProcessingRing(color: context.accent.text),
              ),
            ),
          ),
      ],
    );
  }
}

/// Spinning arc. Turns continuously unless reduced motion is on, in which
/// case it stays still at the tilted start position.
final class _ProcessingRing extends StatefulWidget {
  const _ProcessingRing({required this.color});

  final Color color;

  @override
  State<_ProcessingRing> createState() => _ProcessingRingState();
}

final class _ProcessingRingState extends State<_ProcessingRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: _ringTurn,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (ReducedMotion.of(context).enabled) {
      _spin
        ..stop()
        ..value = 0;
    } else if (!_spin.isAnimating) {
      _spin.repeat();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _spin,
      builder: (context, _) => CustomPaint(
        painter: _RingPainter(color: widget.color, turn: _spin.value),
        size: Size.infinite,
      ),
    );
  }
}

final class _RingPainter extends CustomPainter {
  const _RingPainter({required this.color, required this.turn});

  final Color color;

  /// Fraction of a full turn, 0 to 1.
  final double turn;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = RComponent.playKeyRingWidth
      ..strokeCap = StrokeCap.butt;

    // CSS borders are drawn inside the box, so the stroke centre sits half a
    // stroke width in from the edge.
    final rect = (Offset.zero & size).deflate(RComponent.playKeyRingWidth / 2);
    final startDegrees = _ringArcStartDegrees + _ringTiltDegrees + turn * 360;

    canvas.drawArc(
      rect,
      _toRadians(startDegrees),
      _toRadians(_ringArcSweepDegrees),
      false,
      paint,
    );
  }

  static double _toRadians(double degrees) => degrees * math.pi / 180;

  @override
  bool shouldRepaint(_RingPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.turn != turn;
}
