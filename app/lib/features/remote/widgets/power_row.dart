import 'package:flutter/material.dart';

import '../../../core/strings/power_strings.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../ui/glass_key.dart';
import '../../../ui/r_icon.dart';
import '../../../ui/r_icons_data.dart';
import '../data/power_repository.dart';

/// Gap between the three power keys (`design/export/artboards/Remote.dc.html`,
/// `gap: 10px`). Not a design token.
const double _keyGap = 10;

/// Glyph size of the power keys (artboard svg 17). Not a design token.
const double _powerIconSize = 17;

/// Power row of SCR-010 (`design/components.md` C09): Sleep, Restart, and
/// Matikan as three [GlassKey]s in one row.
///
/// The row is neutral and sits above the volume panel. A tap does not run the
/// command: it reports the action through [onSelected], and the confirm flow
/// (C11) decides what happens next. [enabled] false disables all three keys.
final class PowerRow extends StatelessWidget {
  const PowerRow({super.key, required this.enabled, required this.onSelected});

  /// False disables every key and [onSelected] is never called.
  final bool enabled;

  /// Called with the tapped action.
  final ValueChanged<PowerAction> onSelected;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _key(
            context,
            action: PowerAction.sleep,
            label: PowerStrings.rowSleep,
            semanticsLabel: PowerStrings.semSleep,
            icon: RIcons.moon,
          ),
        ),
        const SizedBox(width: _keyGap),
        Expanded(
          child: _key(
            context,
            action: PowerAction.restart,
            label: PowerStrings.rowRestart,
            semanticsLabel: PowerStrings.semRestart,
            icon: RIcons.restart,
          ),
        ),
        const SizedBox(width: _keyGap),
        Expanded(
          child: _key(
            context,
            action: PowerAction.shutdown,
            label: PowerStrings.rowShutdown,
            semanticsLabel: PowerStrings.semShutdown,
            icon: RIcons.power,
          ),
        ),
      ],
    );
  }

  Widget _key(
    BuildContext context, {
    required PowerAction action,
    required String label,
    required String semanticsLabel,
    required RIconData icon,
  }) {
    final color = enabled
        ? Theme.of(context).colorScheme.onSurface
        : context.control.fgDisabled;

    return GlassKey(
      semanticsLabel: semanticsLabel,
      onPressed: enabled ? () => onSelected(action) : null,
      variant: GlassKeyVariant.glass,
      size: GlassKeySize.power,
      icon: RIcon(icon, size: _powerIconSize, color: color),
      label: label,
    );
  }
}
