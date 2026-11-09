import 'package:flutter/material.dart';

import '../../../core/strings/pairing_strings.dart';
import '../../../ui/brand_mark.dart';
import '../../../ui/pairing_scaffold.dart';
import '../../../ui/r_icons_data.dart';

/// Q05 Permission permanently denied: camera-off icon, title, action to phone settings.
final class PermissionBlockedView extends StatelessWidget {
  const PermissionBlockedView({
    super.key,
    required this.onOpenSettings,
    required this.onManual,
  });

  final VoidCallback onOpenSettings;
  final VoidCallback onManual;

  @override
  Widget build(BuildContext context) {
    return PairingScaffold(
      leading: const IconDisc.chipLarge(icon: RIcons.cameraOff),
      title: PairingStrings.deniedTitle,
      body: PairingStrings.deniedBody,
      primaryLabel: PairingStrings.deniedOpenSettings,
      onPrimary: onOpenSettings,
      secondaryLabel: PairingStrings.deniedManualLink,
      onSecondary: onManual,
    );
  }
}
