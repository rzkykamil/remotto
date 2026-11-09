import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/storage/connection_storage.dart';
import 'core/storage/storage_providers.dart';
import 'features/pairing/state/pairing_flow_controller.dart';
import 'features/pairing/widgets/qr_viewfinder.dart';

/// Reads storage before `runApp`, so the router redirect is synchronous
/// and there is no loading screen in M0.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  final prefs = await SharedPreferences.getInstance();
  final initial = await const SecureConnectionStorage(FlutterSecureStorage())
      .read();

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        initialPairingProvider.overrideWithValue(initial),
        // Real camera for the scan screen (the only mobile_scanner import
        // is in qr_viewfinder.dart).
        qrScannerSourceProvider.overrideWith(
          (ref) => ref.watch(mobileScannerQrSourceProvider),
        ),
      ],
      child: const RemottoApp(),
    ),
  );
}
