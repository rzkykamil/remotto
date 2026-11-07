import 'package:flutter/material.dart';

import '../core/theme/theme_extensions.dart';
import '../core/theme/tokens.g.dart';

/// Shown instead of the number while no volume is known.
const String _unknownValue = '—';

/// Size of the "%" sign relative to the number (C05: 0.32x). Not a token.
const double _percentScale = 0.32;

/// Number size at 360 dp wide (C05, C10). Not a token.
const double _compactSize = 108;

/// Number size on a short screen, under 700 dp tall (C10). Not a token.
const double _shortSize = 96;

/// Text scale cap of the readout (plan T5). The number must stay on one line.
const double _maxTextScale = 1.3;

/// Colour state of the number (C05).
enum VolumeReadoutTone {
  /// Idle: `fg.primary`.
  normal,

  /// Slider held: accent text.
  dragging,

  /// Muted or disabled: `fg.secondary`.
  dim,
}

/// Big laptop volume number with an optional hint below it (`design/components.md`
/// C05). Pure UI primitive: the caller maps state to [value], [hint] and [tone].
///
/// [value] null shows an em dash. A null or empty [hint] takes no space.
/// Excluded from Semantics: the slider already announces the value.
final class VolumeReadout extends StatelessWidget {
  const VolumeReadout({
    super.key,
    required this.value,
    required this.hint,
    this.tone = VolumeReadoutTone.normal,
    this.compact = false,
    this.short = false,
  });

  /// Level 0 to 100, or null while unknown.
  final int? value;

  /// Hint text under the number. Null or empty hides it.
  final String? hint;

  final VolumeReadoutTone tone;

  /// 360 dp wide layout: 108 sp number.
  final bool compact;

  /// Screen under 700 dp tall: 96 sp number. Wins over [compact].
  final bool short;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final spec = RType.displayVolume;
    final size = short ? _shortSize : (compact ? _compactSize : spec.size);
    final color = switch (tone) {
      VolumeReadoutTone.normal => scheme.onSurface,
      VolumeReadoutTone.dragging => context.accent.text,
      VolumeReadoutTone.dim => scheme.onSurfaceVariant,
    };
    final numberStyle = TextStyle(
      fontFamily: spec.family,
      fontSize: size,
      fontWeight: spec.weight,
      height: spec.height,
      // The spec gives letter spacing in sp at its own size (-0.04em).
      letterSpacing: spec.letterSpacing / spec.size * size,
      fontFeatures: const [FontFeature.tabularFigures()],
      color: color,
    );
    final text = hint;

    return ExcludeSemantics(
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: _maxTextScale,
        // Scales down instead of overflowing when the area is short.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text.rich(
                TextSpan(
                  style: numberStyle,
                  children: [
                    TextSpan(text: value == null ? _unknownValue : '$value'),
                    TextSpan(
                      text: '%',
                      style: TextStyle(
                        fontSize: size * _percentScale,
                        letterSpacing: 0,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
              ),
              if (text != null && text.isNotEmpty) ...[
                const SizedBox(height: RSpace.s1),
                Text(
                  text,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.labelLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
