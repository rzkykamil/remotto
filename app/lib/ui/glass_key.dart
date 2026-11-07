import 'package:flutter/material.dart';

import '../core/theme/theme_extensions.dart';
import '../core/theme/tokens.g.dart';
import 'glass_panel.dart';
import 'pressable.dart';

/// Visual variant of a [GlassKey] (`design/components.md` C02).
enum GlassKeyVariant {
  /// Stands alone on the backdrop: blurred glass (dock). Uses [GlassPanel].
  glass,

  /// Inside a panel: tinted capsule with edge and highlight, no blur.
  chip,

  /// Inside a dock: transparent until pressed.
  ghost,

  /// Primary non-accent action: filled with the foreground color.
  strong,

  /// Main action of a screen (C02 `.key.acc`): accent gradient, accent shadow,
  /// no blur. Use once per screen.
  accent,
}

/// Key size, mapped to the token scale. There is no 64 dp token, so the
/// 64 dp size from C02 is not offered (decision K9).
enum GlassKeySize { touch, power, control, action, media }

double _heightOf(GlassKeySize size) => switch (size) {
  GlassKeySize.touch => RSize.touchMin,
  GlassKeySize.power => RSize.power,
  GlassKeySize.control => RSize.control,
  GlassKeySize.action => RSize.action,
  GlassKeySize.media => RSize.media,
};

/// Accent key shadow: 0 10px 28px `accent.shadow` (C02 `.key.acc`).
/// Not a token, like the glass shadow in `GlassPanel`.
const Offset _accentShadowOffset = Offset(0, 10);
const double _accentShadowBlur = 28;

/// Capsule button (`design/components.md` C02).
///
/// Built on [Pressable], so press scale, haptic, focus ring, and Semantics
/// come from the same primitive. Height is at least [size]; a label may wrap
/// to two lines and grow the height. Use [GlassKeyVariant.glass] only where
/// no other blurred surface is on the same area, since [GlassPanel] blurs.
/// Chips inside a [GlassPanel] must use [GlassKeyVariant.chip] (no blur).
final class GlassKey extends StatelessWidget {
  const GlassKey({
    super.key,
    required this.semanticsLabel,
    this.onPressed,
    this.icon,
    this.label,
    this.variant = GlassKeyVariant.glass,
    this.size = GlassKeySize.control,
    this.toggled,
    this.semanticsHint,
  }) : assert(
         icon != null || label != null,
         'GlassKey needs an icon, a label, or both.',
       );

  final String semanticsLabel;

  /// Null makes the key disabled.
  final VoidCallback? onPressed;

  /// Generic icon widget. M0 does not provide icons; later modules pass them.
  final Widget? icon;
  final String? label;
  final GlassKeyVariant variant;
  final GlassKeySize size;

  /// Null for a plain key; true/false for a toggle key (for example mute).
  final bool? toggled;
  final String? semanticsHint;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      semanticsLabel: semanticsLabel,
      semanticsHint: semanticsHint,
      onPressed: onPressed,
      toggled: toggled,
      focusRingRadius: RRadius.full,
      builder: (context, pressed) => _capsule(context, pressed: pressed),
    );
  }

  Widget _capsule(BuildContext context, {required bool pressed}) {
    final scheme = Theme.of(context).colorScheme;
    final glass = context.glass;
    final control = context.control;
    final enabled = onPressed != null;
    final height = _heightOf(size);
    final pressedTint = pressed ? glass.chipPressed : Colors.transparent;

    switch (variant) {
      case GlassKeyVariant.glass:
        final color = enabled ? scheme.onSurface : control.fgDisabled;
        return GlassPanel(
          variant: GlassPanelVariant.dock,
          child: ColoredBox(
            color: enabled ? pressedTint : glass.chipDisabled,
            child: _body(context, color: color, height: height),
          ),
        );
      case GlassKeyVariant.chip:
        final color = enabled ? scheme.onSurface : control.fgDisabled;
        return _surface(
          fill: enabled ? glass.chip : glass.chipDisabled,
          overlay: pressedTint,
          edge: glass.edge,
          highlight: glass.highlight,
          child: _body(context, color: color, height: height),
        );
      case GlassKeyVariant.ghost:
        final color = enabled ? scheme.onSurface : control.fgDisabled;
        return _surface(
          fill: Colors.transparent,
          overlay: pressedTint,
          child: _body(context, color: color, height: height),
        );
      case GlassKeyVariant.strong:
        return _surface(
          fill: enabled ? scheme.onSurface : control.fgDisabled,
          overlay: pressedTint,
          child: _body(context, color: scheme.surface, height: height),
        );
      case GlassKeyVariant.accent:
        return _accent(context, enabled: enabled, height: height);
    }
  }

  /// Accent key: gradient `accent.highlight` to `ColorScheme.primary`
  /// (`accent.default`), text `accent.on`, shadow `accent.shadow`. Pressed
  /// feedback is the scale from [Pressable] only, so no tint is laid over the
  /// gradient. Disabled drops the gradient and shadow.
  Widget _accent(
    BuildContext context, {
    required bool enabled,
    required double height,
  }) {
    final accent = context.accent;
    final control = context.control;
    final glass = context.glass;
    final primary = Theme.of(context).colorScheme.primary;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: enabled ? null : glass.chipDisabled,
        gradient: enabled
            ? LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [accent.highlight, primary],
              )
            : null,
        borderRadius: BorderRadius.circular(RRadius.full),
        boxShadow: enabled
            ? [
                BoxShadow(
                  color: accent.shadow,
                  offset: _accentShadowOffset,
                  blurRadius: _accentShadowBlur,
                ),
              ]
            : null,
      ),
      child: _body(
        context,
        color: enabled
            ? Theme.of(context).colorScheme.onPrimary
            : control.fgDisabled,
        height: height,
      ),
    );
  }

  /// Capsule frame: fill, optional 1 dp edge and top highlight, clipped to a
  /// full radius. No blur.
  Widget _surface({
    required Color fill,
    required Color overlay,
    required Widget child,
    Color? edge,
    Color? highlight,
  }) {
    final radius = BorderRadius.circular(RRadius.full);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: radius,
        border: edge == null
            ? null
            : Border.all(color: edge, width: RComponent.glassPanelEdgeWidth),
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          children: [
            if (highlight != null)
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: RComponent.glassPanelEdgeWidth,
                child: ColoredBox(color: highlight),
              ),
            ColoredBox(color: overlay, child: child),
          ],
        ),
      ),
    );
  }

  /// Icon and label row, centered, at least a square of [height].
  Widget _body(
    BuildContext context, {
    required Color color,
    required double height,
  }) {
    final text = label;
    final style = (Theme.of(context).textTheme.labelLarge ?? const TextStyle())
        .copyWith(color: color);
    final icon = this.icon;

    return ConstrainedBox(
      constraints: BoxConstraints(minWidth: height, minHeight: height),
      child: Padding(
        padding: text == null
            ? EdgeInsets.zero
            : const EdgeInsets.symmetric(horizontal: RSpace.s5),
        child: IconTheme.merge(
          data: IconThemeData(color: color),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ?icon,
              if (icon != null && text != null)
                const SizedBox(width: RSpace.s2),
              if (text != null)
                Flexible(
                  child: Text(
                    text,
                    style: style,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
