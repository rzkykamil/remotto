import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:remotto/core/network/agent_status.dart';
import 'package:remotto/core/network/api_failure.dart';
import 'package:remotto/features/remote/data/power_repository.dart';

// Bodies below are the exact shapes that encoding/json produces for
// agent/internal/server/power.go (pendingData, powerScheduledData,
// powerCancelData) and status.go (statusData).

const _pendingJson =
    '{"action":"shutdown","remainingMs":5000,"delayMs":5000,'
    '"scheduledAt":"2026-01-01T23:41:00+07:00"}';

String _scheduled202(String pending) => '{"data":{"pending":$pending}}';

String _status(String pending) =>
    '{"data":{"name":"Laptop-Kamil","version":"1.0.0","uptimeSeconds":11520,'
    '"volume":{"level":35,"muted":false},"pending":$pending}}';

String _errorBody(String code) => '{"error":{"code":"$code","message":"msg"}}';

void main() {
  group('POST /power/{action} 202 contract', () {
    test('pending object maps to Pending with all four fields', () {
      final data = unwrapAgentResponse(202, _scheduled202(_pendingJson));
      final pending = parseScheduledPending(data);

      expect(pending.action, 'shutdown');
      expect(pending.remainingMs, 5000);
      expect(pending.delayMs, 5000);
      expect(pending.scheduledAt, '2026-01-01T23:41:00+07:00');
    });

    test('remainingMs 0 is accepted (being executed)', () {
      const json =
          '{"action":"sleep","remainingMs":0,"delayMs":5000,'
          '"scheduledAt":"2026-01-01T23:41:00+07:00"}';
      final pending = parseScheduledPending(
        unwrapAgentResponse(202, _scheduled202(json)),
      );

      expect(pending.remainingMs, 0);
      expect(pending.action, 'sleep');
    });

    test('pending missing from data is ServerFailure', () {
      expect(
        () => parseScheduledPending(unwrapAgentResponse(202, '{"data":{}}')),
        throwsA(isA<ServerFailure>()),
      );
    });

    test('pending null is ServerFailure', () {
      expect(
        () => parseScheduledPending(
          unwrapAgentResponse(202, _scheduled202('null')),
        ),
        throwsA(isA<ServerFailure>()),
      );
    });

    test('negative remainingMs is ServerFailure', () {
      const json =
          '{"action":"sleep","remainingMs":-1,"delayMs":5000,'
          '"scheduledAt":"2026-01-01T23:41:00+07:00"}';
      expect(
        () => parseScheduledPending(
          unwrapAgentResponse(202, _scheduled202(json)),
        ),
        throwsA(isA<ServerFailure>()),
      );
    });

    test('negative delayMs is ServerFailure', () {
      const json =
          '{"action":"sleep","remainingMs":5000,"delayMs":-5000,'
          '"scheduledAt":"2026-01-01T23:41:00+07:00"}';
      expect(
        () => parseScheduledPending(
          unwrapAgentResponse(202, _scheduled202(json)),
        ),
        throwsA(isA<ServerFailure>()),
      );
    });

    test('remainingMs as string is ServerFailure', () {
      const json =
          '{"action":"sleep","remainingMs":"5000","delayMs":5000,'
          '"scheduledAt":"2026-01-01T23:41:00+07:00"}';
      expect(
        () => parseScheduledPending(
          unwrapAgentResponse(202, _scheduled202(json)),
        ),
        throwsA(isA<ServerFailure>()),
      );
    });

    test('delayMs as float is ServerFailure', () {
      const json =
          '{"action":"sleep","remainingMs":5000,"delayMs":5000.5,'
          '"scheduledAt":"2026-01-01T23:41:00+07:00"}';
      expect(
        () => parseScheduledPending(
          unwrapAgentResponse(202, _scheduled202(json)),
        ),
        throwsA(isA<ServerFailure>()),
      );
    });

    test('scheduledAt missing is ServerFailure', () {
      const json = '{"action":"sleep","remainingMs":5000,"delayMs":5000}';
      expect(
        () => parseScheduledPending(
          unwrapAgentResponse(202, _scheduled202(json)),
        ),
        throwsA(isA<ServerFailure>()),
      );
    });

    // The agent only emits sleep, restart, or shutdown
    // (agent/internal/control/control.go); Pending.fromData rejects the rest.
    test('unknown action in pending is ServerFailure', () {
      const json =
          '{"action":"reboot","remainingMs":5000,"delayMs":5000,'
          '"scheduledAt":"2026-01-01T23:41:00+07:00"}';
      expect(
        () => parseScheduledPending(
          unwrapAgentResponse(202, _scheduled202(json)),
        ),
        throwsA(isA<ServerFailure>()),
      );
    });
  });

  group('POST /power/cancel 200 contract', () {
    test('cancelled sleep maps to PowerAction.sleep', () {
      final action = parseCancelledAction(
        unwrapAgentResponse(
          200,
          '{"data":{"cancelled":"sleep","pending":null}}',
        ),
      );

      expect(action, PowerAction.sleep);
    });

    test('cancelled restart and shutdown map to their actions', () {
      expect(
        parseCancelledAction(
          unwrapAgentResponse(
            200,
            '{"data":{"cancelled":"restart","pending":null}}',
          ),
        ),
        PowerAction.restart,
      );
      expect(
        parseCancelledAction(
          unwrapAgentResponse(
            200,
            '{"data":{"cancelled":"shutdown","pending":null}}',
          ),
        ),
        PowerAction.shutdown,
      );
    });

    test('unknown cancelled action is ServerFailure', () {
      expect(
        () => parseCancelledAction(
          unwrapAgentResponse(
            200,
            '{"data":{"cancelled":"hibernate","pending":null}}',
          ),
        ),
        throwsA(isA<ServerFailure>()),
      );
    });

    test('cancelled missing is ServerFailure', () {
      expect(
        () => parseCancelledAction(
          unwrapAgentResponse(200, '{"data":{"pending":null}}'),
        ),
        throwsA(isA<ServerFailure>()),
      );
    });

    test('cancelled as non-string is ServerFailure', () {
      expect(
        () => parseCancelledAction(
          unwrapAgentResponse(200, '{"data":{"cancelled":1,"pending":null}}'),
        ),
        throwsA(isA<ServerFailure>()),
      );
    });
  });

  group('GET /status pending contract', () {
    test('pending object is parsed into Pending', () {
      final status = parseStatusResponse(200, _status(_pendingJson));

      expect(status.pending, isNotNull);
      expect(status.pending!.action, 'shutdown');
      expect(status.pending!.remainingMs, 5000);
      expect(status.pending!.delayMs, 5000);
      expect(status.pending!.scheduledAt, '2026-01-01T23:41:00+07:00');
    });

    test('pending null is parsed as no schedule', () {
      final status = parseStatusResponse(200, _status('null'));

      expect(status.pending, isNull);
      expect(status.volume, const VolumeStatus(level: 35, muted: false));
    });

    test('remainingMs 0 in status is accepted', () {
      const json =
          '{"action":"restart","remainingMs":0,"delayMs":5000,'
          '"scheduledAt":"2026-01-01T23:41:00+07:00"}';
      final status = parseStatusResponse(200, _status(json));

      expect(status.pending!.remainingMs, 0);
    });

    test('negative remainingMs in status is ServerFailure', () {
      const json =
          '{"action":"restart","remainingMs":-3,"delayMs":5000,'
          '"scheduledAt":"2026-01-01T23:41:00+07:00"}';
      expect(
        () => parseStatusResponse(200, _status(json)),
        throwsA(isA<ServerFailure>()),
      );
    });

    test('pending key missing from status is ServerFailure', () {
      final body = jsonEncode({
        'data': {
          'name': 'Laptop-Kamil',
          'version': '1.0.0',
          'uptimeSeconds': 11520,
          'volume': {'level': 35, 'muted': false},
        },
      });
      expect(
        () => parseStatusResponse(200, body),
        throwsA(isA<ServerFailure>()),
      );
    });
  });

  group('error envelope for power routes', () {
    final cases = <({int status, String code})>[
      (status: 409, code: 'power_pending'),
      (status: 409, code: 'no_pending_power'),
      (status: 409, code: 'power_executing'),
      (status: 500, code: 'power_failed'),
    ];

    for (final c in cases) {
      test('${c.status} ${c.code} is ServerFailure with the same code', () {
        expect(
          () => unwrapAgentResponse(c.status, _errorBody(c.code)),
          throwsA(isA<ServerFailure>().having((f) => f.code, 'code', c.code)),
        );
      });
    }
  });
}
