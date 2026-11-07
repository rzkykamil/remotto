import 'package:flutter/material.dart';

import '../core/theme/theme_extensions.dart';
import '../core/theme/tokens.g.dart';
import 'pressable.dart';

/// Accent text link, a secondary action below the primary button (C08, Q01, Q02,
/// Q05). `accent.text` semibold text, minimum touch height `RSize.touchMin`.
///
/// On top of [Pressable]: no scale and no haptic, per the haptic table in
/// `design/design-system.md` (links are not listed there).
final class RLinkButton extends StatelessWidget {
  const RLinkButton({
    super.key,
    required this.label,
    required this.semanticsLabel,
    this.onPressed,
  });

  final String label;
  final String semanticsLabel;

  /// Null makes the link disabled.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      semanticsLabel: semanticsLabel,
      onPressed: onPressed,
      haptic: PressHaptic.none,
      pressedScale: 1.0,
      focusRingRadius: RRadius.sm,
      builder: (context, pressed) {
        final enabled = onPressed != null;
        final style =
            (Theme.of(context).textTheme.labelLarge ?? const TextStyle())
                .copyWith(
                  color: enabled
                      ? context.accent.text
                      : context.control.fgDisabled,
                  fontWeight: FontWeight.w600,
                );

        return ConstrainedBox(
          constraints: const BoxConstraints(minHeight: RSize.touchMin),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: RSpace.s3),
            child: Center(
              widthFactor: 1,
              child: Text(label, style: style, textAlign: TextAlign.center),
            ),
          ),
        );
      },
    );
  }
}
