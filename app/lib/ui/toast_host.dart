import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/tokens.g.dart';
import '../core/toast/toast_controller.dart';
import 'glass_toast.dart';

/// Shows the active toast above [child]. Installed once at the app root
/// (MaterialApp.router builder), so all screens share one queue.
///
/// The toast sits 12 dp above the dock: the distance from [toastBottomInsetProvider]
/// plus the bottom safe area. Left and right use RSpace.s6.
class ToastHost extends ConsumerWidget {
  const ToastHost({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final message = ref.watch(toastControllerProvider);
    final dockInset = ref.watch(toastBottomInsetProvider);
    final bottom = MediaQuery.paddingOf(context).bottom + dockInset + RSpace.s3;

    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        if (message != null)
          Positioned(
            left: RSpace.s6,
            right: RSpace.s6,
            bottom: bottom,
            child: GlassToast(
              key: ObjectKey(message),
              message: message,
              onDismiss: () =>
                  ref.read(toastControllerProvider.notifier).dismiss(message),
            ),
          ),
      ],
    );
  }
}
