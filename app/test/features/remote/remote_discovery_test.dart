import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:remotto/app.dart';
import 'package:remotto/core/connection/connection_providers.dart';
import 'package:remotto/core/connection/connection_state.dart';
import 'package:remotto/core/discovery/agent_discovery.dart';
import 'package:remotto/core/discovery/discovery_providers.dart';
import 'package:remotto/core/network/agent_http_client.dart';
import 'package:remotto/core/network/network_providers.dart';
import 'package:remotto/core/storage/pairing_data.dart';
import 'package:remotto/core/storage/storage_providers.dart';
import 'package:remotto/core/strings/remote_strings.dart';
import 'package:remotto/core/theme/r_behavior.dart';
import 'package:remotto/features/remote/power/power_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_agent_discovery.dart';
import '../../support/fake_network_change_source.dart';
import '../../support/fake_poll_scheduler.dart';
import '../../support/fake_power_repository.dart';
import '../../support/fakes.dart';
import '../../support/volume_overrides.dart';

// Alur M7: laptop berpindah IP, app menemukan lagi lewat discovery (D5, D6).
// Yang dipakai asli: EndpointResolver, HttpStatusRepository, ConnectionController
// dan AgentHttpClient (di atas MockClient). Yang palsu: discovery mDNS, sumber
// perubahan jaringan, jadwal timer, dan "jaringan" (MockClient).

const _token = 'test-token';
const _port = 8765;
const _oldHost = '192.168.1.10';
const _newHost = '192.168.1.20';
const _agentA = 'a1b2c3d4e5f60718293a4b5c6d7e8f90';
const _agentB = 'b1c2d3e4f5061728394a5b6c7d8e9fa0';

PairingData _pairing({String host = _oldHost}) => PairingData(
  host: host,
  port: _port,
  token: _token,
  laptopName: 'Laptop-Kamil',
  agentId: _agentA,
);

DiscoveredAgent _found(String agentId, String host) =>
    DiscoveredAgent(agentId: agentId, host: host, port: _port, name: 'Laptop');

/// Jaringan palsu untuk `MockClient`. Hanya alamat di [reachable] yang
/// menjawab; tiap alamat menjawab dengan [agentIdByHost]. Setiap permintaan
/// dicatat di [requestedHosts].
final class _Lan {
  _Lan({required this.agentIdByHost, required Set<String> reachable})
    : reachable = Set.of(reachable);

  final Map<String, String> agentIdByHost;
  final Set<String> reachable;
  final List<String> requestedHosts = [];

  /// Bila di-set, permintaan berikutnya menunggu future ini sebelum dijawab.
  Completer<void>? holdNext;

  late final http.Client client = MockClient(_handle);

  Future<http.Response> _handle(http.Request request) async {
    final host = request.url.host;
    requestedHosts.add(host);

    final hold = holdNext;
    if (hold != null) {
      holdNext = null;
      await hold.future;
    }

    if (!reachable.contains(host)) {
      throw SocketException('tidak terjangkau: $host');
    }
    if (request.url.path != '/api/v1/status') {
      return http.Response('{}', 404);
    }
    if (request.headers['Authorization'] != 'Bearer $_token') {
      return http.Response(
        jsonEncode({
          'error': {'code': 'unauthorized', 'message': 'fake error'},
        }),
        401,
      );
    }
    return http.Response(
      jsonEncode({
        'data': {
          'name': 'Laptop-Kamil',
          'version': '1.0.0',
          'uptimeSeconds': 0,
          'volume': {'level': 35, 'muted': false},
          'pending': null,
          'agentId': agentIdByHost[host],
        },
      }),
      200,
      headers: {'content-type': 'application/json'},
    );
  }
}

final class _Harness {
  _Harness({
    required this.container,
    required this.scheduler,
    required this.storage,
    required this.lan,
    required this.discovery,
    required this.network,
  });

  final ProviderContainer container;
  final FakePollScheduler scheduler;
  final InMemoryConnectionStorage storage;
  final _Lan lan;
  final FakeAgentDiscovery discovery;
  final FakeNetworkChangeSource network;

  PairingData? get pairing => container.read(pairingProvider);

  /// Satu perubahan lifecycle aplikasi ke pohon widget.
  Future<void> lifecycle(WidgetTester tester, AppLifecycleState state) async {
    tester.binding.handleAppLifecycleStateChanged(state);
    await _settle(tester);
  }

  /// Satu event jaringan, lalu debounce-nya dijalankan (D6 poin 3).
  Future<void> networkChange(WidgetTester tester) async {
    network.emit();
    await _settle(tester);
    scheduler.fireOnce(RBehavior.networkChangeDebounce);
    await _settle(tester);
  }
}

/// Menunggu future palsu selesai, lalu membangun ulang frame.
Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(() => pumpEventQueue());
  await tester.pumpAndSettle();
}

Future<_Harness> _pumpApp(
  WidgetTester tester, {
  required PairingData pairing,
  required _Lan lan,
  required FakeAgentDiscovery discovery,
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
  final storage = InMemoryConnectionStorage(pairing);
  final network = FakeNetworkChangeSource();
  addTearDown(network.close);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        initialPairingProvider.overrideWithValue(pairing),
        connectionStorageProvider.overrideWithValue(storage),
        // Resolver dan status repository asli; hanya transport yang palsu.
        agentHttpClientProvider.overrideWithValue(AgentHttpClient(lan.client)),
        agentDiscoveryProvider.overrideWithValue(discovery),
        networkChangeSourceProvider.overrideWithValue(network),
        pollSchedulerProvider.overrideWithValue(scheduler),
        volumeOverride(),
        powerRepositoryProvider.overrideWithValue(FakePowerRepository()),
      ],
      child: const RemottoApp(),
    ),
  );
  await _settle(tester);

  final container = ProviderScope.containerOf(
    tester.element(find.byType(RemottoApp)),
  );
  return _Harness(
    container: container,
    scheduler: scheduler,
    storage: storage,
    lan: lan,
    discovery: discovery,
    network: network,
  );
}

ConnectionPhase _phase(_Harness h) =>
    h.container.read(connectionControllerProvider).phase;

/// S10: pill offline, panel offline, label a11y offline.
void _expectOffline() {
  expect(find.text(RemoteStrings.pillOffline), findsOneWidget);
  expect(find.bySemanticsLabel(RemoteStrings.pillOfflineA11y), findsOneWidget);
  expect(find.text('Laptop nggak kejangkau'), findsOneWidget);
}

/// S11: pill "nyambung lagi" and the info toast.
void _expectBack() {
  expect(find.text('NYAMBUNG LAGI'), findsOneWidget);
  expect(find.bySemanticsLabel(RemoteStrings.pillBackA11y), findsOneWidget);
  expect(find.text('Laptop nyambung lagi'), findsOneWidget);
  expect(find.text('Laptop nggak kejangkau'), findsNothing);
}

/// S01: pill online with uptime, no offline panel.
void _expectOnline() {
  expect(find.text('NYAMBUNG · 0M'), findsOneWidget);
  expect(find.bySemanticsLabel(RemoteStrings.pillOnlineA11y), findsOneWidget);
  expect(find.text('Laptop nggak kejangkau'), findsNothing);
}

void main() {
  testWidgets(
    'S10 -> endpoint baru ditemukan -> S11 -> S01; host dan port berganti, token dan agentId tetap',
    (tester) async {
      final lan = _Lan(
        agentIdByHost: {_newHost: _agentA},
        reachable: {_newHost},
      );
      // Panggilan pertama (poll gagal) belum menemukan laptop; panggilan kedua
      // (event jaringan) menemukan alamat baru.
      final discovery = FakeAgentDiscovery(
        resultsPerCall: [
          const [],
          [_found(_agentA, _newHost)],
        ],
      );
      final h = await _pumpApp(
        tester,
        pairing: _pairing(),
        lan: lan,
        discovery: discovery,
      );

      // Poll pertama gagal: menyambung, discovery sudah jalan sekali.
      expect(_phase(h), ConnectionPhase.connecting);
      expect(discovery.callCount, 1);

      // Poll periodik kedua gagal: offline (S10). Rediscover dibatasi 15 dtk.
      h.scheduler.tick();
      await _settle(tester);
      expect(_phase(h), ConnectionPhase.offline);
      _expectOffline();
      expect(discovery.callCount, 1);

      // Wi-Fi berganti: discovery menemukan alamat baru, status sukses di sana.
      await h.networkChange(tester);
      expect(discovery.callCount, 2);
      expect(lan.requestedHosts, contains(_newHost));

      // Poll ke host baru berhasil: S11 dulu, lalu S01 setelah pill 2 dtk.
      expect(_phase(h), ConnectionPhase.back);
      _expectBack();

      h.scheduler.fireOnce(RBehavior.reconnectedPill);
      await _settle(tester);
      expect(_phase(h), ConnectionPhase.online);
      _expectOnline();

      expect(h.storage.data, _pairing(host: _newHost));
      expect(h.pairing, _pairing(host: _newHost));
      expect(h.pairing?.token, _token);
      expect(h.pairing?.agentId, _agentA);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'agentId beda dari yang tersimpan: tetap S10, pairing tak berubah, alamat baru tak dihubungi',
    (tester) async {
      final lan = _Lan(
        agentIdByHost: {_newHost: _agentB},
        reachable: {_newHost},
      );
      final discovery = FakeAgentDiscovery(
        resultsPerCall: [
          [_found(_agentB, _newHost)],
          [_found(_agentB, _newHost)],
        ],
      );
      final original = _pairing();
      final h = await _pumpApp(
        tester,
        pairing: original,
        lan: lan,
        discovery: discovery,
      );

      h.scheduler.tick();
      await _settle(tester);
      expect(_phase(h), ConnectionPhase.offline);
      _expectOffline();

      await h.networkChange(tester);

      // Discovery dipanggil lagi, tetapi kandidat B dibuang sebelum diverifikasi.
      expect(discovery.callCount, 2);
      expect(lan.requestedHosts, isNot(contains(_newHost)));
      expect(_phase(h), ConnectionPhase.offline);
      _expectOffline();
      expect(find.text('Laptop nyambung lagi'), findsNothing);

      expect(h.pairing, original);
      expect(h.storage.data, original);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'resume dari background dengan IP berubah: S02 saat menunggu, lalu S01 di alamat baru',
    (tester) async {
      final lan = _Lan(
        agentIdByHost: {_oldHost: _agentA, _newHost: _agentA},
        reachable: {_oldHost},
      );
      final discovery = FakeAgentDiscovery(
        resultsPerCall: [
          [_found(_agentA, _newHost)],
        ],
      );
      final h = await _pumpApp(
        tester,
        pairing: _pairing(),
        lan: lan,
        discovery: discovery,
      );
      _expectOnline();

      await h.lifecycle(tester, AppLifecycleState.paused);

      // Selama di background laptop pindah ke alamat baru.
      lan.reachable
        ..remove(_oldHost)
        ..add(_newHost);

      // Poll pertama setelah resume ditahan supaya S02 terlihat.
      final hold = Completer<void>();
      lan.holdNext = hold;
      await h.lifecycle(tester, AppLifecycleState.resumed);

      expect(_phase(h), ConnectionPhase.connecting);
      expect(find.text(RemoteStrings.pillConnecting), findsOneWidget);
      expect(find.text('Nunggu jawaban dari laptop…'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RemoteStrings.pillConnectingA11y),
        findsOneWidget,
      );
      expect(h.scheduler.hasLiveOnce(RBehavior.resumeWait), isTrue);
      expect(discovery.callCount, 0);

      // Poll lama ke alamat lama gagal: discovery menemukan alamat baru,
      // poll ulang ke sana, dan layar kembali S01 tanpa melewati offline.
      hold.complete();
      await _settle(tester);

      expect(discovery.callCount, 1);
      expect(_phase(h), ConnectionPhase.online);
      _expectOnline();
      expect(find.text('Nunggu jawaban dari laptop…'), findsNothing);
      expect(h.storage.data, _pairing(host: _newHost));
      expect(h.pairing?.token, _token);
      expect(h.pairing?.agentId, _agentA);
      expect(lan.requestedHosts.last, _newHost);
      expect(tester.takeException(), isNull);
    },
  );
}
