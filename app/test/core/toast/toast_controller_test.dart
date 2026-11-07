import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotto/core/toast/toast_controller.dart';

void main() {
  test('show replaces the current toast', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final c = container.read(toastControllerProvider.notifier);

    const first = ToastMessage(text: 'satu');
    const second = ToastMessage(text: 'dua');
    c.show(first);
    c.show(second);

    expect(container.read(toastControllerProvider), same(second));
  });

  test('dismiss clears only the toast that is still shown', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final c = container.read(toastControllerProvider.notifier);

    const old = ToastMessage(text: 'lama');
    const current = ToastMessage(text: 'baru');
    c.show(old);
    c.show(current);

    c.dismiss(old);
    expect(container.read(toastControllerProvider), same(current));

    c.dismiss(current);
    expect(container.read(toastControllerProvider), isNull);
  });

  test('bottom inset defaults to 0 until the dock overrides it', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(toastBottomInsetProvider), 0);
  });
}
