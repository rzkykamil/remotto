import 'dart:io';

import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotto/core/connection/connection_providers.dart';
import 'package:remotto/core/connection/connection_state.dart';
import 'package:remotto/core/haptics/r_haptics.dart';
import 'package:remotto/core/network/network_providers.dart';
import 'package:remotto/core/storage/pairing_data.dart';
import 'package:remotto/core/storage/storage_providers.dart';
import 'package:remotto/core/theme/app_theme.dart';
import 'package:remotto/core/theme/tokens.g.dart';
import 'package:remotto/features/remote/power/power_providers.dart';
import 'package:remotto/features/remote/power/wakelock_controller.dart';
import 'package:remotto/features/remote/remote_screen.dart';
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

/// Records the screen wakelock calls.
final class _FakeWakelock implements WakelockController {
  @override
  Future<void> enable() async {}

  @override
  Future<void> disable() async {}
}

final class _Harness {
  _Harness({required this.status, required this.scheduler});

  final FakeStatusRepository status;
  final FakePollScheduler scheduler;

  /// Periodic jobs that are still live (the poll schedule).
  Iterable<FakeScheduledJob> get livePeriodic =>
      scheduler.jobs.where((job) => job.live && job.periodic);

  /// Sends one app lifecycle change to the widget tree.
  Future<void> lifecycle(WidgetTester tester, AppLifecycleState state) async {
    tester.binding.handleAppLifecycleStateChanged(state);
    await _settle(tester);
  }
}

/// Waits for the futures of the fakes, then rebuilds the frames.
Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(() => pumpEventQueue());
  await tester.pumpAndSettle();
}

/// Mounts [RemoteScreen] alone, so a 401 does not move the router away from it.
Future<_Harness> _pumpRemote(
  WidgetTester tester, {
  required List<FakeStatusStep> status,
}) async {
  tester.view.physicalSize = const Size(412, 892);
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
  final statusRepository = FakeStatusRepository(status);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        initialPairingProvider.overrideWithValue(_pairing),
        connectionStorageProvider.overrideWithValue(
          InMemoryConnectionStorage(_pairing),
        ),
        statusRepositoryProvider.overrideWithValue(statusRepository),
        pollSchedulerProvider.overrideWithValue(scheduler),
        volumeOverride(),
        powerRepositoryProvider.overrideWithValue(FakePowerRepository()),
        wakelockControllerProvider.overrideWithValue(_FakeWakelock()),
        hapticSinkProvider.overrideWithValue(RecordingHapticSink()),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        home: const RemoteScreen(),
      ),
    ),
  );
  await _settle(tester);

  return _Harness(status: statusRepository, scheduler: scheduler);
}

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
    'FR-6.6: paused menghentikan polling, tidak ada request /status baru',
    (tester) async {
      final h = await _pumpRemote(tester, status: [fakeStatusOk()]);
      expect(h.status.calls, 1);
      expect(h.livePeriodic, isNotEmpty);

      await h.lifecycle(tester, AppLifecycleState.paused);
      final callsAtPause = h.status.calls;
      expect(h.livePeriodic, isEmpty);

      // Time passes in the background; no poll may fire.
      await tester.pump(const Duration(seconds: 30));
      await _settle(tester);
      expect(h.status.calls, callsAtPause);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('FR-6.6, BR-21: resumed memulai polling segera setelah paused', (
    tester,
  ) async {
    final h = await _pumpRemote(tester, status: [fakeStatusOk()]);
    await h.lifecycle(tester, AppLifecycleState.paused);
    final callsAtPause = h.status.calls;

    await h.lifecycle(tester, AppLifecycleState.resumed);

    // The first poll after resume runs at once, then the periodic schedule.
    expect(h.status.calls, callsAtPause + 1);
    expect(h.livePeriodic.single.delay, RMotion.poll);

    h.livePeriodic.single.run();
    await _settle(tester);
    expect(h.status.calls, callsAtPause + 2);
    expect(tester.takeException(), isNull);
  });

  for (final state in [AppLifecycleState.inactive, AppLifecycleState.hidden]) {
    testWidgets('FR-6.6: ${state.name} tidak menghentikan polling', (
      tester,
    ) async {
      final h = await _pumpRemote(tester, status: [fakeStatusOk()]);
      final callsBefore = h.status.calls;

      await h.lifecycle(tester, state);

      expect(h.livePeriodic, hasLength(1));
      expect(h.status.calls, callsBefore);

      h.livePeriodic.single.run();
      await _settle(tester);
      expect(h.status.calls, callsBefore + 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'FR-6.6, BR-21: paused lalu resumed saat tokenRejected tidak memulai poll',
    (tester) async {
      final h = await _pumpRemote(
        tester,
        status: [fakeErrorReply(401, 'unauthorized')],
      );
      expect(h.status.calls, 1);
      expect(
        ProviderScope.containerOf(tester.element(find.byType(RemoteScreen)))
            .read(connectionControllerProvider)
            .phase,
        ConnectionPhase.tokenRejected,
      );

      await h.lifecycle(tester, AppLifecycleState.paused);
      await h.lifecycle(tester, AppLifecycleState.resumed);

      expect(h.status.calls, 1);
      expect(h.livePeriodic, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
