import 'dart:convert';
import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotto/core/theme/tokens.g.dart';

/// Kunci leaf warna yang harus ada di `semantic.<mode>.color`, relatif ke
/// `semantic.<mode>.color`. Mengikuti daftar `_groups` di
/// `tool/generate_tokens.dart`.
const List<String> _expectedColorKeys = [
  'bg.base',
  'bg.glowA',
  'bg.glowB',
  'fg.primary',
  'fg.secondary',
  'fg.disabled',
  'accent.default',
  'accent.highlight',
  'accent.on',
  'accent.text',
  'accent.shadow',
  'status.success',
  'status.warning',
  'status.danger',
  'status.dangerText',
  'status.dangerSoft',
  'status.onDanger',
  'glass.fill',
  'glass.edge',
  'glass.highlight',
  'glass.lowlight',
  'glass.shadow',
  'glass.chip',
  'glass.chipPressed',
  'glass.chipDisabled',
  'glass.solid',
  'glass.sheet',
  'glass.toast',
  'glass.scrim',
  'slider.fill',
  'slider.track',
  'control.segTrack',
  'control.segOn',
  'control.switchOff',
  'control.switchThumb',
  'control.countdownInner',
];

final RegExp _aliasPattern = RegExp(r'^\{([^{}]+)\}$');
final RegExp _hexPattern = RegExp(r'^#([0-9A-Fa-f]{6})$');

Map<String, Object?> _loadTokens() {
  for (final candidate in ['../design/tokens.json', 'design/tokens.json']) {
    final file = File(candidate);
    if (file.existsSync()) {
      return jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
    }
  }
  fail('design/tokens.json tidak ditemukan dari ${Directory.current.path}');
}

final Map<String, Object?> _root = _loadTokens();

Object? _walk(String path) {
  Object? node = _root;
  for (final part in path.split('.')) {
    if (node is! Map<String, Object?> || !node.containsKey(part)) {
      fail('path tidak ditemukan: $path');
    }
    node = node[part];
  }
  return node;
}

Map<String, Object?> _leaf(String path) {
  final node = _walk(path);
  if (node is! Map<String, Object?> || !node.containsKey('value')) {
    fail('bukan token leaf: $path');
  }
  return node;
}

/// Mengikuti alias `{a.b.c}` secara rekursif; gagal bila ada siklus.
Object? _resolve(Object? raw, Set<String> chain) {
  if (raw is! String) {
    return raw;
  }
  final match = _aliasPattern.firstMatch(raw);
  if (match == null) {
    return raw;
  }
  final target = match.group(1)!;
  if (chain.contains(target)) {
    fail('siklus alias: ${[...chain, target].join(' -> ')}');
  }
  return _resolve(_leaf(target)['value'], {...chain, target});
}

/// Meniru aturan `_color` di generator: `#RRGGBB` + alpha leaf semantic
/// (default 1) menjadi `Color(0xAARRGGBB)` dengan alpha `(a * 255).round()`.
Color colorAt(String path) {
  final node = _leaf(path);
  final hex = _resolve(node['value'], {path});
  if (hex is! String || !_hexPattern.hasMatch(hex)) {
    fail('bukan warna #RRGGBB: $path = $hex');
  }
  final alpha = (node['alpha'] as num?) ?? 1;
  final byte = (alpha * 255).round();
  return Color((byte << 24) | int.parse(hex.substring(1), radix: 16));
}

/// Kumpulan path leaf (node yang punya `value`) di bawah [path].
Set<String> _leafPaths(String path) {
  final out = <String>{};
  void visit(Object? node, String prefix) {
    if (node is! Map<String, Object?>) {
      return;
    }
    if (node.containsKey('value')) {
      out.add(prefix);
      return;
    }
    for (final entry in node.entries) {
      visit(entry.value, prefix.isEmpty ? entry.key : '$prefix.${entry.key}');
    }
  }

  visit(_walk(path), '');
  return out;
}

void _expectMode(String mode, TokenSet t) {
  final checks = <(String, Color)>[
    ('bg.base', t.bg.base),
    ('bg.glowA', t.bg.glowA),
    ('bg.glowB', t.bg.glowB),
    ('fg.primary', t.fg.primary),
    ('fg.secondary', t.fg.secondary),
    ('fg.disabled', t.fg.disabled),
    ('accent.default', t.accent.defaultColor),
    ('accent.highlight', t.accent.highlight),
    ('accent.on', t.accent.on),
    ('accent.text', t.accent.text),
    ('accent.shadow', t.accent.shadow),
    ('status.success', t.status.success),
    ('status.warning', t.status.warning),
    ('status.danger', t.status.danger),
    ('status.dangerText', t.status.dangerText),
    ('status.dangerSoft', t.status.dangerSoft),
    ('status.onDanger', t.status.onDanger),
    ('glass.fill', t.glass.fill),
    ('glass.edge', t.glass.edge),
    ('glass.highlight', t.glass.highlight),
    ('glass.lowlight', t.glass.lowlight),
    ('glass.shadow', t.glass.shadow),
    ('glass.chip', t.glass.chip),
    ('glass.chipPressed', t.glass.chipPressed),
    ('glass.chipDisabled', t.glass.chipDisabled),
    ('glass.solid', t.glass.solid),
    ('glass.sheet', t.glass.sheet),
    ('glass.toast', t.glass.toast),
    ('glass.scrim', t.glass.scrim),
    ('slider.fill', t.slider.fill),
    ('slider.track', t.slider.track),
    ('control.segTrack', t.control.segTrack),
    ('control.segOn', t.control.segOn),
    ('control.switchOff', t.control.switchOff),
    ('control.switchThumb', t.control.switchThumb),
    ('control.countdownInner', t.control.countdownInner),
  ];

  expect(
    checks.map((c) => c.$1).toList(),
    _expectedColorKeys,
    reason: 'daftar field uji harus sama dengan daftar generator',
  );

  for (final (key, actual) in checks) {
    final path = 'semantic.$mode.color.$key';
    expect(actual, colorAt(path), reason: path);
  }
}

void main() {
  group('generated tokens match design/tokens.json', () {
    test('light mode: every color field equals the JSON value', () {
      _expectMode('light', kLightTokens);
    });

    test('dark mode: every color field equals the JSON value', () {
      _expectMode('dark', kDarkTokens);
    });
  });

  group('json keys map to generated fields', () {
    test('light color leaves are exactly the generated field list', () {
      expect(
        _leafPaths('semantic.light.color'),
        unorderedEquals(_expectedColorKeys),
        reason: 'semantic.light.color tidak sama dengan field generator',
      );
    });

    test('dark color leaves are exactly the generated field list', () {
      expect(
        _leafPaths('semantic.dark.color'),
        unorderedEquals(_expectedColorKeys),
        reason: 'semantic.dark.color tidak sama dengan field generator',
      );
    });

    test('light and dark have the same leaf structure', () {
      expect(
        _leafPaths('semantic.dark.color'),
        unorderedEquals(_leafPaths('semantic.light.color')),
      );
    });
  });
}
