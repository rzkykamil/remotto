import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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
      discovery = await startDiscovery(
        agentServiceType,
        autoResolve: true,
        ipLookupType: IpLookupType.v4,
      );
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
        await _stopQuietly(discovery);
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
        txt: _decodeTxt(service.txt),
        addresses: addresses,
        port: service.port ?? 0,
      );
    } on Object {
      return null;
    }
  }

  /// Malformed UTF-8 values are dropped; their keys then count as missing.
  Map<String, String> _decodeTxt(Map<String, Uint8List?>? raw) {
    final decoded = <String, String>{};
    if (raw == null) return decoded;
    raw.forEach((key, value) {
      if (value == null) return;
      try {
        decoded[key] = utf8.decode(value, allowMalformed: false);
      } on FormatException {
        // Skip this key.
      }
    });
    return decoded;
  }

  Future<void> _stopQuietly(Discovery discovery) async {
    try {
      await stopDiscovery(discovery);
    } on Object {
      // Nothing to recover; the session is already over.
    }
  }
}
