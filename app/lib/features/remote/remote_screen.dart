import 'package:flutter/material.dart';

import '../../core/strings/strings.dart';

/// Placeholder rute `/remote`. Layar nyata dikerjakan di M2.
// TODO(M2): replace placeholder with the remote screen from artboards.
class RemoteScreen extends StatelessWidget {
  const RemoteScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: Text(
          AppStrings.placeholderRemote,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
      ),
    );
  }
}
