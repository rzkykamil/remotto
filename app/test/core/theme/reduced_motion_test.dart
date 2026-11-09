import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotto/core/theme/reduced_motion.dart';
import 'package:remotto/core/theme/tokens.g.dart';

void main() {
  group('ReducedMotion when disabled (motion on)', () {
    const motion = ReducedMotion(false);

    test('keeps the normal duration', () {
      expect(
        motion.duration(RMotion.screen),
        const Duration(milliseconds: 280),
      );
    });

    test('keeps the normal curve', () {
      expect(motion.curve(RMotion.spring), same(RMotion.spring));
    });

    test('keeps the normal press scale', () {
      expect(motion.pressedScale(RComponent.keyPressedScale), 0.94);
    });

    test('keeps the normal slide distance', () {
      expect(motion.slide(RSpace.s6), RSpace.s6);
    });
  });

  group('ReducedMotion when enabled (reduced motion on)', () {
    const motion = ReducedMotion(true);

    test('uses the fast duration', () {
      expect(motion.duration(RMotion.screen), RMotion.fast);
    });

    test('uses a linear curve', () {
      expect(motion.curve(RMotion.spring), Curves.linear);
    });

    test('removes the press scale', () {
      expect(motion.pressedScale(RComponent.keyPressedScale), 1.0);
    });

    test('removes the slide', () {
      expect(motion.slide(RSpace.s6), 0.0);
    });
  });

  testWidgets('ReducedMotion.of reads MediaQuery.disableAnimations', (
    tester,
  ) async {
    late bool readValue;

    Widget probe(bool disableAnimations) => MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Builder(
          builder: (context) {
            readValue = ReducedMotion.of(context).enabled;
            return const SizedBox();
          },
        ),
      ),
    );

    await tester.pumpWidget(probe(false));
    expect(readValue, isFalse);

    await tester.pumpWidget(probe(true));
    expect(readValue, isTrue);
  });
}
