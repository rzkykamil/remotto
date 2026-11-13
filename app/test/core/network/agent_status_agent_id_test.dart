import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:remotto/core/network/agent_status.dart';
import 'package:remotto/core/network/api_failure.dart';

const _agentId = 'a3f1c9e0b72d4e85916f0c2d7b4e13a8';

Map<String, Object?> _data([Map<String, Object?> extra = const {}]) => {
  'name': 'Laptop-Kamil',
  'version': '1.0.0',
  'uptimeSeconds': 10,
  'volume': null,
  'pending': null,
  ...extra,
};

String _body(Map<String, Object?> extra) => jsonEncode({'data': _data(extra)});

void main() {
  group('AgentStatus agentId (api-spec GET /status)', () {
    test('agentId 32 hex dibaca', () {
      final status = parseStatusResponse(200, _body({'agentId': _agentId}));
      expect(status.agentId, _agentId);
    });

    test('tanpa agentId (agent sebelum M7) menghasilkan null', () {
      final status = parseStatusResponse(200, _body({}));
      expect(status.agentId, isNull);
      expect(status.name, 'Laptop-Kamil');
    });

    test('agentId null dibaca sebagai null', () {
      final status = parseStatusResponse(200, _body({'agentId': null}));
      expect(status.agentId, isNull);
    });

    test('agentId bukan string -> ServerFailure', () {
      expect(
        () => parseStatusResponse(200, _body({'agentId': 123})),
        throwsA(isA<ServerFailure>()),
      );
    });

    test('agentId bentuk salah -> ServerFailure', () {
      const badValues = [
        'ABCDEF0123456789ABCDEF0123456789', // huruf besar
        'a3f1c9e0b72d4e85916f0c2d7b4e13a', // 31 karakter
        'a3f1c9e0b72d4e85916f0c2d7b4e13a88', // 33 karakter
        'g3f1c9e0b72d4e85916f0c2d7b4e13a8', // bukan hex
        '',
      ];
      for (final bad in badValues) {
        expect(
          () => parseStatusResponse(200, _body({'agentId': bad})),
          throwsA(isA<ServerFailure>()),
          reason: bad,
        );
      }
    });

    test('equality dan toString memuat agentId', () {
      final withId = AgentStatus.fromData(_data({'agentId': _agentId}));
      final withoutId = AgentStatus.fromData(_data());
      expect(withId == withoutId, isFalse);
      expect(withId.toString(), contains(_agentId));
    });
  });
}
