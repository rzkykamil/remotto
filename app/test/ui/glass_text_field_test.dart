import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotto/core/strings/pairing_strings.dart';
import 'package:remotto/core/theme/theme_extensions.dart';
import 'package:remotto/ui/glass_text_field.dart';
import 'package:remotto/ui/r_icon.dart';
import 'package:remotto/ui/r_icons_data.dart';

import '../support/test_app.dart';

void main() {
  testWidgets('label, hint and text field render in light and dark mode', (
    tester,
  ) async {
    for (final dark in [false, true]) {
      await tester.pumpWidget(const SizedBox());
      await pumpApp(
        tester,
        const GlassTextField(
          label: PairingStrings.addressLabel,
          hintText: PairingStrings.addressExample,
        ),
        dark: dark,
      );

      expect(find.text(PairingStrings.addressLabel), findsOneWidget);
      expect(find.text(PairingStrings.addressExample), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('error shows message with alert icon in accent.text', (
    tester,
  ) async {
    await pumpApp(
      tester,
      const GlassTextField(
        label: PairingStrings.tokenLabel,
        errorText: PairingStrings.tokenFormatError,
      ),
    );

    expect(find.text(PairingStrings.tokenFormatError), findsOneWidget);
    final icon = tester.widget<RIcon>(find.byType(RIcon));
    expect(icon.data, RIcons.alertCircle);
    final context = tester.element(find.byType(GlassTextField));
    expect(icon.color, context.accent.text);
  });

  testWidgets('label and error are one semantics label on the field', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpApp(
      tester,
      const GlassTextField(
        label: PairingStrings.tokenLabel,
        errorText: PairingStrings.tokenFormatError,
      ),
    );

    expect(
      find.bySemanticsLabel(
        '${PairingStrings.tokenLabel}. ${PairingStrings.tokenFormatError}',
      ),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('disabled field refuses input', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await pumpApp(
      tester,
      GlassTextField(
        label: PairingStrings.addressLabel,
        controller: controller,
        enabled: false,
      ),
    );

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.enabled, isFalse);
  });

  testWidgets('trailing action is shown inside the field', (tester) async {
    await pumpApp(
      tester,
      const GlassTextField(
        label: PairingStrings.tokenLabel,
        obscureText: true,
        trailing: SizedBox(key: Key('trailing'), width: 48, height: 48),
      ),
    );

    expect(find.byKey(const Key('trailing')), findsOneWidget);
  });

  testWidgets('onFocusLost fires when focus leaves the field', (tester) async {
    final focus = FocusNode();
    final other = FocusNode();
    addTearDown(focus.dispose);
    addTearDown(other.dispose);
    var lost = 0;
    await pumpApp(
      tester,
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GlassTextField(
            label: PairingStrings.addressLabel,
            focusNode: focus,
            onFocusLost: () => lost++,
          ),
          TextField(focusNode: other),
        ],
      ),
    );

    focus.requestFocus();
    await tester.pump();
    expect(lost, 0);

    other.requestFocus();
    await tester.pump();
    expect(lost, 1);
  });

  testWidgets('typing calls onChanged and onSubmitted', (tester) async {
    final changes = <String>[];
    var submitted = 0;
    await pumpApp(
      tester,
      GlassTextField(
        label: PairingStrings.addressLabel,
        onChanged: changes.add,
        onSubmitted: (_) => submitted++,
      ),
    );

    await tester.enterText(find.byType(TextField), '192.168.1.20');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    expect(changes, ['192.168.1.20']);
    expect(submitted, 1);
  });
}
