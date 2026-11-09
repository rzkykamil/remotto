import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:remotto/core/haptics/r_haptics.dart';
import 'package:remotto/core/storage/app_preferences.dart';
import 'package:remotto/core/storage/storage_providers.dart';
import 'package:remotto/core/theme/app_theme.dart';
import 'package:remotto/features/pairing/widgets/result_views.dart';
import 'package:remotto/features/pairing/widgets/testing_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/fakes.dart';
import '../../../support/test_app.dart';

Future<List<Override>> _overrides() async {
  SharedPreferences.setMockInitialValues({
    AppPreferences.keyHapticEnabled: true,
  });
  final prefs = await SharedPreferences.getInstance();
  return [
    hapticSinkProvider.overrideWithValue(RecordingHapticSink()),
    sharedPreferencesProvider.overrideWithValue(prefs),
  ];
}

void main() {
  group('TestingView (Q08)', () {
    testWidgets('shows address, title, steps and cancel', (tester) async {
      var cancelled = false;
      await pumpApp(
        tester,
        TestingView(
          address: '192.168.1.20:8765',
          activeStep: 1,
          onCancel: () => cancelled = true,
        ),
        overrides: await _overrides(),
      );

      expect(find.text('192.168.1.20:8765'), findsOneWidget);
      expect(find.text('Lagi nyambung…'), findsOneWidget);
      expect(find.text('Laptop ketemu'), findsOneWidget);
      expect(find.text('Cek token'), findsOneWidget);
      expect(find.text('Simpan sambungan'), findsOneWidget);

      await tester.tap(find.text('Batal'));
      await tester.pump();
      expect(cancelled, isTrue);
      expect(tester.takeException(), isNull);
    });
  });

  group('Result views', () {
    testWidgets('TimeoutView shows 5 second body and both actions (Q10)', (
      tester,
    ) async {
      var retried = false;
      var changed = false;
      await pumpApp(
        tester,
        TimeoutView(
          address: '10.0.0.1:8765',
          onRetry: () => retried = true,
          onChangeAddress: () => changed = true,
        ),
        overrides: await _overrides(),
      );

      expect(find.text('Laptop nggak ketemu'), findsOneWidget);
      expect(
        find.text('Udah dicoba 5 detik di 10.0.0.1:8765.'),
        findsOneWidget,
      );
      expect(
        find.text('HP dan laptop harus di WiFi yang sama.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Coba lagi'));
      await tester.pump();
      await tester.tap(find.text('Ubah alamat'));
      await tester.pump();
      expect(retried, isTrue);
      expect(changed, isTrue);
    });

    testWidgets('RejectedView scan and manual actions (Q11)', (tester) async {
      var rescanned = false;
      var manual = false;
      await pumpApp(
        tester,
        RejectedView(
          onRescan: () => rescanned = true,
          onManual: () => manual = true,
        ),
        overrides: await _overrides(),
      );

      expect(find.text('Token-nya ditolak'), findsOneWidget);
      await tester.tap(find.text('Scan ulang QR'));
      await tester.pump();
      await tester.tap(find.text('Isi manual'));
      await tester.pump();
      expect(rescanned, isTrue);
      expect(manual, isTrue);
    });

    testWidgets('ExpiredView uppercases laptop name and announces (Q12)', (
      tester,
    ) async {
      await pumpApp(
        tester,
        ExpiredView(
          laptopName: 'Laptop-Kamil',
          onRescan: () {},
          onManual: () {},
        ),
        overrides: await _overrides(),
      );

      expect(find.text('LAPTOP-KAMIL'), findsOneWidget);
      expect(find.text('Sambungan putus'), findsOneWidget);
      final node = tester.getSemantics(find.byType(ExpiredView));
      expect(node.flagsCollection.isLiveRegion, isTrue);
    });

    testWidgets('SuccessView shows name and goes to /remote (Q09)', (
      tester,
    ) async {
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const SuccessView(laptopName: 'Laptop-Kamil'),
          ),
          GoRoute(
            path: '/remote',
            builder: (_, _) => const Text('REMOTE_SCREEN'),
          ),
        ],
      );
      tester.view.physicalSize = const Size(412, 892);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: await _overrides(),
          child: MaterialApp.router(
            theme: AppTheme.light,
            routerConfig: router,
          ),
        ),
      );

      expect(find.text('Laptop-Kamil siap dikontrol'), findsOneWidget);
      expect(find.text('NYAMBUNG'), findsOneWidget);
      await tester.tap(find.text('Mulai pakai'));
      await tester.pumpAndSettle();
      expect(find.text('REMOTE_SCREEN'), findsOneWidget);
    });
  });
}
