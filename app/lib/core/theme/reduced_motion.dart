import 'package:flutter/widgets.dart';
import 'package:remotto/core/theme/tokens.g.dart';

/// Chooses durations and curves that respect the platform's reduce-motion
/// setting (`MediaQuery.disableAnimations`).
///
/// Moments that must keep their motion are NOT routed through this helper:
/// the hold-to-confirm ring, the volume slider and status crossfades stay
/// as they are, because they are functional or already subtle.
final class ReducedMotion {
  const ReducedMotion(this.enabled);

  factory ReducedMotion.of(BuildContext context) =>
      ReducedMotion(MediaQuery.disableAnimationsOf(context));

  final bool enabled;

  /// Normal duration, or [RMotion.fast] when reduced motion is on.
  Duration duration(Duration normal) => enabled ? RMotion.fast : normal;

  /// Normal curve, or a linear curve when reduced motion is on.
  Curve curve(Curve normal) => enabled ? Curves.linear : normal;

  /// Normal press scale, or no scaling (1.0) when reduced motion is on.
  double pressedScale(double normal) => enabled ? 1.0 : normal;

  /// Normal slide distance in dp, or no slide when reduced motion is on.
  double slide(double dp) => enabled ? 0.0 : dp;
}
