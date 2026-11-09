import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotto/core/theme/app_theme.dart';
import 'package:remotto/core/theme/theme_extensions.dart';
import 'package:remotto/core/theme/tokens.g.dart';
import 'package:remotto/ui/volume_readout.dart';

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  bool dark = false,
  double textScale = 1.0,
  Size size = const Size(412, 892),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      builder: (context, widget) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: widget!,
      ),
      home: Scaffold(body: Center(child: child)),
    ),
  );
}

/// The rich text that holds the number, e.g. "35%".
Finder _numberFinder(String plain) => find.byWidgetPredicate(
  (w) => w is RichText && w.text.toPlainText() == plain,
);

TextStyle _numberStyle(WidgetTester tester, String plain) {
  final rich = tester.widget<RichText>(_numberFinder(plain));
  // Text.rich wraps the given span under the default text style.
  final root = rich.text as TextSpan;
  return (root.children!.first as TextSpan).style!;
}

void main() {
  testWidgets('shows the number and a percent sign', (tester) async {
    await _pump(tester, const VolumeReadout(value: 35, hint: null));

    expect(_numberFinder('35%'), findsOneWidget);
    expect(_numberStyle(tester, '35%').fontSize, RType.displayVolume.size);
  });

  testWidgets('shows an em dash while the value is unknown', (tester) async {
    await _pump(tester, const VolumeReadout(value: null, hint: null));

    expect(_numberFinder('—%'), findsOneWidget);
  });

  testWidgets('shows the hint under the number', (tester) async {
    await _pump(
      tester,
      const VolumeReadout(value: 50, hint: 'Geser atau ketuk − / +'),
    );

    expect(find.text('Geser atau ketuk − / +'), findsOneWidget);
  });

  testWidgets('null or empty hint takes no text', (tester) async {
    await _pump(tester, const VolumeReadout(value: 50, hint: null));
    expect(find.byType(Text), findsOneWidget);

    await _pump(tester, const VolumeReadout(value: 50, hint: ''));
    expect(find.byType(Text), findsOneWidget);
  });

  testWidgets('compact is 108 sp and short is 96 sp; short wins', (
    tester,
  ) async {
    await _pump(
      tester,
      const VolumeReadout(value: 35, hint: null, compact: true),
    );
    expect(_numberStyle(tester, '35%').fontSize, 108);

    await _pump(
      tester,
      const VolumeReadout(value: 35, hint: null, compact: true, short: true),
    );
    expect(_numberStyle(tester, '35%').fontSize, 96);
  });

  testWidgets('tone sets the number colour', (tester) async {
    final accent = AppTheme.light.extension<AccentTokens>()!;
    final scheme = AppTheme.light.colorScheme;

    await _pump(
      tester,
      const VolumeReadout(
        value: 35,
        hint: null,
        tone: VolumeReadoutTone.dragging,
      ),
    );
    expect(_numberStyle(tester, '35%').color, accent.text);

    await _pump(
      tester,
      const VolumeReadout(value: 35, hint: null, tone: VolumeReadoutTone.dim),
    );
    expect(_numberStyle(tester, '35%').color, scheme.onSurfaceVariant);

    await _pump(tester, const VolumeReadout(value: 35, hint: null));
    expect(_numberStyle(tester, '35%').color, scheme.onSurface);
  });

  testWidgets('number is excluded from Semantics', (tester) async {
    await _pump(tester, const VolumeReadout(value: 35, hint: 'Paling pelan'));

    expect(
      find.descendant(
        of: find.byType(VolumeReadout),
        matching: find.byType(ExcludeSemantics),
      ),
      findsWidgets,
    );
  });

  for (final dark in [false, true]) {
    testWidgets('130% text at 360 dp does not overflow (dark: $dark)', (
      tester,
    ) async {
      await _pump(
        tester,
        const VolumeReadout(
          value: 100,
          hint: 'Suara laptop lagi dibisukan',
          compact: true,
        ),
        dark: dark,
        textScale: 1.3,
        size: const Size(360, 640),
      );

      expect(tester.takeException(), isNull);
    });
  }
}
