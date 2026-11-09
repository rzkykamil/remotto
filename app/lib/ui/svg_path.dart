import 'dart:ui';

/// Parses an SVG path `d` string into a [Path] in the same coordinate space.
///
/// Supports the absolute and relative forms of `M L H V C S A Z`, implicit
/// repeats after a command, and compact number syntax such as `10-5.5.5`.
/// Arc flags accept both `0 1` and the compact `01` form. Quadratic curves
/// (`Q T`) are not used by the app's icons and are rejected.
///
/// Throws [FormatException] when the data is malformed.
Path parseSvgPath(String d) => _SvgPathParser(d).parse();

final class _SvgPathParser {
  _SvgPathParser(this._s);

  final String _s;
  int _i = 0;

  Path parse() {
    final path = Path();
    var cx = 0.0;
    var cy = 0.0;
    var sx = 0.0;
    var sy = 0.0;
    String? cmd;
    // Second control point of the previous C/S, used by S. Null after any
    // other command, so S falls back to the current point.
    double? lastCtrlX;
    double? lastCtrlY;

    _skipSeparators();
    if (_atEnd) return path;
    if (!_isOneOf(_s[_i], 'Mm')) {
      throw FormatException('SVG path must start with M or m', _s, _i);
    }

    while (true) {
      _skipSeparators();
      if (_atEnd) break;

      final c = _s[_i];
      if (_isLetter(c)) {
        cmd = c;
        _i++;
      } else if (cmd == null || _isOneOf(cmd, 'Zz')) {
        throw FormatException('Expected a command letter', _s, _i);
      }
      // Otherwise a number follows, which repeats the previous command.

      final rel = cmd.toLowerCase() == cmd;
      final prevCtrlX = lastCtrlX;
      final prevCtrlY = lastCtrlY;
      lastCtrlX = null;
      lastCtrlY = null;
      switch (cmd.toUpperCase()) {
        case 'M':
          var x = _number();
          var y = _number();
          if (rel) {
            x += cx;
            y += cy;
          }
          path.moveTo(x, y);
          cx = sx = x;
          cy = sy = y;
          // Further coordinate pairs after M are implicit lineto commands.
          cmd = rel ? 'l' : 'L';
        case 'L':
          var x = _number();
          var y = _number();
          if (rel) {
            x += cx;
            y += cy;
          }
          path.lineTo(x, y);
          cx = x;
          cy = y;
        case 'H':
          var x = _number();
          if (rel) x += cx;
          path.lineTo(x, cy);
          cx = x;
        case 'V':
          var y = _number();
          if (rel) y += cy;
          path.lineTo(cx, y);
          cy = y;
        case 'C':
          var x1 = _number();
          var y1 = _number();
          var x2 = _number();
          var y2 = _number();
          var x = _number();
          var y = _number();
          if (rel) {
            x1 += cx;
            y1 += cy;
            x2 += cx;
            y2 += cy;
            x += cx;
            y += cy;
          }
          path.cubicTo(x1, y1, x2, y2, x, y);
          lastCtrlX = x2;
          lastCtrlY = y2;
          cx = x;
          cy = y;
        case 'S':
          // Smooth cubic: the first control point reflects the previous C/S
          // second control point, or equals the current point otherwise.
          var x2 = _number();
          var y2 = _number();
          var x = _number();
          var y = _number();
          if (rel) {
            x2 += cx;
            y2 += cy;
            x += cx;
            y += cy;
          }
          final x1 = prevCtrlX == null ? cx : 2 * cx - prevCtrlX;
          final y1 = prevCtrlY == null ? cy : 2 * cy - prevCtrlY;
          path.cubicTo(x1, y1, x2, y2, x, y);
          lastCtrlX = x2;
          lastCtrlY = y2;
          cx = x;
          cy = y;
        case 'A':
          final rx = _number();
          final ry = _number();
          final rotation = _number();
          final largeArc = _flag();
          final sweep = _flag();
          var x = _number();
          var y = _number();
          if (rel) {
            x += cx;
            y += cy;
          }
          // Flutter's arcToPoint takes the end point in absolute coordinates,
          // the radius pair, the rotation in degrees, and the arc flags, which
          // is the SVG endpoint parameterization.
          path.arcToPoint(
            Offset(x, y),
            radius: Radius.elliptical(rx, ry),
            rotation: rotation,
            largeArc: largeArc,
            clockwise: sweep,
          );
          cx = x;
          cy = y;
        case 'Z':
          path.close();
          cx = sx;
          cy = sy;
        default:
          throw FormatException('Unsupported SVG command "$cmd"', _s, _i - 1);
      }
    }
    return path;
  }

  bool get _atEnd => _i >= _s.length;

  void _skipSeparators() {
    while (_i < _s.length && _isSeparator(_s[_i])) {
      _i++;
    }
  }

  double _number() {
    _skipSeparators();
    final start = _i;
    if (_i < _s.length && (_s[_i] == '+' || _s[_i] == '-')) _i++;
    var digits = _skipDigits();
    if (_i < _s.length && _s[_i] == '.') {
      _i++;
      digits = _skipDigits() || digits;
    }
    if (!digits) {
      throw FormatException('Expected a number', _s, start);
    }
    if (_i < _s.length && (_s[_i] == 'e' || _s[_i] == 'E')) {
      _i++;
      if (_i < _s.length && (_s[_i] == '+' || _s[_i] == '-')) _i++;
      if (!_skipDigits()) {
        throw FormatException('Expected exponent digits', _s, _i);
      }
    }
    return double.parse(_s.substring(start, _i));
  }

  /// Arc flags are a single `0` or `1`, optionally followed without a
  /// separator by the next number.
  bool _flag() {
    _skipSeparators();
    if (_i < _s.length && (_s[_i] == '0' || _s[_i] == '1')) {
      final value = _s[_i] == '1';
      _i++;
      return value;
    }
    throw FormatException('Expected arc flag 0 or 1', _s, _i);
  }

  bool _skipDigits() {
    final start = _i;
    while (_i < _s.length && _isDigit(_s[_i])) {
      _i++;
    }
    return _i > start;
  }

  static bool _isDigit(String c) =>
      c.codeUnitAt(0) >= 0x30 && c.codeUnitAt(0) <= 0x39;

  static bool _isSeparator(String c) =>
      c == ' ' || c == ',' || c == '\n' || c == '\r' || c == '\t';

  static bool _isLetter(String c) {
    final u = c.codeUnitAt(0);
    return (u >= 0x41 && u <= 0x5a) || (u >= 0x61 && u <= 0x7a);
  }

  static bool _isOneOf(String c, String set) => set.contains(c);
}
