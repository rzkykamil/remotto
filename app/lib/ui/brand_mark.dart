import 'package:flutter/material.dart';

import '../core/strings/strings.dart';
import '../core/theme/theme_extensions.dart';
import '../core/theme/tokens.g.dart';
import 'glass_panel.dart';
import 'r_icon.dart';

/// Diameter of the gradient mark at Q01 (`design/export/artboards/Pairing-light.dc.html`).
const double _markDiameter = 44;

/// Edge stroke width of the non-glass icon circle.
const double _discEdgeWidth = 1;

const double _glassDiameter = 96;
const double _glassIconSize = 40;
const double _glassStroke = 1.8;
const double _chipDiameter = 80;
const double _chipIconSize = 36;

/// Remotto mark: accent gradient circle and wordmark, above the Q01 title.
final class BrandMark extends StatelessWidget {
  const BrandMark({super.key});

  @override
  Widget build(BuildContext context) {
    final accent = context.accent;
    final primary = Theme.of(context).colorScheme.primary;
    final wordmark = Theme.of(context).textTheme.titleLarge;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [accent.highlight, primary],
            ),
          ),
          child: const SizedBox.square(dimension: _markDiameter),
        ),
        const SizedBox(width: RSpace.s3),
        Text(
          AppStrings.appName,
          style: wordmark?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

/// Circle containing a large icon. The icon is decorative; the title on the screen explains it.
final class IconDisc extends StatelessWidget {
  const IconDisc({
    super.key,
    required this.icon,
    required this.diameter,
    required this.iconSize,
    this.strokeWidth = 2,
    this.glass = false,
  });

  /// Camera icon in a 96 dp glass circle (Q02).
  const IconDisc.glassLarge({super.key, required this.icon})
    : diameter = _glassDiameter,
      iconSize = _glassIconSize,
      strokeWidth = _glassStroke,
      glass = true;

  /// Icon in an 80 dp chip circle, no blur (Q05).
  const IconDisc.chipLarge({super.key, required this.icon})
    : diameter = _chipDiameter,
      iconSize = _chipIconSize,
      strokeWidth = 2,
      glass = false;

  final RIconData icon;
  final double diameter;
  final double iconSize;
  final double strokeWidth;

  /// True uses [GlassPanel] (blur). False uses chip content without blur.
  final bool glass;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurface;
    final glassTokens = context.glass;
    final glyph = RIcon(
      icon,
      size: iconSize,
      color: color,
      strokeWidth: strokeWidth,
    );

    if (glass) {
      return SizedBox.square(
        dimension: diameter,
        child: GlassPanel(
          variant: GlassPanelVariant.pill,
          child: Center(child: glyph),
        ),
      );
    }

    return SizedBox.square(
      dimension: diameter,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: glassTokens.chip,
          border: Border.all(color: glassTokens.edge, width: _discEdgeWidth),
        ),
        child: Center(child: glyph),
      ),
    );
  }
}
