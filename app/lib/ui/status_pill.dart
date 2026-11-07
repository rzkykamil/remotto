import 'package:flutter/material.dart';

import '../core/theme/reduced_motion.dart';
import '../core/theme/theme_extensions.dart';
import '../core/theme/tokens.g.dart';
import 'glass_panel.dart';
import 'r_icon.dart';
import 'r_icons_data.dart';

/// Status pill variant (`design/components.md` C06).
enum StatusPillVariant { online, back, connecting, offline, off }

/// Height of the C06 pill. Not a token: the value comes from `States-light.dc.html`.
const double _pillHeight = 28;

/// Icon and indicator inside the pill, per the artboard (14 dp).
const double _indicatorSize = 14;

/// Stroke width of the `connecting` ring (artboard 2 dp).
const double _ringWidth = 2;

/// Remote status pill (`design/components.md` C06).
///
/// Visual primitive: text and Semantics label come from the caller, so
/// this widget does not know copy. [label] may contain uptime and is not
/// announced. [semanticsLabel] is static text per variant (without uptime)
/// and is read as a `liveRegion` when the variant changes.
///
/// Variant changes use the `RMotion.status` crossfade; when reduced motion is
/// active, the change is immediate with no animation.
final class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.variant,
    required this.label,
    required this.semanticsLabel,
  });

  final StatusPillVariant variant;
  final String label;
  final String semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final reduced = ReducedMotion.of(context).enabled;

    return Semantics(
      container: true,
      liveRegion: true,
      label: semanticsLabel,
      child: ExcludeSemantics(
        child: AnimatedSwitcher(
          duration: reduced ? Duration.zero : RMotion.status,
          child: KeyedSubtree(
            key: ValueKey(variant),
            child: GlassPanel(
              variant: GlassPanelVariant.pill,
              padding: const EdgeInsets.symmetric(horizontal: RSpace.s3),
              child: SizedBox(
                height: _pillHeight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _indicator(context),
                    const SizedBox(width: RSpace.s2),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _labelStyle(context),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  TextStyle _labelStyle(BuildContext context) {
    final base = Theme.of(context).textTheme.labelSmall ?? const TextStyle();
    return base.copyWith(color: _labelColor(context));
  }

  Color _labelColor(BuildContext context) => switch (variant) {
    StatusPillVariant.back => context.status.success,
    StatusPillVariant.connecting => context.status.warning,
    _ => Theme.of(context).colorScheme.onSurfaceVariant,
  };

  Widget _indicator(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = context.status;

    return switch (variant) {
      StatusPillVariant.online => _dot(color: status.success),
      StatusPillVariant.connecting => _ring(color: status.warning),
      StatusPillVariant.back => RIcon(
        RIcons.check,
        size: _indicatorSize,
        color: status.success,
        strokeWidth: 2.6,
      ),
      StatusPillVariant.offline => RIcon(
        RIcons.wifiOff,
        size: _indicatorSize,
        color: scheme.onSurfaceVariant,
        strokeWidth: 2.4,
      ),
      StatusPillVariant.off => RIcon(
        RIcons.power,
        size: _indicatorSize,
        color: scheme.onSurfaceVariant,
      ),
    };
  }

  /// Solid dot, `online` indicator.
  Widget _dot({required Color color}) => DecoratedBox(
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    child: const SizedBox.square(dimension: RSpace.s2),
  );

  /// Empty ring, `connecting` indicator.
  Widget _ring({required Color color}) => DecoratedBox(
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(color: color, width: _ringWidth),
    ),
    child: const SizedBox.square(dimension: RSpace.s2),
  );
}
