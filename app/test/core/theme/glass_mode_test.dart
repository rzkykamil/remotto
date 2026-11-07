import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotto/core/theme/glass_mode.dart';

/// Pumps a probe that reads [GlassMode] inside a real build with the given
/// high-contrast flag and the given provider container.
Future<({bool Function() solid, GlassFallbackReason Function() reason})>
_pumpProbe(
  WidgetTester tester, {
  required ProviderContainer container,
  bool highContrast = false,
}) async {
  late bool solid;
  late GlassFallbackReason reason;

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MediaQuery(
        data: MediaQueryData(highContrast: highContrast),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Consumer(
            builder: (context, ref, _) {
              solid = GlassMode.isSolid(context, ref);
              reason = GlassMode.reason(context, ref);
              return const SizedBox();
            },
          ),
        ),
      ),
    ),
  );

  return (solid: () => solid, reason: () => reason);
}

void main() {
  testWidgets('default is not solid and reason is none', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final probe = await _pumpProbe(tester, container: container);

    expect(probe.solid(), isFalse);
    expect(probe.reason(), GlassFallbackReason.none);
  });

  testWidgets('high contrast makes glass solid', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final probe = await _pumpProbe(
      tester,
      container: container,
      highContrast: true,
    );

    expect(probe.solid(), isTrue);
    expect(probe.reason(), GlassFallbackReason.highContrast);
  });

  testWidgets('reduceTransparencyProvider makes glass solid', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(reduceTransparencyProvider.notifier).set(true);

    final probe = await _pumpProbe(tester, container: container);

    expect(probe.solid(), isTrue);
    expect(probe.reason(), GlassFallbackReason.reduceTransparency);
  });

  testWidgets('slowRasterProvider makes glass solid', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(slowRasterProvider.notifier).set(true);

    final probe = await _pumpProbe(tester, container: container);

    expect(probe.solid(), isTrue);
    expect(probe.reason(), GlassFallbackReason.slowRaster);
  });

  testWidgets('reason order: reduce transparency beats high contrast', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(reduceTransparencyProvider.notifier).set(true);

    final probe = await _pumpProbe(
      tester,
      container: container,
      highContrast: true,
    );

    expect(probe.reason(), GlassFallbackReason.reduceTransparency);
  });

  testWidgets('reason order: high contrast beats slow raster', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(slowRasterProvider.notifier).set(true);

    final probe = await _pumpProbe(
      tester,
      container: container,
      highContrast: true,
    );

    expect(probe.reason(), GlassFallbackReason.highContrast);
  });

  testWidgets('solid state reacts when the flag changes', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final probe = await _pumpProbe(tester, container: container);
    expect(probe.solid(), isFalse);

    container.read(slowRasterProvider.notifier).set(true);
    await tester.pump();
    expect(probe.solid(), isTrue);
  });
}
