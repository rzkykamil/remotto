import 'package:flutter/material.dart';

import '../../core/strings/strings.dart';

/// Placeholder rute `/settings`. Layar nyata dikerjakan di M5.
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
