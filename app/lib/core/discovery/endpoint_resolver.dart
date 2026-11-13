import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../connection/connection_providers.dart';
import '../network/agent_http_client.dart';
import '../network/api_failure.dart';
import '../network/network_providers.dart';
import '../storage/pairing_data.dart';
import '../storage/storage_providers.dart';
import '../theme/r_behavior.dart';
import 'agent_discovery.dart';
import 'discovery_candidate.dart';
import 'discovery_providers.dart';

/// Outcome of one rediscovery run (D6).
enum RediscoverResult {
  /// Nothing changed: no candidate passed, discovery was skipped, or the
  /// pairing has no agentId yet (legacy).
  none,

  /// A candidate with the stored agentId answered `GET /status` with the
  /// same token. Host and port were saved; token and name are unchanged.
  updated,

  /// The candidate with the stored agentId answered 401. The token was reset
  /// on the laptop, so the app must enter the re-pairing flow (BR-9).
  tokenRejected,
}

/// Maximum number of candidates verified in one run (D5 / T5).
const _maxCandidates = 3;

/// Finds the paired laptop again on the local network when its IP changed.
///
/// Only candidates that pass [selectCandidates] are verified with
/// `GET /status` using the stored token. The endpoint is saved only after the
/// agentId in the response matches the stored one (D5). Nothing is logged:
/// the token and candidate hosts stay out of the logs.
///
/// `interface class` (not `final`) so tests can replace it with a fake.
interface class EndpointResolver {
  EndpointResolver(this._ref);

  final Ref _ref;

  Future<RediscoverResult>? _inFlight;
  DateTime? _lastStarted;

  /// Runs one rediscovery. [force] skips the [RBehavior.discoveryInterval]
  /// gate (network change, D6 point 3). A run already in progress is shared:
  /// the same future is returned and no second discovery starts.
  Future<RediscoverResult> rediscover({bool force = false}) {
    final running = _inFlight;
    if (running != null) return running;

    final pairing = _ref.read(pairingProvider);
    final agentId = pairing?.agentId;
    if (pairing == null || agentId == null) {
      return Future.value(RediscoverResult.none);
    }

    final now = _ref.read(connectionClockProvider)();
    final last = _lastStarted;
    if (!force &&
        last != null &&
        now.difference(last) < RBehavior.discoveryInterval) {
      return Future.value(RediscoverResult.none);
    }
    _lastStarted = now;

    final future = _execute(
      pairing,
      agentId,
    ).whenComplete(() => _inFlight = null);
    _inFlight = future;
    return future;
  }

  Future<RediscoverResult> _execute(PairingData pairing, String agentId) async {
    try {
      final found = await _ref
          .read(agentDiscoveryProvider)
          .find(timeout: RBehavior.discoveryTimeout);
      final candidates = selectCandidates(
        found,
        agentId: agentId,
        currentHost: pairing.host,
        currentPort: pairing.port,
      );

      final client = _ref.read(agentHttpClientProvider);
      for (final candidate in candidates.take(_maxCandidates)) {
        final verified = await _verify(client, candidate, pairing.token);
        if (verified == _Verdict.rejected) {
          return RediscoverResult.tokenRejected;
        }
        if (verified != _Verdict.matched) continue;

        // The user may have re-paired during the run. Save only if the stored
        // pairing still belongs to the same agent with the same token.
        final current = _ref.read(pairingProvider);
        if (current == null ||
            current.agentId != agentId ||
            current.token != pairing.token) {
          return RediscoverResult.none;
        }
        await _ref
            .read(pairingProvider.notifier)
            .updateEndpoint(host: candidate.host, port: candidate.port);
        return RediscoverResult.updated;
      }
      return RediscoverResult.none;
    } on Object {
      return RediscoverResult.none;
    }
  }

  Future<_Verdict> _verify(
    AgentHttpClient client,
    DiscoveredAgent candidate,
    String token,
  ) async {
    try {
      final status = await client.getStatus(
        host: candidate.host,
        port: candidate.port,
        token: token,
        timeout: RBehavior.stepTimeout,
      );
      return status.agentId == candidate.agentId
          ? _Verdict.matched
          : _Verdict.skipped;
    } on UnauthorizedFailure {
      return _Verdict.rejected;
    } on ApiFailure {
      return _Verdict.skipped;
    }
  }
}

enum _Verdict { matched, rejected, skipped }
