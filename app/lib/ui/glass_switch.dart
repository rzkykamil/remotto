import 'package:flutter/material.dart';

import '../core/theme/reduced_motion.dart';
import '../core/theme/theme_extensions.dart';
import '../core/theme/tokens.g.dart';
import 'pressable.dart';
import 'r_icon.dart';
import 'r_icons_data.dart';

// Geometry from the Settings artboard (`design/export/artboards/`,
// `button[role=switch]` and its thumb `span`). Not tokens yet.
const double _trackHeight = 36;
const double _trackBorderWidth = 1;

/// Thumb sits 3 dp from the top and from the off-side edge.
const double _thumbSize = 28;
const double _thumbInset = 3;

/// Thumb left offset in the on state, measured inside the track border.
const double _thumbOnLeft = 27;
const double _thumbShadowOffsetY = 2;
const double _thumbShadowBlur = 6;

/// Icon inside the thumb: check (on) or strip (off), 24-unit viewBox stroke.
const double _thumbIconSize = 14;
const double _thumbIconStroke = 3;

/// Toggle switch (`design/components.md` C21).
///
/// Track [RSize.track] x 36 with a thumb that slides between the two ends.
/// On: accent track and check icon. Off: `control.switchOff` track and strip.
/// Built on [Pressable], so the whole 48 dp hit area toggles the value.
///
/// [onChanged] receives the opposite of [value]. Null disables the switch.
final class GlassSwitch extends StatelessWidget {
  const GlassSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    required this.semanticsLabel,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final control = context.control;
    final glass = context.glass;
    final reduced = ReducedMotion.of(context);
    // Reduced motion switches instantly instead of using the short fade.
    final duration = reduced.enabled ? Duration.zero : RMotion.status;
    final onChanged = this.onChanged;

    return Pressable(
      semanticsLabel: semanticsLabel,
      toggled: value,
      focusRingRadius: RRadius.full,
      onPressed: onChanged == null ? null : () => onChanged(!value),
      builder: (_, _) => Container(
        width: RSize.track,
        height: _trackHeight,
        decoration: BoxDecoration(
          color: value ? scheme.primary : control.switchOff,
          borderRadius: BorderRadius.circular(RRadius.full),
          border: Border.all(color: glass.edge, width: _trackBorderWidth),
        ),
        child: Stack(
          children: [
            AnimatedPositioned(
              duration: duration,
              curve: reduced.curve(RMotion.standard),
              top: _thumbInset,
              left: value ? _thumbOnLeft : _thumbInset,
              width: _thumbSize,
              height: _thumbSize,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: control.switchThumb,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: glass.shadow,
                      offset: const Offset(0, _thumbShadowOffsetY),
                      blurRadius: _thumbShadowBlur,
                    ),
                  ],
                ),
                child: Center(
                  child: value
                      ? RIcon(
                          RIcons.check,
                          size: _thumbIconSize,
                          color: scheme.primary,
                          strokeWidth: _thumbIconStroke,
                        )
                      : RIcon(
                          RIcons.minus,
                          size: _thumbIconSize,
                          color: scheme.onSurfaceVariant,
                          strokeWidth: _thumbIconStroke,
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
