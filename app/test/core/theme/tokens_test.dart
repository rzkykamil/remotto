import 'package:flutter/animation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotto/core/theme/tokens.g.dart';

void main() {
  group('palette', () {
    test('base background matches design tokens for both modes', () {
      expect(kLightTokens.bg.base, const Color(0xFFEDE7DF));
      expect(kDarkTokens.bg.base, const Color(0xFF110F0D));
    });

    test('alpha 0.45 white becomes 0x73FFFFFF', () {
      expect(kLightTokens.glass.fill, const Color(0x73FFFFFF));
    });
  });

  group('scales', () {
    test('play key sizes', () {
      expect(RSize.play, 96);
      expect(RSize.playCompact, 88);
    });

    test('radius full', () {
      expect(RRadius.full, 999);
    });
  });

  group('motion', () {
    test('hold duration is 1200 ms', () {
      expect(RMotion.hold, const Duration(milliseconds: 1200));
    });

    test('spring easing control points', () {
      expect(RMotion.spring, const Cubic(0.34, 1.4, 0.64, 1));
    });
  });

  group('typography', () {
    test('displayVolume: size, height, letter spacing', () {
      expect(RType.displayVolume.size, 128);
      expect(RType.displayVolume.height, 1.0);
      expect(RType.displayVolume.letterSpacing, -0.04 * 128);
    });

    test('displayVolume uses the mono family and semibold weight', () {
      expect(RType.displayVolume.family, RFont.mono);
      expect(RType.displayVolume.weight, FontWeight.w600);
    });
  });
}
