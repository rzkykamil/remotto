import 'dart:async';
import 'dart:io';

import 'package:nsd/nsd.dart';

import 'agent_discovery.dart';
import 'discovery_candidate.dart';

/// [AgentDiscovery] backed by the `nsd` plugin (Bonjour on iOS, NsdManager
/// on Android). Only the platform plugin is touched here; the rules live in
/// discovery_candidate.dart.
final class NsdAgentDiscovery implements AgentDiscovery {
  const NsdAgentDiscovery();

  @override
  Future<List<DiscoveredAgent>> find({required Duration timeout}) async {
    Discovery? discovery;
    try {
      final starting = startDiscovery(
        agentServiceType,
        autoResolve: true,
        ipLookupType: IpLookupType.v4,
      );
      try {
        discovery = await starting.timeout(timeout);
      } on TimeoutException {
        // A session that starts late must still be stopped, or it leaks.
        unawaited(
          starting.then(
            (late) => _stopQuietly(late, timeout),
            onError: (Object _) {},
          ),
        );
        rethrow;
      }
      await Future<void>.delayed(timeout);

      final found = <DiscoveredAgent>[];
      for (final service in discovery.services) {
        final candidate = _parseService(service);
        if (candidate != null) found.add(candidate);
      }
      return found;
    } on Object {
      return const [];
    } finally {
      if (discovery != null) {
        await _stopQuietly(discovery, timeout);
      }
    }
  }

  /// Services that failed to resolve never reach `services`; a service that
  /// cannot be read here is simply skipped.
  DiscoveredAgent? _parseService(Service service) {
    try {
      final addresses = <String>[
        for (final address in service.addresses ?? const <InternetAddress>[])
          address.address,
      ];
      return parseCandidate(
        txt: decodeTxt(service.txt),
        addresses: addresses,
        port: service.port ?? 0,
      );
    } on Object {
      return null;
    }
  }

  Future<void> _stopQuietly(Discovery discovery, Duration timeout) async {
    try {
      await stopDiscovery(discovery).timeout(timeout);
    } on Object {
      // Nothing to recover; the session is already over.
    }
  }
}
