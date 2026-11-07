import 'package:flutter_test/flutter_test.dart';
import 'package:remotto/ui/r_icon.dart';
import 'package:remotto/ui/status_pill.dart';

import '../support/test_app.dart';

StatusPill _pill(StatusPillVariant variant, {String? label}) => StatusPill(
  variant: variant,
  label: label ?? _labelFor(variant),
  semanticsLabel: _semanticsFor(variant),
);

String _labelFor(StatusPillVariant variant) => switch (variant) {
  StatusPillVariant.online => 'NYAMBUNG · 3J 12M',
  StatusPillVariant.back => 'NYAMBUNG LAGI',
  StatusPillVariant.connecting => 'MENYAMBUNG…',
  StatusPillVariant.offline => 'NGGAK KEJANGKAU',
  StatusPillVariant.off => 'LAGI MATI',
};

String _semanticsFor(StatusPillVariant variant) => switch (variant) {
  StatusPillVariant.online => 'NYAMBUNG',
  StatusPillVariant.back => 'NYAMBUNG LAGI',
  StatusPillVariant.connecting => 'MENYAMBUNG',
  StatusPillVariant.offline => 'NGGAK KEJANGKAU',
  StatusPillVariant.off => 'LAGI MATI',
};

void main() {
  for (final variant in StatusPillVariant.values) {
    testWidgets('$variant shows its visible label in light and dark', (
      tester,
    ) async {
      for (final dark in [false, true]) {
        await pumpApp(tester, _pill(variant), dark: dark);
        expect(find.text(_labelFor(variant)), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });
  }

  testWidgets('online label includes uptime but semantics does not', (
    tester,
  ) async {
    await pumpApp(tester, _pill(StatusPillVariant.online));

    expect(find.text('NYAMBUNG · 3J 12M'), findsOneWidget);
    final node = tester.getSemantics(find.bySemanticsLabel('NYAMBUNG'));
    expect(node.label, 'NYAMBUNG');
    expect(node.label, isNot(contains('3J')));
  });

  testWidgets('semantics node is a live region with a static label', (
    tester,
  ) async {
    for (final variant in StatusPillVariant.values) {
      await pumpApp(tester, _pill(variant));
      final node = tester.getSemantics(
        find.bySemanticsLabel(_semanticsFor(variant)),
      );
      expect(node.flagsCollection.isLiveRegion, isTrue, reason: '$variant');
    }
  });

  testWidgets('back and offline and off variants draw their icon', (
    tester,
  ) async {
    await pumpApp(tester, _pill(StatusPillVariant.back));
    expect(find.byType(RIcon), findsOneWidget);

    await pumpApp(tester, _pill(StatusPillVariant.offline));
    await tester.pumpAndSettle();
    expect(find.byType(RIcon), findsOneWidget);

    await pumpApp(tester, _pill(StatusPillVariant.off));
    await tester.pumpAndSettle();
    expect(find.byType(RIcon), findsOneWidget);
  });

  testWidgets('online and connecting draw a dot or ring, not an icon', (
    tester,
  ) async {
    await pumpApp(tester, _pill(StatusPillVariant.online));
    expect(find.byType(RIcon), findsNothing);

    await pumpApp(tester, _pill(StatusPillVariant.connecting));
    await tester.pumpAndSettle();
    expect(find.byType(RIcon), findsNothing);
  });

  testWidgets('variant change swaps label immediately when reduced motion', (
    tester,
  ) async {
    await pumpApp(
      tester,
      _pill(StatusPillVariant.online),
      disableAnimations: true,
    );
    await pumpApp(
      tester,
      _pill(StatusPillVariant.offline),
      disableAnimations: true,
    );
    await tester.pump();

    expect(find.text('NGGAK KEJANGKAU'), findsOneWidget);
    expect(find.text('NYAMBUNG · 3J 12M'), findsNothing);
  });

  testWidgets('variant change crossfades when motion is allowed', (
    tester,
  ) async {
    await pumpApp(tester, _pill(StatusPillVariant.online));
    await pumpApp(tester, _pill(StatusPillVariant.offline));
    await tester.pump();

    // Mid-transition: both labels are still in the tree.
    expect(find.text('NYAMBUNG · 3J 12M'), findsOneWidget);
    expect(find.text('NGGAK KEJANGKAU'), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.text('NYAMBUNG · 3J 12M'), findsNothing);
    expect(find.text('NGGAK KEJANGKAU'), findsOneWidget);
  });
}
