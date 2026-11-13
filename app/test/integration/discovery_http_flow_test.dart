import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:remotto/core/connection/connection_controller.dart';
import 'package:remotto/core/connection/connection_providers.dart';
import 'package:remotto/core/connection/connection_state.dart';
import 'package:remotto/core/discovery/agent_discovery.dart';
import 'package:remotto/core/discovery/discovery_providers.dart';
import 'package:remotto/core/network/agent_http_client.dart';
import 'package:remotto/core/network/network_providers.dart';
import 'package:remotto/core/storage/pairing_data.dart';
import 'package:remotto/core/storage/storage_providers.dart';
import 'package:remotto/core/theme/r_behavior.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_agent_discovery.dart';
import '../support/fake_network_change_source.dart';
import '../support/fake_poll_scheduler.dart';
import '../support/fakes.dart';
import '../support/loopback_rewrite_client.dart';
import 'fake_agent_server.dart';

// M7 integration: discovery over real HTTP to two loopback agents.
//
// Real: ConnectionController, EndpointResolver, HttpStatusRepository,
// AgentHttpClient, and the HTTP transport (through LoopbackRewriteClient).
// Fake: mDNS result (FakeAgentDiscovery), network events, the poll scheduler
// (timers are fired by hand), and storage (in memory).
//
// Candidate hosts are private LAN addresses (D5/BR-12). The rewrite client
// sends them to 127.0.0.1, where the second fake agent listens. The candidate
// filter itself is not changed by the test.

const _lanHost = '192.168.1.20';

/// TEST-NET-3 (RFC 5737): public, so the filter must drop it. It is mapped to
/// loopback as well, so a wrong request would reach server 2 and be counted.
const _publicHost = '203.0.113.7';

const _rewriteHosts = {_lanHost: '127.0.0.1', _publicHost: '127.0.0.1'};

const _agentA = 'a1b2c3d4e5f60718293a4b5c6d7e8f90';
const _agentB = 'b1c2d3e4f5061728394a5b6c7d8e9fa0';

PairingData _pairing({
  required int port,
  String host = '127.0.0.1',
  String? agentId = _agentA,
}) => PairingData(
  host: host,
  port: port,
  token: fakeAgentToken,
  laptopName: 'Laptop-Kamil',
  agentId: agentId,
);

DiscoveredAgent _found(String agentId, String host, FakeAgentServer server) =>
    DiscoveredAgent(
      agentId: agentId,
      host: host,
      port: server.port,
      name: 'Laptop-Kamil',
    );

Future<FakeAgentServer> _server(String? agentId) async {
  final server = await FakeAgentServer.start();
  server.agentId = agentId;
  return server;
}

/// Container with the real controller and resolver, plus the fakes above.
final class _Flow {
  _Flow._({
    required this.container,
    required this.scheduler,
    required this.storage,
    required this.discovery,
    required this.network,
    required this.rewrite,
    required this.s1,
    required this.s2,
  });

  final ProviderContainer container;
  final FakePollScheduler scheduler;
  final InMemoryConnectionStorage storage;
  final FakeAgentDiscovery discovery;
  final FakeNetworkChangeSource network;
  final LoopbackRewriteClient rewrite;

  /// Laptop before the IP change (the stored endpoint).
  final FakeAgentServer s1;

  /// Laptop after the IP change (the discovery candidate).
  final FakeAgentServer s2;

  static Future<_Flow> open({
    required FakeAgentServer s1,
    required FakeAgentServer s2,
    required PairingData pairing,
    required List<List<DiscoveredAgent>> discoveryResults,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final rewrite = LoopbackRewriteClient(http.Client(), _rewriteHosts);
    final scheduler = FakePollScheduler();
    final storage = InMemoryConnectionStorage(pairing);
    final discovery = FakeAgentDiscovery(resultsPerCall: discoveryResults);
    final network = FakeNetworkChangeSource();
    final container = ProviderContainer(
      overrides: [
        // Read when offline (lastPowerCommand), so it must be overridden.
        sharedPreferencesProvider.overrideWithValue(prefs),
        initialPairingProvider.overrideWithValue(pairing),
        connectionStorageProvider.overrideWithValue(storage),
        agentHttpClientProvider.overrideWithValue(AgentHttpClient(rewrite)),
        agentDiscoveryProvider.overrideWithValue(discovery),
        networkChangeSourceProvider.overrideWithValue(network),
        pollSchedulerProvider.overrideWithValue(scheduler),
      ],
    );
    return _Flow._(
      container: container,
      scheduler: scheduler,
      storage: storage,
      discovery: discovery,
      network: network,
      rewrite: rewrite,
      s1: s1,
      s2: s2,
    );
  }

  Future<void> dispose() async {
    container.dispose();
    await network.close();
    rewrite.close();
    await s1.close();
    await s2.close();
  }

  ConnectionController get ctrl =>
      container.read(connectionControllerProvider.notifier);

  ConnectionPhase get phase =>
      container.read(connectionControllerProvider).phase;

  PairingData? get pairing => container.read(pairingProvider);

  /// Starts polling and waits for the first poll.
  Future<void> start() {
    ctrl.start();
    return ctrl.pollOnce();
  }

  /// One network event, then its debounce timer (D6 point 3). The event is
  /// delivered through a stream, so the queue is flushed before the timer
  /// is fired. The queue is flushed again after the timer, because the
  /// handler awaits `onLocalNetwork` before it starts discovery.
  Future<void> networkChange() async {
    network.emit();
    await pumpEventQueue();
    scheduler.fireOnce(RBehavior.networkChangeDebounce);
    await pumpEventQueue();
  }

  /// Completes when [cond] holds. It is checked on every change of the
  /// controller state or the pairing, and fails after 5 seconds.
  Future<void> until(bool Function() cond, {required String what}) {
    if (cond()) return Future<void>.value();
    final done = Completer<void>();
    void check() {
      if (!done.isCompleted && cond()) done.complete();
    }

    final subs = [
      container.listen(connectionControllerProvider, (prev, next) => check()),
      container.listen(pairingProvider, (prev, next) => check()),
    ];
    return done.future
        .timeout(
          const Duration(seconds: 5),
          onTimeout: () => fail('timed out waiting for: $what'),
        )
        .whenComplete(() {
          for (final sub in subs) {
            sub.close();
          }
        });
  }

  /// Jendela diam nyata untuk membuktikan "tidak ada request". Hasil lain
  /// selalu ditunggu lewat [until] atau [ConnectionController.pollOnce].
  Future<void> quietWindow() {
    final done = Completer<void>();
    Timer(const Duration(milliseconds: 400), done.complete);
    return done.future;
  }

  /// The laptop moves away: the old server stops answering, and two failed
  /// polls take the app to offline.
  Future<void> laptopLeavesOldAddress() async {
    await s1.close();
    await ctrl.pollOnce();
    await ctrl.pollOnce();
  }
}

void main() {
  test(
    'I2: IP changes, app finds the same agent again and saves the new endpoint',
    () async {
      final s1 = await _server(_agentA);
      final s2 = await _server(_agentA);
      final flow = await _Flow.open(
        s1: s1,
        s2: s2,
        pairing: _pairing(port: s1.port),
        discoveryResults: [
          // Failed poll: nothing found yet.
          const [],
          // Network event: the laptop answers at the new address.
          [_found(_agentA, _lanHost, s2)],
        ],
      );
      addTearDown(flow.dispose);

      await flow.start();
      expect(flow.phase, ConnectionPhase.online);

      await flow.laptopLeavesOldAddress();
      expect(flow.phase, ConnectionPhase.offline);
      expect(
        flow.discovery.callCount,
        1,
        reason: 'one run for the first failure',
      );

      await flow.networkChange();
      expect(flow.discovery.callCount, 2);
      await flow.until(() => flow.phase == ConnectionPhase.back, what: 'back');
      expect(s2.requests, greaterThan(0), reason: 'server 2 must be reached');

      flow.scheduler.fireOnce(RBehavior.reconnectedPill);
      expect(flow.phase, ConnectionPhase.online);

      final expected = _pairing(port: s2.port, host: _lanHost);
      expect(flow.pairing, expected);
      expect(flow.storage.data, expected);
      expect(flow.pairing?.token, fakeAgentToken, reason: 'token unchanged');
      expect(flow.pairing?.agentId, _agentA, reason: 'agentId unchanged');
    },
  );

  test(
    'I3a: TXT announces agentId B, candidate dropped before any request',
    () async {
      final s1 = await _server(_agentA);
      final s2 = await _server(_agentA);
      final original = _pairing(port: s1.port);
      final flow = await _Flow.open(
        s1: s1,
        s2: s2,
        pairing: original,
        discoveryResults: [
          const [],
          [_found(_agentB, _lanHost, s2)],
        ],
      );
      addTearDown(flow.dispose);

      await flow.start();
      await flow.laptopLeavesOldAddress();
      expect(flow.phase, ConnectionPhase.offline);

      await flow.networkChange();
      expect(flow.discovery.callCount, 2);
      await flow.ctrl.pollOnce();
      await flow.quietWindow();

      expect(s2.requests, 0, reason: 'TXT mismatch must not be dialled');
      expect(flow.pairing, original);
      expect(flow.storage.data, original);
      expect(flow.phase, ConnectionPhase.offline);
    },
  );

  test(
    'I3b: TXT matches, but /status of server 2 answers agentId B, rejected',
    () async {
      final s1 = await _server(_agentA);
      final s2 = await _server(_agentB);
      final original = _pairing(port: s1.port);
      final flow = await _Flow.open(
        s1: s1,
        s2: s2,
        pairing: original,
        discoveryResults: [
          const [],
          [_found(_agentA, _lanHost, s2)],
        ],
      );
      addTearDown(flow.dispose);

      await flow.start();
      await flow.laptopLeavesOldAddress();
      expect(flow.phase, ConnectionPhase.offline);

      await flow.networkChange();
      await s2.untilRequests(1);
      await flow.ctrl.pollOnce();
      await flow.quietWindow();

      expect(s2.requests, 1, reason: 'only the verification GET /status');
      expect(flow.pairing, original);
      expect(flow.storage.data, original);
      expect(flow.phase, ConnectionPhase.offline);
    },
  );

  test('I3c: server 2 answers 401 for the candidate, token rejected and polling stops', () async {
    final s1 = await _server(_agentA);
    final s2 = await _server(_agentA);
    s2.token = 'b' * 64;
    final original = _pairing(port: s1.port);
    final flow = await _Flow.open(
      s1: s1,
      s2: s2,
      pairing: original,
      discoveryResults: [
        const [],
        [_found(_agentA, _lanHost, s2)],
      ],
    );
    addTearDown(flow.dispose);

    await flow.start();
    await flow.laptopLeavesOldAddress();
    expect(flow.phase, ConnectionPhase.offline);

    await flow.networkChange();
    await flow.until(
      () => flow.phase == ConnectionPhase.tokenRejected,
      what: 'tokenRejected',
    );
    expect(flow.scheduler.periodicJob, isNull, reason: 'polling stopped');

    final before = s2.requests;
    await flow.ctrl.pollOnce();
    await flow.quietWindow();

    expect(s2.requests, before, reason: 'no request after 401');
    expect(flow.phase, ConnectionPhase.tokenRejected);
    expect(flow.pairing, original);
    expect(flow.storage.data, original);
  });

  group(
    'I3d: server 2 answers an error on the candidate, endpoint not saved',
    () {
      const degraded = {
        FakeAgentMode.forbidden: '403',
        FakeAgentMode.rateLimited: '429',
        FakeAgentMode.serverError: '500',
      };
      degraded.forEach((mode, label) {
        test('candidate answers $label: none, offline', () async {
          final s1 = await _server(_agentA);
          final s2 = await _server(_agentA);
          s2.mode = mode;
          final original = _pairing(port: s1.port);
          final flow = await _Flow.open(
            s1: s1,
            s2: s2,
            pairing: original,
            discoveryResults: [
              const [],
              [_found(_agentA, _lanHost, s2)],
            ],
          );
          addTearDown(flow.dispose);

          await flow.start();
          await flow.laptopLeavesOldAddress();
          expect(flow.phase, ConnectionPhase.offline);

          await flow.networkChange();
          await s2.untilRequests(1);
          await flow.ctrl.pollOnce();
          await flow.quietWindow();

          expect(s2.requests, 1, reason: 'only the verification request');
          expect(flow.pairing, original);
          expect(flow.storage.data, original);
          expect(flow.phase, ConnectionPhase.offline);
        });
      });
    },
  );

  test('I6 backfill: old pairing gets its agentId from the first authenticated poll', () async {
    final s1 = await _server(_agentA);
    final s2 = await _server(_agentA);
    final flow = await _Flow.open(
      s1: s1,
      s2: s2,
      pairing: _pairing(port: s1.port, agentId: null),
      discoveryResults: [
        const [],
        [_found(_agentA, _lanHost, s2)],
      ],
    );
    addTearDown(flow.dispose);

    await flow.start();
    await flow.until(
      () => flow.pairing?.agentId != null,
      what: 'agentId backfilled',
    );
    expect(flow.pairing, _pairing(port: s1.port));
    expect(flow.storage.data, _pairing(port: s1.port));
    expect(flow.phase, ConnectionPhase.online);

    // Continue with the I2 flow: after backfill, discovery works.
    await flow.laptopLeavesOldAddress();
    await flow.networkChange();
    await flow.until(() => flow.phase == ConnectionPhase.back, what: 'back');
    flow.scheduler.fireOnce(RBehavior.reconnectedPill);

    expect(flow.pairing, _pairing(port: s2.port, host: _lanHost));
    expect(flow.storage.data, _pairing(port: s2.port, host: _lanHost));
  });

  test('I6 legacy: no agentId means no discovery, pairing unchanged', () async {
    final s1 = await _server(null);
    final s2 = await _server(_agentA);
    final original = _pairing(port: s1.port, agentId: null);
    final flow = await _Flow.open(
      s1: s1,
      s2: s2,
      pairing: original,
      discoveryResults: [
        [_found(_agentA, _lanHost, s2)],
      ],
    );
    addTearDown(flow.dispose);

    await flow.start();
    expect(flow.phase, ConnectionPhase.online);
    expect(flow.pairing, original, reason: 'legacy server sends no agentId');

    await s1.close();
    for (var i = 0; i < 3; i++) {
      await flow.ctrl.pollOnce();
      await flow.networkChange();
    }
    await flow.ctrl.pollOnce();
    await flow.quietWindow();

    expect(
      flow.discovery.callCount,
      0,
      reason: 'discovery is off without agentId',
    );
    expect(flow.pairing, original);
    expect(flow.storage.data, original);
    expect(s2.requests, 0);
  });

  test(
    'BR-12: non-private candidates (loopback, public) are never contacted',
    () async {
      final s1 = await _server(_agentA);
      final s2 = await _server(_agentA);
      final original = _pairing(port: s1.port);
      final flow = await _Flow.open(
        s1: s1,
        s2: s2,
        pairing: original,
        discoveryResults: [
          [_found(_agentA, '127.0.0.1', s2), _found(_agentA, _publicHost, s2)],
        ],
      );
      addTearDown(flow.dispose);

      await flow.start();
      await flow.laptopLeavesOldAddress();
      await flow.quietWindow();

      expect(flow.discovery.callCount, 1);
      expect(s2.requests, 0, reason: 'filter must drop both candidates');
      expect(flow.pairing, original);
      expect(flow.storage.data, original);
      expect(flow.phase, ConnectionPhase.offline);
    },
  );
}
