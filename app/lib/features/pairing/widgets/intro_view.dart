import 'package:flutter/material.dart';

import '../../../core/strings/pairing_strings.dart';
import '../../../ui/brand_mark.dart';
import '../../../ui/pairing_scaffold.dart';

/// Q01 First open: mark, title, three steps, actions "Scan QR" and "Isi manual".
final class IntroView extends StatelessWidget {
  const IntroView({super.key, required this.onScan, required this.onManual});

  final VoidCallback onScan;
  final VoidCallback onManual;

  @override
  Widget build(BuildContext context) {
    return PairingScaffold(
      leading: const BrandMark(),
      title: PairingStrings.introTagline,
      tips: const [
        PairingStrings.introStep1,
        PairingStrings.introStep2,
        PairingStrings.introStep3,
      ],
      primaryLabel: PairingStrings.scanQr,
      onPrimary: onScan,
      secondaryLabel: PairingStrings.manualLink,
      onSecondary: onManual,
    );
  }
}
