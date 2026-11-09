import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../theme/reduced_motion.dart';
import '../theme/tokens.g.dart';

/// Halaman layar dengan fade dan geser 24 dp masuk (design-system.md section 6).
///
/// Reduced motion: durasi `fast` dan tanpa geser (fade saja). Durasi dihitung
/// dari [context] saat halaman dibuat; geser dibaca lagi di dalam builder.
CustomTransitionPage<void> appPage(
  BuildContext context,
  GoRouterState state,
  Widget child,
) {
  final motion = ReducedMotion.of(context);
  final duration = motion.duration(RMotion.screen);

  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: duration,
    reverseTransitionDuration: duration,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final reduced = ReducedMotion.of(context);
      final curved = CurvedAnimation(
        parent: animation,
        curve: reduced.curve(RMotion.standard),
      );
      final slide = reduced.slide(RSpace.s6);

      return FadeTransition(
        opacity: curved,
        child: AnimatedBuilder(
          animation: curved,
          builder: (context, child) => Transform.translate(
            offset: Offset(0, slide * (1 - curved.value)),
            child: child,
          ),
          child: child,
        ),
      );
    },
  );
}
