import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Penjaga regresi: kode discovery tidak boleh mencetak log dan
/// `nsd_agent_discovery.dart` tidak boleh menyentuh token.
///
/// Tes membaca sumber, bukan perilaku. Baris komentar (`//`, termasuk `///`)
/// dikecualikan supaya dokumentasi boleh menyebut kata terlarang.
void main() {
  final discoveryDir = Directory('lib/core/discovery');

  List<File> discoverySources() => discoveryDir
      .listSync()
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .toList();

  bool isCommentLine(String line) => line.trimLeft().startsWith('//');

  test('folder discovery terbaca dan berisi sumber Dart', () {
    expect(discoveryDir.existsSync(), isTrue);
    expect(discoverySources(), isNotEmpty);
  });

  test('kode discovery tidak memakai print, log, atau stderr', () {
    final forbidden = <String, RegExp>{
      'print(': RegExp(r'\bprint\('),
      'debugPrint(': RegExp(r'\bdebugPrint\('),
      'dart:developer': RegExp(r'dart:developer'),
      'Logger': RegExp(r'\bLogger\b'),
      'log(': RegExp(r'\blog\('),
      'stderr.write': RegExp(r'stderr\.write'),
    };

    final violations = <String>[];
    for (final file in discoverySources()) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (isCommentLine(line)) continue;
        for (final entry in forbidden.entries) {
          if (entry.value.hasMatch(line)) {
            violations.add('${file.path}:${i + 1} memakai ${entry.key}');
          }
        }
      }
    }

    expect(violations, isEmpty);
  });

  test('nsd_agent_discovery.dart tidak menyentuh token', () {
    final file = File('lib/core/discovery/nsd_agent_discovery.dart');
    expect(file.existsSync(), isTrue);

    final lines = file.readAsLinesSync();
    final hits = <String>[];
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (isCommentLine(line)) continue;
      if (RegExp('token', caseSensitive: false).hasMatch(line)) {
        hits.add('${file.path}:${i + 1}');
      }
    }

    expect(hits, isEmpty);
  });
}
