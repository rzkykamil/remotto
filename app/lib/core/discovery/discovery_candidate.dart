import 'dart:convert';
import 'dart:typed_data';

import 'agent_discovery.dart';

/// DNS-SD service type advertised by the agent (technical-spec, D3).
const agentServiceType = '_remotto._tcp';

const _maxNameLength = 32;

final _agentIdPattern = RegExp(r'^[0-9a-f]{32}$');
final _ipv4Pattern = RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$');

/// Turns one resolved mDNS service into a candidate (D5 points 1 and 3).
///
/// Returns null when TXT `v` is not `1`, TXT `id` is not 32 lowercase hex,
/// no IPv4 address is in a private range (BR-12), or [port] is outside
/// 1-65535. IPv6 addresses are ignored. The agentId match against the stored
/// value is done later in [selectCandidates].
DiscoveredAgent? parseCandidate({
  required Map<String, String> txt,
  required List<String> addresses,
  required int port,
}) {
  if (txt['v'] != '1') return null;

  final agentId = txt['id'];
  if (agentId == null || !_agentIdPattern.hasMatch(agentId)) return null;

  if (port < 1 || port > 65535) return null;

  final host = _firstPrivateIpv4(addresses);
  if (host == null) return null;

  return DiscoveredAgent(
    agentId: agentId,
    host: host,
    port: port,
    name: _cleanName(txt['name']),
  );
}

/// Keeps candidates whose agentId equals [agentId] (D5 point 2) and whose
/// endpoint differs from the stored one (D5 point 4). Duplicate endpoints
/// are removed so each one is verified at most once. A host that is not a
/// private IPv4 address is dropped too (D5 point 3, checked again here
/// because a [DiscoveredAgent] may come from anywhere).
List<DiscoveredAgent> selectCandidates(
  List<DiscoveredAgent> candidates, {
  required String agentId,
  required String currentHost,
  required int currentPort,
}) {
  final seen = <String>{};
  final selected = <DiscoveredAgent>[];
  for (final candidate in candidates) {
    if (candidate.agentId != agentId) continue;
    if (candidate.host == currentHost && candidate.port == currentPort) {
      continue;
    }
    if (!_isPrivateHost(candidate.host)) continue;
    if (!seen.add('${candidate.host}:${candidate.port}')) continue;
    selected.add(candidate);
  }
  return selected;
}

bool _isPrivateHost(String host) {
  final octets = _parseIpv4(host);
  return octets != null && _isPrivate(octets);
}

String? _firstPrivateIpv4(List<String> addresses) {
  for (final address in addresses) {
    final octets = _parseIpv4(address);
    if (octets != null && _isPrivate(octets)) return address;
  }
  return null;
}

/// Dotted-decimal IPv4. Leading zeros are rejected as ambiguous.
List<int>? _parseIpv4(String input) {
  final match = _ipv4Pattern.firstMatch(input);
  if (match == null) return null;
  final octets = <int>[];
  for (var i = 1; i <= 4; i++) {
    final part = match.group(i)!;
    if (part.length > 1 && part.startsWith('0')) return null;
    final value = int.parse(part);
    if (value > 255) return null;
    octets.add(value);
  }
  return octets;
}

/// Only 10/8, 172.16/12 and 192.168/16 (D5). Unlike the manual input check,
/// 100.64/10 is excluded here.
bool _isPrivate(List<int> o) {
  final a = o[0];
  final b = o[1];
  if (a == 10) return true;
  if (a == 172 && b >= 16 && b <= 31) return true;
  return a == 192 && b == 168;
}

/// Decodes raw TXT values as UTF-8. A null value is skipped. Malformed UTF-8
/// drops only its own key, so the key then counts as missing.
Map<String, String> decodeTxt(Map<String, Uint8List?>? raw) {
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

String? _cleanName(String? raw) {
  final name = raw?.trim();
  if (name == null || name.isEmpty) return null;
  return name.length > _maxNameLength
      ? name.substring(0, _maxNameLength)
      : name;
}
