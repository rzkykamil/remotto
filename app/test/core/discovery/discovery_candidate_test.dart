import 'dart:convert';
import 'dart:typed_data';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotto/core/discovery/agent_discovery.dart';
import 'package:remotto/core/discovery/discovery_candidate.dart';
import 'package:remotto/core/discovery/network_change_source.dart';

const _agentId = '0123456789abcdef0123456789abcdef';
const _otherAgentId = 'fedcba9876543210fedcba9876543210';

Map<String, String> _validTxt({String? id, String? name}) => {
  'v': '1',
  'id': id ?? _agentId,
  'name': ?name,
};

void main() {
  group('parseCandidate', () {
    test('accepts a valid private IPv4 announcement', () {
      final result = parseCandidate(
        txt: _validTxt(name: 'Laptop Rizky'),
        addresses: const ['192.168.1.20'],
        port: 8765,
      );

      expect(result, isNotNull);
      expect(result!.agentId, _agentId);
      expect(result.host, '192.168.1.20');
      expect(result.port, 8765);
      expect(result.name, 'Laptop Rizky');
    });

    test('accepts 10/8 and 172.16/12 addresses', () {
      expect(
        parseCandidate(
          txt: _validTxt(),
          addresses: const ['10.0.0.5'],
          port: 8765,
        )?.host,
        '10.0.0.5',
      );
      expect(
        parseCandidate(
          txt: _validTxt(),
          addresses: const ['172.31.255.1'],
          port: 8765,
        )?.host,
        '172.31.255.1',
      );
    });

    test('rejects TXT v other than 1', () {
      final txt = _validTxt()..['v'] = '2';
      expect(
        parseCandidate(txt: txt, addresses: const ['192.168.1.2'], port: 8765),
        isNull,
      );
    });

    test('rejects TXT without v', () {
      final txt = _validTxt()..remove('v');
      expect(
        parseCandidate(txt: txt, addresses: const ['192.168.1.2'], port: 8765),
        isNull,
      );
    });

    test('rejects malformed id', () {
      for (final bad in [
        '',
        '0123456789ABCDEF0123456789ABCDEF', // uppercase
        '0123456789abcdef0123456789abcde', // 31 chars
        '0123456789abcdef0123456789abcdef0', // 33 chars
        '0123456789abcdef0123456789abcdeg', // non-hex
      ]) {
        expect(
          parseCandidate(
            txt: _validTxt(id: bad),
            addresses: const ['192.168.1.2'],
            port: 8765,
          ),
          isNull,
          reason: 'id "$bad" should be rejected',
        );
      }
    });

    test('rejects TXT without id', () {
      final txt = _validTxt()..remove('id');
      expect(
        parseCandidate(txt: txt, addresses: const ['192.168.1.2'], port: 8765),
        isNull,
      );
    });

    test('ignores IPv6 and rejects when no IPv4 is present', () {
      expect(
        parseCandidate(
          txt: _validTxt(),
          addresses: const ['fe80::1', '2001:db8::1'],
          port: 8765,
        ),
        isNull,
      );
    });

    test('picks the private IPv4 when IPv6 is listed first', () {
      final result = parseCandidate(
        txt: _validTxt(),
        addresses: const ['fe80::1', '192.168.0.9'],
        port: 8765,
      );
      expect(result?.host, '192.168.0.9');
    });

    test('rejects public IPv4 addresses', () {
      for (final ip in ['8.8.8.8', '203.0.113.7', '172.15.0.1', '172.32.0.1']) {
        expect(
          parseCandidate(txt: _validTxt(), addresses: [ip], port: 8765),
          isNull,
          reason: '$ip is not private',
        );
      }
    });

    test('rejects Tailscale 100.64/10 range', () {
      expect(
        parseCandidate(
          txt: _validTxt(),
          addresses: const ['100.100.1.1'],
          port: 8765,
        ),
        isNull,
      );
    });

    test('rejects malformed IPv4 such as leading zeros or octet above 255', () {
      for (final ip in ['192.168.01.1', '192.168.1.256', '192.168.1']) {
        expect(
          parseCandidate(txt: _validTxt(), addresses: [ip], port: 8765),
          isNull,
          reason: '$ip should be rejected',
        );
      }
    });

    test('rejects port 0 and port above 65535', () {
      expect(
        parseCandidate(
          txt: _validTxt(),
          addresses: const ['192.168.1.2'],
          port: 0,
        ),
        isNull,
      );
      expect(
        parseCandidate(
          txt: _validTxt(),
          addresses: const ['192.168.1.2'],
          port: 70000,
        ),
        isNull,
      );
    });

    test('accepts port 1 and 65535', () {
      expect(
        parseCandidate(
          txt: _validTxt(),
          addresses: const ['192.168.1.2'],
          port: 1,
        ),
        isNotNull,
      );
      expect(
        parseCandidate(
          txt: _validTxt(),
          addresses: const ['192.168.1.2'],
          port: 65535,
        ),
        isNotNull,
      );
    });

    test('keeps the candidate without name when name is absent or blank', () {
      final result = parseCandidate(
        txt: _validTxt(name: '   '),
        addresses: const ['192.168.1.2'],
        port: 8765,
      );
      expect(result, isNotNull);
      expect(result!.name, isNull);
    });

    test('truncates name to 32 characters', () {
      final result = parseCandidate(
        txt: _validTxt(name: 'x' * 50),
        addresses: const ['192.168.1.2'],
        port: 8765,
      );
      expect(result!.name, 'x' * 32);
    });
  });

  group('decodeTxt', () {
    Uint8List bytes(String value) => Uint8List.fromList(utf8.encode(value));

    // 0xff can never appear in valid UTF-8.
    final malformed = Uint8List.fromList([0xff, 0xfe, 0xfd]);

    test('gives an empty map for raw null', () {
      expect(decodeTxt(null), isEmpty);
    });

    test('skips a key whose value is null', () {
      expect(decodeTxt({'v': null}), isEmpty);
      expect(decodeTxt({'v': bytes('1'), 'name': null}), {'v': '1'});
    });

    test('decodes valid UTF-8, including non-ASCII text', () {
      expect(decodeTxt({'name': bytes('Laptop Rizky ünï')}), {
        'name': 'Laptop Rizky ünï',
      });
    });

    test('drops a key with malformed UTF-8', () {
      expect(decodeTxt({'name': malformed}), isEmpty);
    });

    test('keeps the other keys when one key is malformed', () {
      expect(decodeTxt({'name': malformed, 'v': bytes('1')}), {'v': '1'});
    });

    test('parseCandidate rejects when a malformed id drops the key', () {
      final txt = decodeTxt({'v': bytes('1'), 'id': malformed});
      expect(
        parseCandidate(txt: txt, addresses: const ['192.168.1.2'], port: 8765),
        isNull,
      );
    });

    test('parseCandidate rejects when a malformed v drops the key', () {
      final txt = decodeTxt({'v': malformed, 'id': bytes(_agentId)});
      expect(
        parseCandidate(txt: txt, addresses: const ['192.168.1.2'], port: 8765),
        isNull,
      );
    });
  });

  group('selectCandidates', () {
    const current = (host: '192.168.1.10', port: 8765);

    DiscoveredAgent agent({
      String id = _agentId,
      String host = '192.168.1.20',
      int port = 8765,
    }) => DiscoveredAgent(agentId: id, host: host, port: port);

    test('keeps a candidate with matching agentId and a new endpoint', () {
      final selected = selectCandidates(
        [agent()],
        agentId: _agentId,
        currentHost: current.host,
        currentPort: current.port,
      );
      expect(selected.map((a) => a.host), ['192.168.1.20']);
    });

    test('drops candidates whose agentId differs from the stored one', () {
      final selected = selectCandidates(
        [agent(id: _otherAgentId)],
        agentId: _agentId,
        currentHost: current.host,
        currentPort: current.port,
      );
      expect(selected, isEmpty);
    });

    test('drops a candidate equal to the current endpoint', () {
      final selected = selectCandidates(
        [agent(host: current.host, port: current.port)],
        agentId: _agentId,
        currentHost: current.host,
        currentPort: current.port,
      );
      expect(selected, isEmpty);
    });

    test('keeps same host with a different port', () {
      final selected = selectCandidates(
        [agent(host: current.host, port: 9000)],
        agentId: _agentId,
        currentHost: current.host,
        currentPort: current.port,
      );
      expect(selected.single.port, 9000);
    });

    test('removes duplicate endpoints and keeps order', () {
      final selected = selectCandidates(
        [
          agent(host: '192.168.1.20'),
          agent(host: '192.168.1.30'),
          agent(host: '192.168.1.20'),
        ],
        agentId: _agentId,
        currentHost: current.host,
        currentPort: current.port,
      );
      expect(selected.map((a) => a.host), ['192.168.1.20', '192.168.1.30']);
    });
  });

  group('isLocalNetwork', () {
    test('true for Wi-Fi or Ethernet', () {
      expect(isLocalNetwork([ConnectivityResult.wifi]), isTrue);
      expect(isLocalNetwork([ConnectivityResult.ethernet]), isTrue);
      expect(
        isLocalNetwork([ConnectivityResult.mobile, ConnectivityResult.wifi]),
        isTrue,
      );
    });

    test('false for mobile-only or none', () {
      expect(isLocalNetwork([ConnectivityResult.mobile]), isFalse);
      expect(isLocalNetwork([ConnectivityResult.none]), isFalse);
      expect(isLocalNetwork(const []), isFalse);
    });
  });
}
