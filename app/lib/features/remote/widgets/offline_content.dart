import 'package:flutter/material.dart';

import '../../../core/strings/remote_strings.dart';
import '../../../core/theme/tokens.g.dart';
import '../../../ui/glass_key.dart';
import '../../../ui/link_button.dart';
import '../../../ui/r_icon.dart';
import '../../../ui/r_icons_data.dart';

/// Offline state icon, 40 dp (`design/components.md` C08). Not a token:
/// the value comes from `States-light.dc.html`.
const double _stateIconSize = 40;

/// Offline state icon stroke (artboard 1.8 on a 24 viewBox).
const double _stateIconStroke = 1.8;

/// Volume panel content when offline (`design/components.md` C08, S10).
///
/// Content only; the glass panel is provided by the caller. Order: icon, title, body,
/// then actions "Coba lagi" and "Pairing ulang". [retrying] changes the label
/// "Coba lagi" to "Nyoba…" and disables it. [poweredOff] changes the
/// title and icon to the "Laptop lagi mati" state (P15, used from M4).
final class OfflineContent extends StatelessWidget {
  const OfflineContent({
    super.key,
    required this.onRetry,
    required this.onRepair,
    this.retrying = false,
    this.poweredOff = false,
  });

  final VoidCallback onRetry;
  final VoidCallback onRepair;
  final bool retrying;
  final bool poweredOff;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final retryLabel = retrying
        ? RemoteStrings.offlineRetrying
        : RemoteStrings.offlineRetry;

    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        RIcon(
          poweredOff ? RIcons.power : RIcons.wifiOff,
          size: _stateIconSize,
          color: muted,
          strokeWidth: _stateIconStroke,
        ),
        const SizedBox(height: RSpace.s3),
        Semantics(
          header: true,
          child: Text(
            poweredOff
                ? RemoteStrings.poweredOffTitle
                : RemoteStrings.offlineTitle,
            style: textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: RSpace.s2),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: RSpace.s6),
          child: Text(
            RemoteStrings.offlineBody,
            style: textTheme.bodyLarge?.copyWith(color: muted),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: RSpace.s3),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: RSpace.s1,
          runSpacing: RSpace.s2,
          children: [
            GlassKey(
              variant: GlassKeyVariant.chip,
              size: GlassKeySize.touch,
              label: retryLabel,
              semanticsLabel: retryLabel,
              onPressed: retrying ? null : onRetry,
            ),
            RLinkButton(
              label: RemoteStrings.repairPairing,
              semanticsLabel: RemoteStrings.repairPairing,
              onPressed: onRepair,
            ),
          ],
        ),
      ],
    );
  }
}
