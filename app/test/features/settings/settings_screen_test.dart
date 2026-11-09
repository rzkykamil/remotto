import 'dart:async';
import 'dart:ui' show CheckedState, Size, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:remotto/app.dart';
import 'package:remotto/core/connection/connection_providers.dart';
import 'package:remotto/core/connection/connection_state.dart';
import 'package:remotto/core/connection/status_repository.dart';
import 'package:remotto/core/network/api_failure.dart';
import 'package:remotto/core/network/network_providers.dart';
import 'package:remotto/core/router/app_router.dart';
import 'package:remotto/core/storage/app_preferences.dart';
import 'package:remotto/core/storage/pairing_data.dart';
import 'package:remotto/core/storage/storage_providers.dart';
import 'package:remotto/core/strings/settings_strings.dart';
import 'package:remotto/core/theme/glass_mode.dart';
import 'package:remotto/core/theme/reduce_transparency_channel.dart';
import 'package:remotto/core/theme/tokens.g.dart';
import 'package:remotto/features/remote/power/power_providers.dart';
import 'package:remotto/features/remote/remote_screen.dart';
import 'package:remotto/features/settings/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_power_repository.dart';
import '../../support/fake_poll_scheduler.dart';
import '../../support/fake_status_repository.dart';
import '../../support/fakes.dart';
import '../../support/volume_overrides.dart';

const _pairing = PairingData(
  host: '192.168.1.10',
  port: 8765,
  token: 'test-token',
  laptopName: 'Laptop Uji',
);

/// Nama laptop sangat panjang untuk R03 (teks 130%).
const _longName = 'Laptop-Kamil-Ruang-Kerja-Utama-Lantai-Dua-Belakang';

/// Hasil pump: container untuk provider dan SharedPreferences untuk cek tulis.
final class _Harness {
  _Harness(this.container, this.prefs, this.storage);

  final ProviderContainer container;
  final SharedPreferences prefs;
  final InMemoryConnectionStorage storage;

  String get path => container
      .read(routerProvider)
      .routerDelegate
      .currentConfiguration
      .uri
      .path;
}

Future<_Harness> _pumpApp(
  WidgetTester tester, {
  Map<String, Object> initialPrefs = const {},
  FakeStatusRepository? repo,
  Size size = const Size(412, 892),
  Brightness brightness = Brightness.light,
  double textScale = 1.0,
  List<Override> extra = const [],
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  tester.platformDispatcher.platformBrightnessTestValue = brightness;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.platformDispatcher.clearPlatformBrightnessTestValue();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });

  final prefs = (await tester.runAsync(() async {
    SharedPreferences.setMockInitialValues(initialPrefs);
    return SharedPreferences.getInstance();
  }))!;

  final storage = InMemoryConnectionStorage(_pairing);
  final StatusRepository statusRepo =
      repo ?? FakeStatusRepository([fakeStatusOk(uptimeSeconds: 11520)]);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        initialPairingProvider.overrideWithValue(_pairing),
        connectionStorageProvider.overrideWithValue(storage),
        statusRepositoryProvider.overrideWithValue(statusRepo),
        pollSchedulerProvider.overrideWithValue(FakePollScheduler()),
        volumeOverride(),
        powerRepositoryProvider.overrideWithValue(FakePowerRepository()),
        ...extra,
      ],
      child: const RemottoApp(),
    ),
  );
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await tester.pumpAndSettle();

  final container = ProviderScope.containerOf(
    tester.element(find.byType(RemottoApp)),
  );
  return _Harness(container, prefs, storage);
}

/// Membuka Pengaturan dengan push dari Remote, seperti tombol di Remote.
Future<void> _openSettings(WidgetTester tester, _Harness h) async {
  unawaited(h.container.read(routerProvider).push(AppRoutes.settings));
  await tester.pumpAndSettle();
  expect(find.byType(SettingsScreen), findsOneWidget);
}

/// Bayangan luar panel kaca (`GlassPanel`: blur 32). Bayangan thumb switch (blur 6)
/// tidak ikut dihitung.
List<BoxShadow> _glowShadows(WidgetTester tester) => [
  for (final box in tester.widgetList<DecoratedBox>(
    find.descendant(
      of: find.byType(SettingsScreen),
      matching: find.byType(DecoratedBox),
    ),
  ))
    if (box.decoration case final BoxDecoration d)
      ...?d.boxShadow?.where((s) => s.blurRadius == 32),
];

Brightness _screenBrightness(WidgetTester tester) =>
    Theme.of(tester.element(find.byType(SettingsScreen))).brightness;

void main() {
  for (final brightness in [Brightness.light, Brightness.dark]) {
    testWidgets('R01 (${brightness.name}): Sistem, getar nyala, NYAMBUNG, '
        '3j 12m', (tester) async {
      final h = await _pumpApp(tester, brightness: brightness);
      await _openSettings(tester, h);

      expect(h.container.read(themeModeProvider), ThemeMode.system);
      expect(h.container.read(hapticEnabledProvider), isTrue);
      expect(find.text(SettingsStrings.statusOnline), findsOneWidget);
      expect(find.text('3j 12m'), findsOneWidget);
      expect(find.text(SettingsStrings.hapticOn), findsOneWidget);
      expect(_screenBrightness(tester), brightness);
      expect(tester.takeException(), isNull);
    });

    testWidgets('R02 (${brightness.name}): Gelap menulis themeMode, '
        'matikan getar menulis hapticEnabled=false', (tester) async {
      final h = await _pumpApp(tester, brightness: brightness);
      await _openSettings(tester, h);

      await tester.tap(find.text(SettingsStrings.themeDark));
      await tester.pumpAndSettle();
      expect(h.container.read(themeModeProvider), ThemeMode.dark);
      expect(h.prefs.getString(AppPreferences.keyThemeMode), 'dark');
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.dark,
      );
      expect(_screenBrightness(tester), Brightness.dark);

      await tester.tap(find.text(SettingsStrings.hapticLabel));
      await tester.pumpAndSettle();
      expect(h.container.read(hapticEnabledProvider), isFalse);
      expect(h.prefs.getBool(AppPreferences.keyHapticEnabled), isFalse);
      expect(find.text(SettingsStrings.hapticOff), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final width in [360.0, 412.0]) {
    testWidgets('R03: teks 130% dan nama panjang tidak overflow dan tidak '
        'terpotong (lebar $width dp)', (tester) async {
      final h = await _pumpApp(
        tester,
        size: Size(width, 800),
        textScale: 1.3,
        repo: FakeStatusRepository([
          fakeStatusOk(name: _longName, uptimeSeconds: 11520),
        ]),
      );
      await _openSettings(tester, h);

      expect(tester.takeException(), isNull);
      final name = tester.widget<Text>(find.text(_longName));
      expect(name.maxLines, isNull);
      expect(name.overflow, isNull);
      expect(find.text(SettingsStrings.themeLight), findsOneWidget);
      expect(find.text(SettingsStrings.themeDark), findsOneWidget);
      expect(find.text(SettingsStrings.themeSystem), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('R04: Pairing ulang membuka sheet; Nggak jadi menutupnya tanpa '
      'efek', (tester) async {
    final h = await _pumpApp(tester);
    await _openSettings(tester, h);

    await tester.tap(find.text(SettingsStrings.repairPairing));
    await tester.pumpAndSettle();
    expect(find.text(SettingsStrings.repairSheetTitle), findsOneWidget);
    expect(
      find.text(SettingsStrings.repairSheetBody('Laptop-Kamil')),
      findsOneWidget,
    );

    await tester.tap(find.text(SettingsStrings.repairSheetCancel));
    await tester.pumpAndSettle();
    expect(find.text(SettingsStrings.repairSheetTitle), findsNothing);
    expect(h.storage.data, _pairing);
    expect(h.container.read(pairingProvider), _pairing);
    expect(find.byType(SettingsScreen), findsOneWidget);
  });

  testWidgets('R04: konfirmasi menjalankan alur pairing ulang (T7)', (
    tester,
  ) async {
    final h = await _pumpApp(tester);
    await _openSettings(tester, h);

    await tester.tap(find.text(SettingsStrings.repairPairing));
    await tester.pumpAndSettle();
    await tester.tap(find.text(SettingsStrings.repairSheetConfirm));
    await tester.pumpAndSettle();

    expect(h.container.read(pairingProvider), isNull);
    expect(h.path, AppRoutes.pairing);
  });

  testWidgets('R05 offline: NGGAK KEJANGKAU, uptime "—", tema dan getar tetap '
      'bisa dipakai', (tester) async {
    final repo = FakeStatusRepository([
      fakeStatusOk(uptimeSeconds: 11520),
      const FakeTransportFailure(UnreachableFailure()),
    ]);
    final h = await _pumpApp(tester, repo: repo);

    // Dua poll gagal berturut-turut menjadi offline (BR-8).
    await tester.runAsync(
      () => h.container.read(connectionControllerProvider.notifier).pollOnce(),
    );
    await tester.runAsync(
      () => h.container.read(connectionControllerProvider.notifier).pollOnce(),
    );
    await tester.pumpAndSettle();
    expect(
      h.container.read(connectionControllerProvider).phase,
      ConnectionPhase.offline,
    );

    await _openSettings(tester, h);
    expect(find.text(SettingsStrings.statusOffline), findsOneWidget);
    expect(find.text(SettingsStrings.uptimeUnknown), findsOneWidget);
    expect(find.text('3j 12m'), findsNothing);

    await tester.tap(find.text(SettingsStrings.themeDark));
    await tester.pumpAndSettle();
    expect(h.container.read(themeModeProvider), ThemeMode.dark);

    await tester.tap(find.text(SettingsStrings.hapticLabel));
    await tester.pumpAndSettle();
    expect(h.container.read(hapticEnabledProvider), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('R06: reduce transparency membuat panel solid tanpa blur', (
    tester,
  ) async {
    final h = await _pumpApp(
      tester,
      extra: [
        // Bootstrap membaca flag OS lewat channel secara async dan bisa
        // menimpa nilai uji dengan false. Matikan agar nilai uji bertahan.
        reduceTransparencyBootstrapProvider.overrideWith((ref) {}),
        reduceTransparencyProvider.overrideWithBuild((ref, notifier) => true),
      ],
    );
    await _openSettings(tester, h);

    expect(find.byType(BackdropFilter), findsNothing);
    final fills = tester
        .widgetList<DecoratedBox>(
          find.descendant(
            of: find.byType(SettingsScreen),
            matching: find.byType(DecoratedBox),
          ),
        )
        .map((box) => box.decoration)
        .whereType<BoxDecoration>();
    expect(fills.map((d) => d.color), contains(kLightTokens.glass.solid));
    expect(_glowShadows(tester), isEmpty, reason: 'tanpa bayangan kaca (glow)');
  });

  testWidgets(
    'R06 kontrol: tanpa reduce transparency kaca memakai blur dan glow',
    (tester) async {
      final h = await _pumpApp(tester);
      await _openSettings(tester, h);
      expect(find.byType(BackdropFilter), findsWidgets);
      expect(_glowShadows(tester), isNotEmpty);
    },
  );

  testWidgets('semantics: grup Tema radiogroup, switch berlabel, satu node per '
      'baris, header judul', (tester) async {
    final semantics = tester.ensureSemantics();
    final h = await _pumpApp(tester);
    await _openSettings(tester, h);

    final group = tester.getSemantics(find.bySemanticsLabel('Tema'));
    expect(group.flagsCollection.isInMutuallyExclusiveGroup, isFalse);

    for (final label in [
      SettingsStrings.themeLight,
      SettingsStrings.themeDark,
      SettingsStrings.themeSystem,
    ]) {
      final node = tester.getSemantics(find.bySemanticsLabel(label));
      expect(
        node.flagsCollection.isInMutuallyExclusiveGroup,
        isTrue,
        reason: label,
      );
    }
    expect(
      tester
          .getSemantics(find.bySemanticsLabel(SettingsStrings.themeSystem))
          .flagsCollection
          .isChecked,
      CheckedState.isTrue,
    );
    expect(
      tester
          .getSemantics(find.bySemanticsLabel(SettingsStrings.themeDark))
          .flagsCollection
          .isChecked,
      CheckedState.isFalse,
    );

    final haptic = tester.getSemantics(
      find.bySemanticsLabel(
        '${SettingsStrings.hapticLabel}, ${SettingsStrings.hapticOn}',
      ),
    );
    expect(haptic.childrenCount, 0);
    expect(haptic.flagsCollection.isToggled, Tristate.isTrue);

    final repair = tester.getSemantics(
      find.bySemanticsLabel(SettingsStrings.repairPairing),
    );
    expect(repair.childrenCount, 0);
    expect(repair.flagsCollection.isButton, isTrue);

    final info = tester.getSemantics(
      find.bySemanticsLabel(
        'Laptop-Kamil, 192.168.1.10:8765, ${SettingsStrings.statusOnline}',
      ),
    );
    expect(info.childrenCount, 0);

    final header = tester.getSemantics(
      find.bySemanticsLabel(SettingsStrings.title),
    );
    expect(header.flagsCollection.isHeader, isTrue);
    semantics.dispose();
  });

  testWidgets('tombol back (SettingsHeader) memanggil pop ke Remote', (
    tester,
  ) async {
    final h = await _pumpApp(tester);
    await _openSettings(tester, h);
    final router = h.container.read(routerProvider);
    expect(router.canPop(), isTrue);

    await tester.tap(find.bySemanticsLabel(SettingsStrings.backSemantics));
    await tester.pumpAndSettle();

    expect(find.byType(SettingsScreen), findsNothing);
    expect(find.byType(RemoteScreen), findsOneWidget);
    expect(router.canPop(), isFalse);
    expect(tester.takeException(), isNull);
  });
}
