import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:remotto/core/connection/connection_providers.dart';
import 'package:remotto/core/discovery/agent_discovery.dart';
import 'package:remotto/core/discovery/discovery_providers.dart';
import 'package:remotto/core/discovery/endpoint_resolver.dart';
import 'package:remotto/core/network/agent_http_client.dart';
import 'package:remotto/core/network/network_providers.dart';
import 'package:remotto/core/storage/pairing_data.dart';
import 'package:remotto/core/storage/storage_providers.dart';
import 'package:remotto/core/theme/r_behavior.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_agent_discovery.dart';
import '../../support/fakes.dart';

const _agentId = '0123456789abcdef0123456789abcdef';
const _otherAgentId = 'fedcba9876543210fedcba9876543210';
const _token =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
const _otherToken =
    'fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210';

const _oldHost = '192.168.1.10';
const _oldPort = 8765;
const _newHost = '192.168.1.20';
const _newPort = 9000;

const _legacy = PairingData(
  host: _oldHost,
  port: _oldPort,
  token: _token,
  laptopName: 'Laptop-Kamil',
);

const _paired = PairingData(
  host: _oldHost,
  port: _oldPort,
  token: _token,
  laptopName: 'Laptop-Kamil',
  agentId: _agentId,
);

DiscoveredAgent _found({
  String agentId = _agentId,
  String host = _newHost,
  int port = _newPort,
}) => DiscoveredAgent(agentId: agentId, host: host, port: port);

http.Response _statusResponse({String agentId = _agentId}) {
  return http.Response(
    jsonEncode({
      'data': {
        'name': 'Laptop-Kamil',
        'version': '1.0.0',
        'uptimeSeconds': 120,
        'volume': {'level': 35, 'muted': false},
        'pending': null,
        'agentId': agentId,
      },
    }),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}

http.Response _errorResponse(int status, String code) => http.Response(
  jsonEncode({
    'error': {'code': code},
  }),
  status,
  headers: {'content-type': 'application/json'},
);

/// The stored pairing after a re-pair: same laptop, other token or agentId.
PairingData _repairedWith({String token = _token, String agentId = _agentId}) =>
    PairingData(
      host: _oldHost,
      port: _oldPort,
      token: token,
      laptopName: 'Laptop-Kamil',
      agentId: agentId,
    );

/// Preferences for the save path (save clears the last power command).
late SharedPreferences _prefs;

final class _Clock {
  DateTime now = DateTime(2026, 11, 13, 10);
}

/// Wiring for one test: container, fake discovery, and every request the
/// HTTP client sees. [handler] answers each request; it may await, so a test
/// can re-pair the laptop before the reply.
final class _Harness {
  _Harness({
    required PairingData? pairing,
    required this.discovery,
    required FutureOr<http.Response> Function(http.Request request) handler,
  }) : storage = InMemoryConnectionStorage(pairing) {
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(_prefs),
        initialPairingProvider.overrideWithValue(pairing),
        connectionStorageProvider.overrideWithValue(storage),
        agentDiscoveryProvider.overrideWithValue(discovery),
        agentHttpClientProvider.overrideWithValue(
          AgentHttpClient(
            MockClient((request) async {
              requests.add(request);
              return handler(request);
            }),
          ),
        ),
        connectionClockProvider.overrideWithValue(() => clock.now),
      ],
    );
  }

  final FakeAgentDiscovery discovery;
  final InMemoryConnectionStorage storage;
  final _Clock clock = _Clock();
  final List<http.Request> requests = [];
  late final ProviderContainer container;

  EndpointResolver get resolver => container.read(endpointResolverProvider);

  PairingData? get pairing => container.read(pairingProvider);

  void dispose() => container.dispose();
}

_Harness _harness({
  PairingData? pairing = _paired,
  List<List<DiscoveredAgent>> results = const [],
  Completer<void>? gate,
  FutureOr<http.Response> Function(http.Request request)? handler,
}) {
  return _Harness(
    pairing: pairing,
    discovery: FakeAgentDiscovery(resultsPerCall: results, gate: gate),
    handler: handler ?? (_) => _statusResponse(),
  );
}

void main() {
  group('rediscover', () {
    late _Harness h;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      _prefs = await SharedPreferences.getInstance();
    });

    tearDown(() => h.dispose());

    test('updates host and port after a matching agentId and keeps the token '
        'and name', () async {
      h = _harness(
        results: [
          [_found()],
        ],
      );

      final result = await h.resolver.rediscover();

      expect(result, RediscoverResult.updated);
      expect(h.pairing!.host, _newHost);
      expect(h.pairing!.port, _newPort);
      expect(h.pairing!.token, _token);
      expect(h.pairing!.laptopName, 'Laptop-Kamil');
      expect(h.pairing!.agentId, _agentId);
      expect(h.storage.data, h.pairing);

      expect(h.requests, hasLength(1));
      final request = h.requests.single;
      expect(request.url.host, _newHost);
      expect(request.url.port, _newPort);
      expect(request.url.path, '/api/v1/status');
      expect(request.headers['Authorization'], 'Bearer $_token');
    });

    test(
      'drops a candidate whose status answers with another agentId',
      () async {
        h = _harness(
          results: [
            [_found()],
          ],
          handler: (_) => _statusResponse(agentId: _otherAgentId),
        );

        expect(await h.resolver.rediscover(), RediscoverResult.none);
        expect(h.pairing, _paired);
        expect(h.storage.data, _paired);
        expect(h.requests, hasLength(1));
      },
    );

    test(
      'ignores a candidate whose agentId differs from the stored one',
      () async {
        h = _harness(
          results: [
            [_found(agentId: _otherAgentId)],
          ],
        );

        expect(await h.resolver.rediscover(), RediscoverResult.none);
        expect(h.pairing, _paired);
        expect(h.requests, isEmpty);
      },
    );

    test(
      'a 401 from the matching agent gives tokenRejected and saves nothing',
      () async {
        h = _harness(
          results: [
            [_found(), _found(host: '192.168.1.30', port: 9001)],
          ],
          handler: (request) => request.url.host == _newHost
              ? http.Response(
                  jsonEncode({
                    'error': {'code': 'invalid_token'},
                  }),
                  401,
                  headers: {'content-type': 'application/json'},
                )
              : _statusResponse(),
        );

        expect(await h.resolver.rediscover(), RediscoverResult.tokenRejected);
        expect(h.pairing, _paired);
        expect(h.storage.data, _paired);
        // The next candidate is not asked once the token is known to be reset.
        expect(h.requests, hasLength(1));
      },
    );

    test(
      'a 401 gives none when the token was replaced during the run',
      () async {
        h = _harness(
          results: [
            [_found()],
          ],
          handler: (request) async {
            await h.container
                .read(pairingProvider.notifier)
                .save(_repairedWith(token: _otherToken));
            return _errorResponse(401, 'invalid_token');
          },
        );

        expect(await h.resolver.rediscover(), RediscoverResult.none);
        expect(h.pairing, _repairedWith(token: _otherToken));
        expect(h.storage.data, _repairedWith(token: _otherToken));
        expect(h.requests, hasLength(1));
      },
    );

    test(
      'a 401 gives none when the agentId was replaced during the run',
      () async {
        h = _harness(
          results: [
            [_found()],
          ],
          handler: (request) async {
            await h.container
                .read(pairingProvider.notifier)
                .save(_repairedWith(agentId: _otherAgentId));
            return _errorResponse(401, 'invalid_token');
          },
        );

        expect(await h.resolver.rediscover(), RediscoverResult.none);
        expect(h.pairing, _repairedWith(agentId: _otherAgentId));
        expect(h.requests, hasLength(1));
      },
    );

    for (final (name, reply)
        in <(String, FutureOr<http.Response> Function(http.Request))>[
          ('403 forbidden', (_) => _errorResponse(403, 'forbidden')),
          ('429 rate limited', (_) => _errorResponse(429, 'rate_limited')),
          ('500 server error', (_) => _errorResponse(500, 'internal_error')),
          ('timeout', (_) => throw TimeoutException('slow')),
          (
            'socket unreachable',
            (_) => throw const SocketException('unreachable'),
          ),
        ]) {
      test(
        'a candidate answering $name is skipped and the pairing stays unchanged',
        () async {
          h = _harness(
            results: [
              [_found()],
            ],
            handler: reply,
          );

          expect(await h.resolver.rediscover(), RediscoverResult.none);
          expect(h.pairing, _paired);
          expect(h.storage.data, _paired);
          expect(h.requests, hasLength(1));
        },
      );
    }

    test(
      'a legacy pairing without agentId gives none and runs no discovery',
      () async {
        h = _harness(pairing: _legacy);

        expect(await h.resolver.rediscover(force: true), RediscoverResult.none);
        expect(h.discovery.callCount, 0);
        expect(h.requests, isEmpty);
        expect(h.pairing, _legacy);
      },
    );

    test('without a pairing gives none and runs no discovery', () async {
      h = _harness(pairing: null);

      expect(await h.resolver.rediscover(force: true), RediscoverResult.none);
      expect(h.discovery.callCount, 0);
    });

    test('a candidate on the current endpoint is not verified', () async {
      h = _harness(
        results: [
          [_found(host: _oldHost, port: _oldPort)],
        ],
      );

      expect(await h.resolver.rediscover(), RediscoverResult.none);
      expect(h.requests, isEmpty);
      expect(h.pairing, _paired);
    });

    test('public IPv4 and IPv6 hosts are ignored, and so is Tailscale CGNAT '
        '(D5)', () async {
      h = _harness(
        results: [
          [
            _found(host: '8.8.8.8'),
            _found(host: 'fe80::1'),
            _found(host: '100.64.0.5'),
          ],
        ],
      );

      expect(await h.resolver.rediscover(), RediscoverResult.none);
      expect(h.requests, isEmpty);
      expect(h.pairing, _paired);
    });

    test(
      'a failing candidate is skipped and the next one can succeed',
      () async {
        h = _harness(
          results: [
            [_found(), _found(host: '192.168.1.30', port: 9001)],
          ],
          handler: (request) => request.url.host == _newHost
              ? http.Response('boom', 500)
              : _statusResponse(),
        );

        expect(await h.resolver.rediscover(), RediscoverResult.updated);
        expect(h.pairing!.host, '192.168.1.30');
        expect(h.pairing!.port, 9001);
        expect(h.requests, hasLength(2));
      },
    );

    test('verifies at most three candidates', () async {
      h = _harness(
        results: [
          [for (var i = 21; i <= 24; i++) _found(host: '192.168.1.$i')],
        ],
        handler: (_) => _statusResponse(agentId: _otherAgentId),
      );

      expect(await h.resolver.rediscover(), RediscoverResult.none);
      expect(h.requests, hasLength(3));
      expect(h.pairing, _paired);
    });

    test('uses discoveryTimeout for the search', () async {
      h = _harness();

      await h.resolver.rediscover(force: true);
      expect(h.discovery.timeouts, [RBehavior.discoveryTimeout]);
    });

    test(
      'a non-forced run waits for discoveryInterval before running again',
      () async {
        h = _harness();

        await h.resolver.rediscover();
        expect(h.discovery.callCount, 1);

        h.clock.now = h.clock.now.add(const Duration(seconds: 5));
        expect(await h.resolver.rediscover(), RediscoverResult.none);
        expect(h.discovery.callCount, 1);

        h.clock.now = h.clock.now.add(const Duration(seconds: 10));
        await h.resolver.rediscover();
        expect(h.discovery.callCount, 2);
      },
    );

    test('force bypasses discoveryInterval', () async {
      h = _harness();

      await h.resolver.rediscover();
      h.clock.now = h.clock.now.add(const Duration(seconds: 1));
      await h.resolver.rediscover(force: true);
      expect(h.discovery.callCount, 2);
    });

    test('concurrent calls share one run and one discovery', () async {
      final gate = Completer<void>();
      h = _harness(
        results: [
          [_found()],
        ],
        gate: gate,
      );

      final first = h.resolver.rediscover();
      final second = h.resolver.rediscover(force: true);
      expect(identical(first, second), isTrue);

      gate.complete();
      expect(await first, RediscoverResult.updated);
      expect(await second, RediscoverResult.updated);
      expect(h.discovery.callCount, 1);
    });

    test('a new run is allowed after the previous one finished', () async {
      h = _harness();

      await h.resolver.rediscover();
      await h.resolver.rediscover(force: true);
      expect(h.discovery.callCount, 2);
    });
  });
}
