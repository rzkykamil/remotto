import 'package:flutter/material.dart';

import '../../../core/strings/remote_strings.dart';
import '../../../core/theme/tokens.g.dart';
import '../../../ui/glass_key.dart';
import '../../../ui/r_icon.dart';
import '../../../ui/r_icons_data.dart';
import '../../../ui/status_pill.dart';

/// Settings icon size inside the 48 dp button. Not a token: the value comes from
/// `States-light.dc.html` (20 dp, stroke 2).
const double _settingsIconSize = 20;
const double _settingsIconStroke = 2;

/// SCR-010 header: laptop name (`titleMd`, one line) above [StatusPill],
/// and a 48 dp Settings button on the right (`design/components.md` C10).
///
/// Long names are ellipsized; the full name is in the Semantics label.
final class RemoteHeader extends StatelessWidget {
  const RemoteHeader({
    super.key,
    required this.laptopName,
    required this.pillVariant,
    required this.pillLabel,
    required this.pillSemanticsLabel,
    required this.onSettings,
  });

  final String laptopName;
  final StatusPillVariant pillVariant;
  final String pillLabel;
  final String pillSemanticsLabel;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurface;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                header: true,
                label: laptopName,
                child: ExcludeSemantics(
                  child: Text(
                    laptopName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ),
              const SizedBox(height: RSpace.s2),
              // The pill ellipsizes its label when 130% text does not fit.
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: StatusPill(
                  variant: pillVariant,
                  label: pillLabel,
                  semanticsLabel: pillSemanticsLabel,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: RSpace.s3),
        GlassKey(
          variant: GlassKeyVariant.glass,
          size: GlassKeySize.touch,
          semanticsLabel: RemoteStrings.settingsButton,
          onPressed: onSettings,
          icon: RIcon(
            RIcons.settingsSliders,
            size: _settingsIconSize,
            color: muted,
            strokeWidth: _settingsIconStroke,
          ),
        ),
      ],
    );
  }
}
