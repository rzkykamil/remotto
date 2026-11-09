// Generates lib/core/theme/tokens.g.dart from design/tokens.json.
//
// Run from app/: dart run tool/generate_tokens.dart
// Uses only dart:io and dart:convert. Output is deterministic (idempotent).
import 'dart:convert';
import 'dart:io';

Future<void> main() async {
  try {
    await _generate();
  } on _GenerateError catch (error) {
    stderr.writeln('generate_tokens: ${error.message}');
    exitCode = 1;
  } on FileSystemException catch (error) {
    stderr.writeln('generate_tokens: ${error.message} ${error.path ?? ''}');
    exitCode = 1;
  }
}

Future<void> _generate() async {
  final toolDir = File.fromUri(Platform.script).parent.uri;
  final source = File.fromUri(toolDir.resolve('../../design/tokens.json'));
  final output = File.fromUri(
    toolDir.resolve('../lib/core/theme/tokens.g.dart'),
  );

  final root = jsonDecode(await source.readAsString()) as Map<String, Object?>;
  await output.writeAsString(_Generator(_Tokens(root)).generate());

  final result = await Process.run(Platform.resolvedExecutable, [
    'format',
    output.path,
  ]);
  if (result.exitCode != 0) {
    throw _GenerateError('dart format failed: ${result.stderr}');
  }
  stdout.writeln('Wrote ${output.path}');
}

final class _GenerateError implements Exception {
  _GenerateError(this.message);

  final String message;
}

final RegExp _aliasPattern = RegExp(r'^\{([^{}]+)\}$');
final RegExp _quantityPattern = RegExp(r'^(-?\d+(?:\.\d+)?)(dp|sp|em|ms)$');
final RegExp _hexPattern = RegExp(r'^#([0-9A-Fa-f]{6})$');

/// Read-only view over tokens.json with alias resolution.
final class _Tokens {
  _Tokens(this._root);

  final Map<String, Object?> _root;

  /// Object at [path], e.g. `primitive.spacing`.
  Map<String, Object?> map(String path) {
    final node = _walk(path);
    if (node is! Map<String, Object?>) {
      throw _GenerateError('not an object: $path');
    }
    return node;
  }

  /// Token leaf at [path]: an object that carries a `value` key.
  Map<String, Object?> leaf(String path) {
    final node = _walk(path);
    if (node is! Map<String, Object?> || !node.containsKey('value')) {
      throw _GenerateError('not a token leaf: $path');
    }
    return node;
  }

  /// Value of the token at [path] with `{alias}` references followed.
  Object? value(String path) => resolve(leaf(path)['value'], {path});

  /// Follows `{path}` alias strings recursively. Fails on cycles.
  Object? resolve(Object? raw, [Set<String> chain = const <String>{}]) {
    if (raw is! String) {
      return raw;
    }
    final match = _aliasPattern.firstMatch(raw);
    if (match == null) {
      return raw;
    }
    final target = match.group(1)!;
    if (chain.contains(target)) {
      throw _GenerateError('alias cycle: ${[...chain, target].join(' -> ')}');
    }
    return resolve(leaf(target)['value'], {...chain, target});
  }

  Object? _walk(String path) {
    Object? node = _root;
    for (final part in path.split('.')) {
      if (node is! Map<String, Object?> || !node.containsKey(part)) {
        throw _GenerateError('path not found: $path');
      }
      node = node[part];
    }
    return node;
  }
}

/// A named field of a generated color set class.
final class _Field {
  _Field(this.dart, this.json);

  factory _Field.same(String name) => _Field(name, name);

  /// Dart identifier, e.g. `defaultColor`.
  final String dart;

  /// Key in tokens.json, e.g. `default`.
  final String json;
}

/// A color group (`semantic.<mode>.color.<name>`) and its generated class.
final class _Group {
  _Group(this.name, this.cls, this.fields);

  final String name;
  final String cls;
  final List<_Field> fields;
}

/// One `static const` line inside an abstract final holder class.
final class _Const {
  _Const(this.type, this.name, this.expr);

  final String type;
  final String name;
  final String expr;
}

final List<_Group> _groups = [
  _Group('bg', 'BgSet', [
    _Field.same('base'),
    _Field.same('glowA'),
    _Field.same('glowB'),
  ]),
  _Group('fg', 'FgSet', [
    _Field.same('primary'),
    _Field.same('secondary'),
    _Field.same('disabled'),
  ]),
  _Group('accent', 'AccentSet', [
    _Field('defaultColor', 'default'),
    _Field.same('highlight'),
    _Field.same('on'),
    _Field.same('text'),
    _Field.same('shadow'),
  ]),
  _Group('status', 'StatusSet', [
    _Field.same('success'),
    _Field.same('warning'),
    _Field.same('danger'),
    _Field.same('dangerText'),
    _Field.same('dangerSoft'),
    _Field.same('onDanger'),
  ]),
  _Group('glass', 'GlassSet', [
    _Field.same('fill'),
    _Field.same('edge'),
    _Field.same('highlight'),
    _Field.same('lowlight'),
    _Field.same('shadow'),
    _Field.same('chip'),
    _Field.same('chipPressed'),
    _Field.same('chipDisabled'),
    _Field.same('solid'),
    _Field.same('sheet'),
    _Field.same('toast'),
    _Field.same('scrim'),
  ]),
  _Group('slider', 'SliderSet', [_Field.same('fill'), _Field.same('track')]),
  _Group('control', 'ControlSet', [
    _Field.same('segTrack'),
    _Field.same('segOn'),
    _Field.same('switchOff'),
    _Field.same('switchThumb'),
    _Field.same('countdownInner'),
  ]),
];

/// Component scalars exposed as `RComponent` constants: (Dart name, path).
final List<(String, String)> _componentEntries = [
  ('glassPanelSaturation', 'component.glassPanel.saturation'),
  ('glassPanelEdgeWidth', 'component.glassPanel.edgeWidth'),
  ('keyPressedScale', 'component.key.pressedScale'),
  ('playKeyRingWidth', 'component.playKey.ringWidth'),
  ('volumeSliderStep', 'component.volumeSlider.step'),
  ('volumeSliderButtonStep', 'component.volumeSlider.buttonStep'),
  ('volumeSliderHapticDetent', 'component.volumeSlider.hapticDetent'),
  ('countdownSeconds', 'component.countdown.seconds'),
  ('countdownRingStroke', 'component.countdown.ringStroke'),
  ('toastDurationError', 'component.toast.durationError'),
  ('toastDurationInfo', 'component.toast.durationInfo'),
  ('offlineAfterFailures', 'component.connection.offlineAfterFailures'),
];

final class _Generator {
  _Generator(this._t);

  final _Tokens _t;

  static const String _header = '''
// GENERATED by tool/generate_tokens.dart from design/tokens.json. Do not edit.

import 'package:flutter/animation.dart';
import 'package:flutter/painting.dart';
''';

  static const String _typeSpec = '''
final class TypeSpec {
  const TypeSpec({
    required this.family,
    required this.size,
    required this.weight,
    required this.height,
    required this.letterSpacing,
  });

  final String family;
  final double size;
  final FontWeight weight;
  final double height;
  final double letterSpacing;
}
''';

  String generate() {
    final blocks = <String>[
      _header,
      ..._colorSets(),
      _tokenSet(),
      _tokenSetConst('kLightTokens', 'light'),
      _tokenSetConst('kDarkTokens', 'dark'),
      _staticClass('RSpace', [
        for (final key in _t.map('primitive.spacing').keys)
          _Const('double', 's$key', _dp('primitive.spacing.$key')),
      ]),
      _staticClass(
        'RRadius',
        _allKeys('primitive.radius', (key) {
          return _Const('double', key, _dp('primitive.radius.$key'));
        }),
      ),
      _staticClass(
        'RSize',
        _allKeys('primitive.size', (key) {
          return _Const('double', key, _dp('primitive.size.$key'));
        }),
      ),
      _staticClass(
        'RBlur',
        _allKeys('primitive.blur', (key) {
          return _Const('double', key, _dp('primitive.blur.$key'));
        }),
      ),
      _staticClass('RMotion', [
        ..._allKeys('primitive.duration', (key) {
          return _Const(
            'Duration',
            key,
            _durationExpr('primitive.duration.$key'),
          );
        }),
        ..._allKeys('primitive.easing', (key) {
          return _Const('Cubic', key, _cubicExpr('primitive.easing.$key'));
        }),
      ]),
      _staticClass('RComponent', [
        for (final (name, path) in _componentEntries)
          _componentConst(name, path),
      ]),
      _typeSpec,
      _staticClass('RFont', [
        for (final key in _t.map('primitive.fontFamily').keys)
          _Const('String', key, "'${_t.value('primitive.fontFamily.$key')}'"),
      ]),
      _staticClass('RType', [
        for (final key in _t.map('primitive.typography').keys)
          _Const('TypeSpec', key, _typeSpecExpr(key)),
      ]),
    ];
    return '${blocks.join('\n\n')}\n';
  }

  List<_Const> _allKeys(String path, _Const Function(String key) build) {
    return [for (final key in _t.map(path).keys) build(key)];
  }

  List<String> _colorSets() => [for (final group in _groups) _colorSet(group)];

  String _colorSet(_Group group) {
    final params = group.fields
        .map((f) => 'required this.${f.dart}')
        .join(', ');
    final buf = StringBuffer()
      ..writeln('final class ${group.cls} {')
      ..writeln('  const ${group.cls}({$params});')
      ..writeln();
    for (final field in group.fields) {
      buf.writeln('  final Color ${field.dart};');
    }
    buf.write('}');
    return buf.toString();
  }

  String _tokenSet() {
    final buf = StringBuffer()
      ..writeln('final class TokenSet {')
      ..writeln(
        '  const TokenSet({'
        '${_groups.map((g) => 'required this.${g.name}').join(', ')}'
        '});',
      )
      ..writeln();
    for (final group in _groups) {
      buf.writeln('  final ${group.cls} ${group.name};');
    }
    buf.write('}');
    return buf.toString();
  }

  String _tokenSetConst(String name, String mode) {
    final buf = StringBuffer('const TokenSet $name = TokenSet(\n');
    for (final group in _groups) {
      buf.writeln('  ${group.name}: ${group.cls}(');
      for (final field in group.fields) {
        final color = _color(
          'semantic.$mode.color.${group.name}.${field.json}',
        );
        buf.writeln('    ${field.dart}: $color,');
      }
      buf.writeln('  ),');
    }
    buf.write(');');
    return buf.toString();
  }

  /// `#RRGGBB` plus optional `alpha` (0-1) to `Color(0xAARRGGBB)`.
  String _color(String path) {
    final node = _t.leaf(path);
    final hex = _t.value(path);
    if (hex is! String || !_hexPattern.hasMatch(hex)) {
      throw _GenerateError('not a #RRGGBB color: $path = $hex');
    }
    final alpha = (node['alpha'] as num?) ?? 1;
    final byte = (alpha * 255).round().toRadixString(16).padLeft(2, '0');
    return 'Color(0x${byte.toUpperCase()}${hex.substring(1).toUpperCase()})';
  }

  String _dp(String path) => _double(_quantity(_t.value(path), 'dp', path));

  String _durationExpr(String path) {
    final ms = _quantity(_t.value(path), 'ms', path).round();
    return 'Duration(milliseconds: $ms)';
  }

  String _cubicExpr(String path) {
    final raw = _t.value(path);
    if (raw is! List<Object?> || raw.length != 4) {
      throw _GenerateError('$path: expected cubic-bezier with 4 numbers');
    }
    final args = raw.map((n) => _double((n as num).toDouble())).join(', ');
    return 'Cubic($args)';
  }

  _Const _componentConst(String name, String path) {
    final node = _t.leaf(path);
    final raw = _t.value(path);
    switch (node['type']) {
      case 'number':
        if (raw is int) {
          return _Const('int', name, '$raw');
        }
        return _Const('double', name, _double((raw as num).toDouble()));
      case 'dimension':
        return _Const('double', name, _dp(path));
      case 'duration':
        return _Const('Duration', name, _durationExpr(path));
    }
    throw _GenerateError('$path: unsupported component type ${node['type']}');
  }

  String _typeSpecExpr(String key) {
    final typography =
        _t.leaf('primitive.typography.$key')['value'] as Map<String, Object?>;
    final path = 'primitive.typography.$key';

    final familyName = _t.resolve(typography['fontFamily']) as String;
    final familyKey = _t
        .map('primitive.fontFamily')
        .keys
        .firstWhere(
          (k) => _t.value('primitive.fontFamily.$k') == familyName,
          orElse: () => throw _GenerateError('$path: unknown fontFamily'),
        );

    final weight = _t.resolve(typography['fontWeight']) as int;
    final size = _quantity(typography['fontSize'], 'sp', path);
    final lineHeight = _quantity(typography['lineHeight'], 'sp', path);
    final em = _quantity(typography['letterSpacing'], 'em', path);

    final height = _double(lineHeight / size);
    final letterSpacing = _double(em * size);
    return 'TypeSpec(family: RFont.$familyKey, size: ${_double(size)}, '
        'weight: FontWeight.w$weight, height: $height, '
        'letterSpacing: $letterSpacing)';
  }

  /// Parses `NNdp`, `NNsp`, `NNem`, or `NNms` into its numeric part.
  double _quantity(Object? raw, String unit, String path) {
    final match = raw is String ? _quantityPattern.firstMatch(raw) : null;
    if (match == null || match.group(2) != unit) {
      throw _GenerateError('$path: expected a $unit value, got $raw');
    }
    return double.parse(match.group(1)!);
  }

  String _staticClass(String name, List<_Const> consts) {
    final buf = StringBuffer('abstract final class $name {\n');
    for (final c in consts) {
      buf.writeln('  static const ${c.type} ${c.name} = ${c.expr};');
    }
    buf.write('}');
    return buf.toString();
  }

  /// Dart double literal; `toString` round-trips to the same value.
  String _double(double value) => value.toString();
}
