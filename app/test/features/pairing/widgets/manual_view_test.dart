import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:remotto/core/haptics/r_haptics.dart';
import 'package:remotto/core/storage/app_preferences.dart';
import 'package:remotto/core/storage/storage_providers.dart';
import 'package:remotto/core/strings/pairing_strings.dart';
import 'package:remotto/features/pairing/widgets/manual_view.dart';
import 'package:remotto/ui/glass_key.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/fakes.dart';
import '../../../support/test_app.dart';

Future<List<Override>> _overrides(RecordingHapticSink sink) async {
  SharedPreferences.setMockInitialValues({
    AppPreferences.keyHapticEnabled: true,
  });
  final prefs = await SharedPreferences.getInstance();
  return [
    hapticSinkProvider.overrideWithValue(sink),
    sharedPreferencesProvider.overrideWithValue(prefs),
  ];
}

GlassKey _connect(WidgetTester tester) => tester.widget<GlassKey>(
  find.byWidgetPredicate(
    (w) => w is GlassKey && w.semanticsLabel == PairingStrings.connect,
  ),
);

EditableText _field(WidgetTester tester, int index) =>
    tester.widget<EditableText>(find.byType(EditableText).at(index));

void main() {
  testWidgets('Q06: connect is disabled until both fields are filled', (
    tester,
  ) async {
    await pumpApp(tester, const ManualView());

    expect(find.text(PairingStrings.manualTitle), findsOneWidget);
    expect(_connect(tester).onPressed, isNull);

    await tester.enterText(find.byType(EditableText).at(0), '192.168.1.20');
    await tester.pump();
    expect(_connect(tester).onPressed, isNull);

    await tester.enterText(
      find.byType(EditableText).at(1),
      '0123456789abcdef' * 4,
    );
    await tester.pump();
    expect(_connect(tester).onPressed, isNotNull);
  });

  testWidgets('Q07: bad address shows format error after the field is left', (
    tester,
  ) async {
    await pumpApp(tester, const ManualView());

    await tester.enterText(find.byType(EditableText).at(0), '192.168.1');
    await tester.tap(find.byType(EditableText).at(1));
    await tester.pump();

    expect(find.text(PairingStrings.addressFormatError), findsOneWidget);
  });

  testWidgets('Q07: token of wrong length shows token error after blur', (
    tester,
  ) async {
    await pumpApp(tester, const ManualView());

    await tester.enterText(find.byType(EditableText).at(1), 'K7QF2M');
    await tester.tap(find.byType(EditableText).at(0));
    await tester.pump();

    expect(find.text(PairingStrings.tokenFormatError), findsOneWidget);
  });

  testWidgets('a field left empty is not flagged on blur', (tester) async {
    await pumpApp(tester, const ManualView());

    await tester.tap(find.byType(EditableText).at(0));
    await tester.tap(find.byType(EditableText).at(1));
    await tester.pump();

    expect(find.text(PairingStrings.addressFormatError), findsNothing);
    expect(find.text(PairingStrings.tokenFormatError), findsNothing);
  });

  testWidgets('token is hidden by default and the eye key reveals it', (
    tester,
  ) async {
    final sink = RecordingHapticSink();
    await pumpApp(
      tester,
      const ManualView(),
      overrides: await _overrides(sink),
    );

    expect(_field(tester, 1).obscureText, isTrue);

    await tester.tap(find.bySemanticsLabel(PairingStrings.tokenShow));
    await tester.pump();
    expect(_field(tester, 1).obscureText, isFalse);
    expect(find.bySemanticsLabel(PairingStrings.tokenHide), findsOneWidget);
  });
}
