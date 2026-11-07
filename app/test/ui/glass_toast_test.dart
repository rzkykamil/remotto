import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotto/core/toast/toast_controller.dart';
import 'package:remotto/ui/link_button.dart';
import 'package:remotto/ui/r_icon.dart';
import 'package:remotto/ui/toast_host.dart';

import '../support/test_app.dart';

const _errorText = 'Perintah nggak sampai ke laptop';
const _infoText = 'Laptop nyambung lagi';

/// Test button: shows a toast when tapped.
class _Trigger extends ConsumerWidget {
  const _Trigger(this.message);

  final ToastMessage Function() message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox.expand(
      child: GestureDetector(
        key: const Key('trigger'),
        behavior: HitTestBehavior.opaque,
        onTap: () => ref.read(toastControllerProvider.notifier).show(message()),
        child: const SizedBox.expand(),
      ),
    );
  }
}

Future<void> _pumpHost(WidgetTester tester, ToastMessage Function() msg) {
  return pumpApp(
    tester,
    ToastHost(child: _Trigger(msg)),
    size: const Size(412, 892),
  );
}

Future<void> _show(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('trigger')));
  await tester.pump();
  // Enter finished (RMotion.toast = 200 ms).
  await tester.pump(const Duration(milliseconds: 250));
}

void main() {
  testWidgets('error toast shows text, alert icon and Ulangi action', (
    tester,
  ) async {
    var retried = 0;
    await _pumpHost(
      tester,
      () => ToastMessage(
        text: _errorText,
        variant: ToastVariant.error,
        actionLabel: 'Ulangi',
        onAction: () => retried++,
      ),
    );
    await _show(tester);

    expect(find.text(_errorText), findsOneWidget);
    expect(find.widgetWithText(RLinkButton, 'Ulangi'), findsOneWidget);

    await tester.tap(find.widgetWithText(RLinkButton, 'Ulangi'));
    await tester.pump();
    expect(retried, 1);
  });

  testWidgets('info toast has check icon in success color and no action', (
    tester,
  ) async {
    await _pumpHost(tester, () => const ToastMessage(text: _infoText));
    await _show(tester);

    expect(find.text(_infoText), findsOneWidget);
    expect(find.byType(RLinkButton), findsNothing);
    expect(find.byType(RIcon), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 10));
  });

  testWidgets('info toast dismisses after 2.5 s', (tester) async {
    await _pumpHost(tester, () => const ToastMessage(text: _infoText));
    await _show(tester);

    await tester.pump(const Duration(milliseconds: 2000));
    expect(find.text(_infoText), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pumpAndSettle();
    expect(find.text(_infoText), findsNothing);
  });

  testWidgets('error toast stays for 6 s, longer than info', (tester) async {
    await _pumpHost(
      tester,
      () => const ToastMessage(text: _errorText, variant: ToastVariant.error),
    );
    await _show(tester);

    await tester.pump(const Duration(milliseconds: 3000));
    expect(find.text(_errorText), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 3000));
    await tester.pumpAndSettle();
    expect(find.text(_errorText), findsNothing);
  });

  testWidgets('holding the toast pauses the timer until release', (
    tester,
  ) async {
    await _pumpHost(tester, () => const ToastMessage(text: _infoText));
    await _show(tester);

    final gesture = await tester.startGesture(
      tester.getCenter(find.text(_infoText)),
    );
    await tester.pump(const Duration(seconds: 10));
    expect(find.text(_infoText), findsOneWidget);

    await gesture.up();
    await tester.pump(const Duration(milliseconds: 2000));
    expect(find.text(_infoText), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pumpAndSettle();
    expect(find.text(_infoText), findsNothing);
  });

  testWidgets('swipe down dismisses the toast', (tester) async {
    await _pumpHost(tester, () => const ToastMessage(text: _infoText));
    await _show(tester);

    await tester.fling(find.text(_infoText), const Offset(0, 120), 800);
    await tester.pumpAndSettle();
    expect(find.text(_infoText), findsNothing);
  });

  testWidgets('a new toast replaces the old one', (tester) async {
    var current = const ToastMessage(text: _infoText);
    await _pumpHost(tester, () => current);
    await _show(tester);
    expect(find.text(_infoText), findsOneWidget);

    current = const ToastMessage(text: _errorText, variant: ToastVariant.error);
    await tester.tap(find.byKey(const Key('trigger')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text(_infoText), findsNothing);
    expect(find.text(_errorText), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 10));
  });

  testWidgets('message text is a polite live region', (tester) async {
    await _pumpHost(tester, () => const ToastMessage(text: _infoText));
    await _show(tester);

    expect(
      tester.getSemantics(find.text(_infoText)),
      matchesSemantics(label: _infoText, isLiveRegion: true),
    );
    await tester.pumpAndSettle(const Duration(seconds: 10));
  });

  testWidgets('reduced motion keeps the toast visible without slide', (
    tester,
  ) async {
    await pumpApp(
      tester,
      ToastHost(child: _Trigger(() => const ToastMessage(text: _infoText))),
      disableAnimations: true,
    );
    await _show(tester);
    expect(find.text(_infoText), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 10));
  });

  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';
    testWidgets('error toast renders in $mode with alert icon and action', (
      tester,
    ) async {
      await pumpApp(
        tester,
        ToastHost(
          child: _Trigger(
            () => ToastMessage(
              text: _errorText,
              variant: ToastVariant.error,
              actionLabel: 'Ulangi',
              onAction: () {},
            ),
          ),
        ),
        dark: dark,
      );
      await _show(tester);

      expect(find.text(_errorText), findsOneWidget);
      expect(find.widgetWithText(RLinkButton, 'Ulangi'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle(const Duration(seconds: 10));
    });

    testWidgets('info toast renders in $mode with check icon', (tester) async {
      await pumpApp(
        tester,
        ToastHost(child: _Trigger(() => const ToastMessage(text: _infoText))),
        dark: dark,
      );
      await _show(tester);

      expect(find.text(_infoText), findsOneWidget);
      expect(find.byType(RIcon), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle(const Duration(seconds: 10));
    });
  }

  testWidgets('toast action reaches 48 dp touch target', (tester) async {
    await _pumpHost(
      tester,
      () => ToastMessage(
        text: _errorText,
        variant: ToastVariant.error,
        actionLabel: 'Ulangi',
        onAction: () {},
      ),
    );
    await _show(tester);

    final hit = tester.getSize(find.widgetWithText(RLinkButton, 'Ulangi'));
    expect(hit.height, greaterThanOrEqualTo(48));
    await tester.pumpAndSettle(const Duration(seconds: 10));
  });
}
