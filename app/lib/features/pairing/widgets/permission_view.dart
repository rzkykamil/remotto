import 'package:flutter/material.dart';

import '../../../core/strings/pairing_strings.dart';
import '../../../ui/brand_mark.dart';
import '../../../ui/pairing_scaffold.dart';
import '../../../ui/r_icons_data.dart';

/// Q02 Camera permission, explanation before the OS dialog: glass icon, title, two actions.
final class PermissionView extends StatelessWidget {
  const PermissionView({
    super.key,
    required this.onAllow,
    required this.onManual,
  });

  final VoidCallback onAllow;
  final VoidCallback onManual;

  @override
  Widget build(BuildContext context) {
    return PairingScaffold(
      leading: const IconDisc.glassLarge(icon: RIcons.camera),
      title: PairingStrings.permTitle,
      body: PairingStrings.permBody,
      primaryLabel: PairingStrings.permAllow,
      onPrimary: onAllow,
      secondaryLabel: PairingStrings.permManualLink,
      onSecondary: onManual,
    );
  }
}
