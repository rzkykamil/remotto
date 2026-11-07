import 'package:flutter_test/flutter_test.dart';
import 'package:remotto/core/strings/uptime_format.dart';

void main() {
  group('formatUptime (C06, minutes rounded down)', () {
    final cases = <(String, Duration)>[
      ('0M', Duration.zero),
      ('0M', const Duration(seconds: 59)),
      ('12M', const Duration(minutes: 12)),
      ('12M', const Duration(minutes: 12, seconds: 59)),
      ('59M', const Duration(minutes: 59, seconds: 59)),
      ('1J 0M', const Duration(hours: 1)),
      ('3J 12M', const Duration(seconds: 11520)),
      ('3J 12M', const Duration(hours: 3, minutes: 12, seconds: 59)),
      ('25J 0M', const Duration(hours: 25)),
      ('0M', const Duration(minutes: -5)),
    ];

    for (final (expected, input) in cases) {
      test('$input -> $expected', () {
        expect(formatUptime(input), expected);
      });
    }
  });
}
