import 'package:flutter/material.dart';

import '../../core/strings/strings.dart';

/// Placeholder for route `/settings`. The real screen is built in M5.
// TODO(M5): replace placeholder with the settings screen from artboards.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: Text(
          AppStrings.placeholderSettings,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
      ),
    );
  }
}
