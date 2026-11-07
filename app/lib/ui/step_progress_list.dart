import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme/reduced_motion.dart';
import '../core/theme/theme_extensions.dart';
import '../core/theme/tokens.g.dart';
import 'glass_panel.dart';
import 'r_icon.dart';
import 'r_icons_data.dart';

/// State of one step in a [StepProgressList] (`design/components.md` C18).
enum StepProgressState { done, active, todo }

/// One row of a [StepProgressList].
final class StepProgressItem {
  const StepProgressItem({required this.label, required this.state});

  final String label;
  final StepProgressState state;
}

/// Ring width of the active step (artboard: 3 px border, right side transparent).
const double _ringStroke = 3;

/// Ring diameter of the active step.
const double _ringSize = RSpace.s4;

/// Dot diameter of a step that has not started.
const double _dotSize = RSpace.s3;

/// Dot stroke thickness of a step that has not started.
const double _dotStroke = 2;

/// Full rotation of the active step ring.
const Duration _ringPeriod = Duration(milliseconds: 900);

/// Width of the divider line between rows.
const double _dividerWidth = 1;

/// List of steps in one glass group (`design/components.md` C18).
///
/// Each row is [RSize.control] (56 dp) tall: a check for a completed step,
/// a spinning ring for the active step, a dot for a step that has not
/// started. The ring is still under reduced motion. The group is read as a
/// `liveRegion`, so step changes are announced.
final class StepProgressList extends StatelessWidget {
  const StepProgressList({super.key, required this.steps});

  final List<StepProgressItem> steps;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final status = context.status;
    final divider = context.glass.lowlight;
    final reduced = ReducedMotion.of(context).enabled;

    return Semantics(
      container: true,
      liveRegion: true,
      child: GlassPanel(
        padding: const EdgeInsets.symmetric(
          horizontal: RSpace.s5,
          vertical: RSpace.s2,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < steps.length; i++)
              DecoratedBox(
                decoration: BoxDecoration(
                  border: i == 0
                      ? null
                      : Border(
                          top: BorderSide(color: divider, width: _dividerWidth),
                        ),
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: RSize.control),
                  child: Row(
                    children: [
                      SizedBox.square(
                        dimension: RSpace.s6,
                        child: Center(
                          child: _StepMarker(
                            state: steps[i].state,
                            status: status,
                            reduced: reduced,
                            dotColor: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const SizedBox(width: RSpace.s3),
                      Expanded(
                        child: Text(
                          steps[i].label,
                          style: textTheme.bodyLarge?.copyWith(
                            fontWeight:
                                steps[i].state == StepProgressState.active
                                ? FontWeight.w600
                                : null,
                            color: steps[i].state == StepProgressState.todo
                                ? scheme.onSurfaceVariant
                                : scheme.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Status icon of one row: check, spinning ring, or empty dot.
final class _StepMarker extends StatelessWidget {
  const _StepMarker({
    required this.state,
    required this.status,
    required this.reduced,
    required this.dotColor,
  });

  final StepProgressState state;
  final StatusTokens status;
  final bool reduced;
  final Color dotColor;

  @override
  Widget build(BuildContext context) {
    return switch (state) {
      StepProgressState.done => RIcon(
        RIcons.check,
        size: RSpace.s6,
        color: status.success,
      ),
      StepProgressState.active => _SpinningRing(
        color: status.warning,
        spin: !reduced,
      ),
      StepProgressState.todo => SizedBox.square(
        dimension: _dotSize,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: dotColor, width: _dotStroke),
          ),
        ),
      ),
    };
  }
}

/// Three-quarter circle ring that spins continuously. With [spin] false
/// the ring is still (reduced motion).
final class _SpinningRing extends StatefulWidget {
  const _SpinningRing({required this.color, required this.spin});

  final Color color;
  final bool spin;

  @override
  State<_SpinningRing> createState() => _SpinningRingState();
}

final class _SpinningRingState extends State<_SpinningRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _ringPeriod,
  );

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant _SpinningRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    if (widget.spin) {
      if (!_controller.isAnimating) _controller.repeat();
    } else {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _controller,
      child: SizedBox.square(
        dimension: _ringSize,
        child: CustomPaint(painter: _RingPainter(color: widget.color)),
      ),
    );
  }
}

final class _RingPainter extends CustomPainter {
  const _RingPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = _ringStroke;
    final rect = Offset.zero & size;
    final arcRect = rect.deflate(stroke / 2);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    // Three-quarter circle: gap at the top right, like the artboard.
    canvas.drawArc(arcRect, -math.pi / 2, math.pi * 1.5, false, paint);
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) => oldDelegate.color != color;
}
