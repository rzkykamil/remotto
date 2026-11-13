import 'dart:async';

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Setup untuk semua file tes.
///
/// `connectivity_plus` tidak punya implementasi native di tes. Handler palsu
/// untuk `listen` dan `cancel` (tanpa event) mencegah [ConnectionController]
/// menyentuh plugin nyata pada tes yang tidak mengganti
/// `networkChangeSourceProvider`. Tes yang butuh event jaringan memakai
/// `FakeNetworkChangeSource`.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  // The binding blocks real HTTP (every request answers 400). Tes HTTP
  // memakai server lokal, jadi override dicabut seperti sebelum binding ada.
  HttpOverrides.global = null;
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('dev.fluttercommunity.plus/connectivity_status'),
        (call) async => null,
      );
  await testMain();
}
