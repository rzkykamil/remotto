import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotto/app.dart';
import 'package:remotto/core/connection/connection_providers.dart';
import 'package:remotto/core/haptics/r_haptics.dart';
import 'package:remotto/core/network/api_failure.dart';
import 'package:remotto/core/network/network_providers.dart';
import 'package:remotto/core/storage/pairing_data.dart';
import 'package:remotto/core/storage/storage_providers.dart';
import 'package:remotto/core/strings/power_strings.dart';
import 'package:remotto/core/strings/remote_strings.dart';
import 'package:remotto/core/theme/tokens.g.dart';
import 'package:remotto/core/toast/toast_controller.dart';
import 'package:remotto/features/remote/power/countdown_screen.dart';
import 'package:remotto/features/remote/power/power_providers.dart';
import 'package:remotto/features/remote/power/result_screen.dart';
import 'package:remotto/features/remote/power/wakelock_controller.dart';
import 'package:remotto/features/remote/remote_screen.dart';
import 'package:remotto/features/remote/widgets/confirm_sheet.dart';
import 'package:remotto/features/remote/widgets/power_row.dart';
import 'package:remotto/ui/hold_to_confirm.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_poll_scheduler.dart';
import '../../support/fake_power_repository.dart';
import '../../support/fake_status_repository.dart';
import '../../support/fakes.dart';
import '../../support/volume_overrides.dart';

const _pairing = PairingData(
  host: '192.168.1.10',
  port: 8765,
  token: 'test-token',
  laptopName: 'Laptop-Kamil',
);

const _oneSecond = Duration(seconds: 1);

/// Records the screen wakelock calls.
final class _FakeWakelock implements WakelockController {
  final List<String> calls = [];

  @override
  Future<void> enable() async => calls.add('enable');

  @override
  Future<void> disable() async => calls.add('disable');
}

final class _Harness {
  _Harness({
    required this.container,
    required this.scheduler,
    required this.wakelock,
  });

  final ProviderContainer container;
  final FakePollScheduler scheduler;
  final _FakeWakelock wakelock;

  /// Runs the countdown ticker [times] times, as the real 1 s timer would.
  Future<void> tickCountdown(WidgetTester tester, {int times = 1}) async {
    for (var i = 0; i < times; i++) {
      final ticker = scheduler.jobs.lastWhere(
        (job) => job.live && job.periodic && job.delay == _oneSecond,
      );
      ticker.run();
    }
    await _settle(tester);
  }

  /// Runs one status poll (every 5 s). The periodic job with the poll
  /// interval, not the countdown ticker.
  Future<void> pollStatus(WidgetTester tester) async {
    final poll = scheduler.jobs.lastWhere(
      (job) => job.live && job.periodic && job.delay == RMotion.poll,
    );
    poll.run();
    await _settle(tester);
  }
}

/// Waits for the futures of the fakes, then rebuilds the frames.
Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(() => pumpEventQueue());
  await tester.pumpAndSettle();
}

/// Opens the full app at Remote with the given power and status fakes.
Future<_Harness> _pumpApp(
  WidgetTester tester, {
  required FakePowerRepository power,
  List<FakeStatusStep> status = const [],
  Size size = const Size(412, 892),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  final prefs = (await tester.runAsync(() async {
    SharedPreferences.setMockInitialValues({});
    return SharedPreferences.getInstance();
  }))!;
  final scheduler = FakePollScheduler();
  final wakelock = _FakeWakelock();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        initialPairingProvider.overrideWithValue(_pairing),
        connectionStorageProvider.overrideWithValue(
          InMemoryConnectionStorage(_pairing),
        ),
        statusRepositoryProvider.overrideWithValue(
          FakeStatusRepository(
            status.isEmpty ? [fakeStatusOk(name: 'Laptop-Kamil')] : status,
          ),
        ),
        pollSchedulerProvider.overrideWithValue(scheduler),
        volumeOverride(),
        powerRepositoryProvider.overrideWithValue(power),
        wakelockControllerProvider.overrideWithValue(wakelock),
        hapticSinkProvider.overrideWithValue(RecordingHapticSink()),
      ],
      child: const RemottoApp(),
    ),
  );
  await _settle(tester);

  return _Harness(
    container: ProviderScope.containerOf(
      tester.element(find.byType(RemottoApp)),
    ),
    scheduler: scheduler,
    wakelock: wakelock,
  );
}

Future<void> _tap(WidgetTester tester, String text) async {
  await tester.tap(find.text(text));
  await _settle(tester);
}

/// Holds the hold control with [label] until it completes, then releases.
Future<void> _hold(WidgetTester tester, String label) async {
  final center = tester.getCenter(
    find.descendant(of: find.byType(HoldToConfirm), matching: find.text(label)),
  );
  final gesture = await tester.startGesture(center);
  await tester.pump();
  await tester.pump(RMotion.hold);
  await tester.pump(const Duration(milliseconds: 50));
  await gesture.up();
  await _settle(tester);
}

/// Whether the power row is enabled (`PowerRow.enabled`).
bool _rowEnabled(WidgetTester tester) =>
    tester.widget<PowerRow>(find.byType(PowerRow)).enabled;

/// Loads the bundled Geist font, so label widths match the app and not the
/// test font (Ahem, one em per glyph).
Future<void> _loadGeist() async {
  final loader = FontLoader('Geist');
  for (final name in ['Geist-Regular', 'Geist-Medium', 'Geist-SemiBold']) {
    final bytes = File('assets/fonts/$name.ttf').readAsBytesSync();
    loader.addFont(
      Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)),
    );
  }
  await loader.load();
}

void main() {
  setUpAll(_loadGeist);

  testWidgets(
    '(a) sleep: Sleep-in, hitung mundur 5 detik, terkirim, Oke kembali ke Remote',
    (tester) async {
      final power = FakePowerRepository();
      final h = await _pumpApp(tester, power: power);

      await _tap(tester, PowerStrings.rowSleep);
      expect(find.byType(ConfirmSheet), findsOneWidget);
      await _tap(tester, PowerStrings.sleepAction);

      expect(power.scheduleCalls, 1);
      expect(find.byType(ConfirmSheet), findsNothing);
      expect(find.byType(CountdownScreen), findsOneWidget);
      expect(find.text(PowerStrings.countdownTitleSleep), findsOneWidget);
      expect(h.wakelock.calls, ['enable']);
      expect(_rowEnabled(tester), isFalse);

      await h.tickCountdown(tester, times: 5);

      expect(find.byType(CountdownScreen), findsNothing);
      expect(find.byType(ResultScreen), findsOneWidget);
      expect(find.text(PowerStrings.doneSleepTitle), findsOneWidget);
      expect(h.wakelock.calls, ['enable', 'disable']);

      await _tap(tester, PowerStrings.doneAction);

      expect(find.byType(ResultScreen), findsNothing);
      expect(find.byType(CountdownScreen), findsNothing);
      expect(find.byType(RemoteScreen), findsOneWidget);
      expect(_rowEnabled(tester), isTrue);
      expect(power.scheduleCalls, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    '(b) shutdown: Lanjut, tahan penuh, hitung mundur, Batal, toast di Remote',
    (tester) async {
      final power = FakePowerRepository();
      final h = await _pumpApp(tester, power: power);

      await _tap(tester, PowerStrings.rowShutdown);
      await _tap(tester, PowerStrings.stage1Action);
      expect(find.byType(HoldToConfirm), findsOneWidget);
      await _hold(tester, PowerStrings.shutdownHoldLabel);

      expect(power.scheduleCalls, 1);
      expect(find.byType(CountdownScreen), findsOneWidget);
      expect(find.text(PowerStrings.countdownTitleShutdown), findsOneWidget);

      await _tap(tester, PowerStrings.countdownCancel);

      expect(power.cancelCalls, 1);
      expect(find.byType(CountdownScreen), findsNothing);
      expect(find.byType(ResultScreen), findsNothing);
      expect(find.byType(RemoteScreen), findsOneWidget);
      expect(find.text(PowerStrings.toastCancelledShutdown), findsOneWidget);
      expect(
        h.container.read(toastControllerProvider)?.text,
        PowerStrings.toastCancelledShutdown,
      );
      expect(_rowEnabled(tester), isTrue);
      expect(h.wakelock.calls, ['enable', 'disable']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    '(c) jadwal gagal (500) menampilkan P10; Coba lagi membuka tahap 2 tanpa mengirim',
    (tester) async {
      final power = FakePowerRepository(
        script: [fakePowerError(500, 'power_failed')],
      );
      await _pumpApp(tester, power: power);

      await _tap(tester, PowerStrings.rowShutdown);
      await _tap(tester, PowerStrings.stage1Action);
      await _hold(tester, PowerStrings.shutdownHoldLabel);

      expect(find.byType(ResultScreen), findsOneWidget);
      expect(find.text(PowerStrings.scheduleFailedTitle), findsOneWidget);
      expect(power.scheduleCalls, 1);

      await _tap(tester, PowerStrings.scheduleFailedRetry);

      // Confirm sheet again, straight to the hold step (already confirmed).
      expect(find.byType(ResultScreen), findsNothing);
      expect(find.byType(ConfirmSheet), findsOneWidget);
      expect(find.byType(HoldToConfirm), findsOneWidget);
      expect(find.text(PowerStrings.stage1Action), findsNothing);
      expect(power.scheduleCalls, 1);

      await _tap(tester, PowerStrings.cancelAction);
      expect(find.byType(ConfirmSheet), findsNothing);
      expect(power.scheduleCalls, 1);
      expect(find.byType(RemoteScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    '(c) P10 sleep: Coba lagi membuka P01 lagi; Tutup kembali ke Remote',
    (tester) async {
      final power = FakePowerRepository(
        script: [fakePowerError(500, 'power_failed')],
      );
      await _pumpApp(tester, power: power);

      await _tap(tester, PowerStrings.rowSleep);
      await _tap(tester, PowerStrings.sleepAction);
      expect(find.text(PowerStrings.scheduleFailedTitle), findsOneWidget);

      await _tap(tester, PowerStrings.scheduleFailedRetry);
      expect(find.byType(ResultScreen), findsNothing);
      expect(find.text(PowerStrings.sleepAction), findsOneWidget);
      expect(power.scheduleCalls, 1);

      await _tap(tester, PowerStrings.sleepAction);
      expect(power.scheduleCalls, 2);
      expect(find.text(PowerStrings.scheduleFailedTitle), findsOneWidget);

      await _tap(tester, PowerStrings.scheduleFailedClose);
      expect(find.byType(ResultScreen), findsNothing);
      expect(find.byType(RemoteScreen), findsOneWidget);
      expect(_rowEnabled(tester), isTrue);
      expect(power.scheduleCalls, 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    '(d) tanpa konfirmasi pengguna, tidak ada perintah yang dikirim',
    (tester) async {
      final power = FakePowerRepository();
      await _pumpApp(tester, power: power);

      // Sheet opened and dismissed with "Nggak jadi".
      await _tap(tester, PowerStrings.rowSleep);
      expect(find.byType(ConfirmSheet), findsOneWidget);
      await _tap(tester, PowerStrings.cancelAction);

      expect(find.byType(ConfirmSheet), findsNothing);
      expect(find.byType(CountdownScreen), findsNothing);
      expect(power.scheduleCalls, 0);
      expect(power.cancelCalls, 0);
      expect(_rowEnabled(tester), isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('(e) PowerRow nonaktif saat flow berjalan', (tester) async {
    final power = FakePowerRepository();
    final h = await _pumpApp(tester, power: power);
    expect(_rowEnabled(tester), isTrue);

    await _tap(tester, PowerStrings.rowSleep);
    await _tap(tester, PowerStrings.sleepAction);
    expect(find.byType(CountdownScreen), findsOneWidget);
    expect(_rowEnabled(tester), isFalse);

    await h.tickCountdown(tester, times: 5);
    expect(find.byType(ResultScreen), findsOneWidget);
    expect(_rowEnabled(tester), isFalse);

    await _tap(tester, PowerStrings.doneAction);
    expect(_rowEnabled(tester), isTrue);
  });

  testWidgets('(e) PowerRow nonaktif saat layar offline', (tester) async {
    final power = FakePowerRepository();
    final h = await _pumpApp(
      tester,
      power: power,
      status: [
        const FakeTransportFailure(UnreachableFailure()),
        const FakeTransportFailure(UnreachableFailure()),
      ],
    );

    // First poll failed: still connecting, so the row is off.
    expect(_rowEnabled(tester), isFalse);

    // Second failed poll: offline (S10).
    await h.pollStatus(tester);
    expect(find.text(RemoteStrings.offlineTitle), findsOneWidget);
    expect(_rowEnabled(tester), isFalse);
    expect(power.scheduleCalls, 0);
    expect(tester.takeException(), isNull);
  });

  for (final size in [
    const Size(360, 640),
    const Size(360, 800),
    const Size(412, 892),
  ]) {
    for (final textScale in [1.0, 1.3]) {
      testWidgets(
        'layar ${size.width.toInt()}x${size.height.toInt()} teks ${(textScale * 100).round()}%: baris daya tampil tanpa overflow',
        (tester) async {
          tester.platformDispatcher.textScaleFactorTestValue = textScale;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await _pumpApp(tester, power: FakePowerRepository(), size: size);

          expect(find.byType(PowerRow), findsOneWidget);
          expect(find.text(PowerStrings.rowShutdown), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
