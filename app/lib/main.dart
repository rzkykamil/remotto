import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/storage/connection_storage.dart';
import 'core/storage/storage_providers.dart';

/// Membaca storage sebelum `runApp`, jadi redirect router bersifat sinkron
/// dan tidak ada layar loading di M0.
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
      ],
      child: const RemottoApp(),
    ),
  );
}
