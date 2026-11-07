// Guard tests for the frontend UI rules (see docs/design-system.md section 9). They scan source files, so they run in CI
// without a device. Paths are relative to app/, the package root.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _libDir = 'lib';
const _pubspecPath = 'pubspec.yaml';
const _tokensPath = 'lib/core/theme/tokens.g.dart';
const _featuresDir = 'lib/features';
const _hapticsPath = 'lib/core/haptics/r_haptics.dart';

// Material defaults and UI kit entry points that the design forbids.
final _forbiddenWidgets = RegExp(
  r'\bInkWell\b|\bInkResponse\b|\bIcons\.|\bAppBar\(|\bSnackBar\b|'
  r'\bAlertDialog\b|\bSegmentedButton\b|\bSwitch\(|\bSlider\(|'
  r'\bFloatingActionButton\b',
);

final _colorLiteral = RegExp(r'Color\(0x');
final _hapticCall = RegExp(r'\bHapticFeedback\b');
final _edgeInsetsCall = RegExp(
  r'EdgeInsets\.(?:all|symmetric|only|fromLTRB)\(([^)]*)\)',
);
final _numberLiteral = RegExp(r'(?<![\w.])\d+(?:\.\d+)?');

// UI kit and icon-pack packages that must not appear in pubspec.yaml (§11).
const _forbiddenPackages = [
  'flutter_svg',
  'google_fonts',
  'getwidget',
  'flutter_neumorphic',
  'glassmorphism',
  'liquid_glass',
  'font_awesome_flutter',
  'cupertino_icons',
  'lucide_icons',
  'iconsax',
  'material_design_icons_flutter',
  'ionicons',
];

List<File> _dartFiles(String dir) {
  return Directory(dir)
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();
}

String _rel(File f) => f.path.replaceAll('\\', '/');

/// Returns "path:line: text" for every line in [files] matching [pattern].
List<String> _matchLines(Iterable<File> files, RegExp pattern) {
  final hits = <String>[];
  for (final file in files) {
    final lines = file.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      if (pattern.hasMatch(lines[i])) {
        hits.add('${_rel(file)}:${i + 1}: ${lines[i].trim()}');
      }
    }
  }
  return hits;
}

void main() {
  final libFiles = _dartFiles(_libDir);

  group('Material defaults and UI kit (frontend-ui.md anti-pattern)', () {
    test('no InkWell, AppBar, Icons.*, Slider, Switch and other defaults', () {
      final hits = _matchLines(libFiles, _forbiddenWidgets);
      expect(
        hits,
        isEmpty,
        reason:
            'Forbidden Material default or UI kit widget in lib/:\n'
            '${hits.join('\n')}',
      );
    });
  });

  group('Tokens only', () {
    test('Color(0x...) appears only in generated tokens.g.dart', () {
      final others = libFiles.where((f) => !_rel(f).endsWith(_tokensPath));
      final hits = _matchLines(others, _colorLiteral);
      expect(
        hits,
        isEmpty,
        reason:
            'Color(0x...) literal outside $_tokensPath:\n'
            '${hits.join('\n')}',
      );
    });

    test('no numeric EdgeInsets literal in lib/features (0 is allowed)', () {
      final featureFiles = _dartFiles(_featuresDir);
      final violations = <String>[];
      for (final file in featureFiles) {
        final source = file.readAsStringSync();
        for (final call in _edgeInsetsCall.allMatches(source)) {
          final args = call.group(1)!;
          for (final number in _numberLiteral.allMatches(args)) {
            if (double.parse(number.group(0)!) != 0) {
              final line =
                  '\n'.allMatches(source.substring(0, call.start)).length + 1;
              violations.add('${_rel(file)}:$line: ${call.group(0)}');
              break;
            }
          }
        }
      }
      expect(
        violations,
        isEmpty,
        reason:
            'Literal padding in lib/features/ (use RSpace):\n'
            '${violations.join('\n')}',
      );
    });
  });

  group('Haptic', () {
    test('HapticFeedback is called only from r_haptics.dart', () {
      final others = libFiles.where((f) => !_rel(f).endsWith(_hapticsPath));
      final hits = _matchLines(others, _hapticCall);
      expect(
        hits,
        isEmpty,
        reason:
            'HapticFeedback used outside $_hapticsPath:\n'
            '${hits.join('\n')}',
      );
    });
  });

  group('Dependencies', () {
    test('pubspec.yaml does not list UI kit or icon-pack packages', () {
      final pubspec = File(_pubspecPath).readAsStringSync();
      final violations = <String>[];
      for (final name in _forbiddenPackages) {
        final entry = RegExp(
          '^\\s+${RegExp.escape(name)}\\s*:',
          multiLine: true,
        );
        if (entry.hasMatch(pubspec)) {
          violations.add(name);
        }
      }
      expect(
        violations,
        isEmpty,
        reason: 'Forbidden package(s) in pubspec.yaml: $violations',
      );
    });
  });

  group('Guard sanity', () {
    test('the scanned tree is not empty', () {
      expect(libFiles, isNotEmpty);
      expect(_dartFiles(_featuresDir), isNotEmpty);
    });
  });
}
