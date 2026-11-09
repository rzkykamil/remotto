import 'package:flutter/foundation.dart' show VoidCallback;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Toast kind (`design/components.md` C07). Error uses a warning icon
/// and an optional action; info uses a green check with no action.
enum ToastVariant { error, info }

/// Content of one toast. Object identity is used to recognize the same
/// toast, so each [ToastController.show] creates a new instance.
final class ToastMessage {
  const ToastMessage({
    required this.text,
    this.variant = ToastVariant.info,
    this.actionLabel,
    this.onAction,
  });

  final String text;
  final ToastVariant variant;

  /// Optional text action, e.g. "Ulangi". Null means no action button.
  final String? actionLabel;
  final VoidCallback? onAction;
}

/// One active toast at a time. [show] replaces the toast currently shown.
final class ToastController extends Notifier<ToastMessage?> {
  @override
  ToastMessage? build() => null;

  void show(ToastMessage message) => state = message;

  /// Closes [message] only if it is still the toast shown. A toast that was
  /// replaced is not closed.
  void dismiss(ToastMessage message) {
    if (identical(state, message)) {
      state = null;
    }
  }
}

final toastControllerProvider =
    NotifierProvider<ToastController, ToastMessage?>(ToastController.new);

/// Height of the media dock at the bottom of the screen, in dp. The toast sits above it
/// with a 12 dp gap (C07). The Remote screen sets it while open and resets it to 0
/// when closed.
final class ToastBottomInset extends Notifier<double> {
  @override
  double build() => 0;

  /// No-op after the provider is disposed, e.g. when the app container closes
  /// while a screen is still unmounting.
  void set(double value) {
    if (!ref.mounted) return;
    state = value;
  }
}

final toastBottomInsetProvider = NotifierProvider<ToastBottomInset, double>(
  ToastBottomInset.new,
);
