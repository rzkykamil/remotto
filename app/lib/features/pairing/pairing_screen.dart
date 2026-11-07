import 'package:flutter/material.dart';

import '../../core/strings/strings.dart';

/// Placeholder rute `/pairing`. Layar nyata dikerjakan di M1.
// TODO(M1): replace placeholder with the pairing flow from artboards.
class PairingScreen extends StatelessWidget {
  const PairingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: Text(
          AppStrings.placeholderPairing,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
      ),
    );
  }
}
