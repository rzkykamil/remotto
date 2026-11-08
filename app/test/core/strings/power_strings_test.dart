import 'package:flutter_test/flutter_test.dart';
import 'package:remotto/core/strings/power_strings.dart';

void main() {
  group('since (P13)', () {
    test('tanpa "dari HP ini"', () {
      expect(PowerStrings.since(2), 'Dijadwalkan 2 detik lalu');
    });

    test('dengan "dari HP ini"', () {
      expect(
        PowerStrings.since(2, fromThisPhone: true),
        'Dijadwalkan 2 detik lalu dari HP ini',
      );
    });
  });

  group('formatClock (P15, HH.mm)', () {
    final cases = <(String, DateTime)>[
      ('23.41', DateTime(2026, 11, 8, 23, 41)),
      ('00.05', DateTime(2026, 11, 8, 0, 5)),
      ('09.00', DateTime(2026, 11, 8, 9)),
    ];

    for (final (expected, input) in cases) {
      test('$input -> $expected', () {
        expect(PowerStrings.formatClock(input), expected);
      });
    }
  });

  group('P15 body', () {
    final at = DateTime(2026, 11, 8, 23, 41);

    test('matikan memakai jam HH.mm', () {
      expect(
        PowerStrings.poweredOffShutdownBody(at),
        'Dimatiin dari HP ini jam 23.41. Nyalain laptopnya, nanti nyambung sendiri.',
      );
    });

    test('sleep memakai jam HH.mm', () {
      expect(
        PowerStrings.poweredOffSleepBody(at),
        'Di-sleep-in dari HP ini jam 23.41. Buka lagi laptopnya, nanti nyambung sendiri.',
      );
    });
  });

  group('lateCancel body (P14)', () {
    test('dengan "dari HP ini"', () {
      expect(
        PowerStrings.lateShutdownBody('Laptop-Kamil', 6, fromThisPhone: true),
        'Laptop-Kamil lagi dimatiin. Perintahnya dikirim 6 detik lalu dari HP ini.',
      );
    });

    test('tanpa "dari HP ini"', () {
      expect(
        PowerStrings.lateShutdownBody('Laptop-Kamil', 6),
        'Laptop-Kamil lagi dimatiin. Perintahnya dikirim 6 detik lalu.',
      );
    });

    test('aksi restart dan sleep memakai frasa sendiri', () {
      expect(
        PowerStrings.lateRestartBody('Laptop-Kamil', 3),
        'Laptop-Kamil lagi restart. Perintahnya dikirim 3 detik lalu.',
      );
      expect(
        PowerStrings.lateSleepBody('Laptop-Kamil', 3, fromThisPhone: true),
        'Laptop-Kamil lagi tidur. Perintahnya dikirim 3 detik lalu dari HP ini.',
      );
    });
  });
}
