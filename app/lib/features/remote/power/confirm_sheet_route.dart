import 'package:flutter/widgets.dart';

import '../../../core/strings/power_strings.dart';
import '../../../core/theme/reduced_motion.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../core/theme/tokens.g.dart';
import '../data/power_repository.dart';
import '../widgets/confirm_sheet.dart';

/// Opens [ConfirmSheet] as a non-opaque modal route over the current screen
/// (`design/components.md` C11).
///
/// Completes with the [PowerAction] once the user confirms. Completes with
/// null for every way of cancelling: "Nggak jadi", a tap on the scrim, a
/// downward swipe on the handle, and the system back button. Focus returns to
/// the widget that had it before the sheet opened.
///
/// The route is built from [context], so the caller must be under the app's
/// theme and [MediaQuery]. Durations follow reduce-motion: a fade replaces
/// the slide when animations are off.
Future<PowerAction?> showConfirmSheet(
  BuildContext context, {
  required PowerAction action,
  required String laptopName,
  bool startAtStage2 = false,
}) async {
  final reduced = ReducedMotion.of(context);
  final previousFocus = FocusManager.instance.primaryFocus;
  final navigator = Navigator.of(context);

  final route = PageRouteBuilder<PowerAction>(
    opaque: false,
    barrierDismissible: true,
    barrierColor: context.glass.scrim,
    barrierLabel: PowerStrings.cancelAction,
    transitionDuration: reduced.duration(RMotion.sheetOpen),
    reverseTransitionDuration: reduced.duration(RMotion.sheetClose),
    settings: const RouteSettings(name: 'confirm_sheet'),
    pageBuilder: (routeContext, _, _) => Align(
      alignment: Alignment.bottomCenter,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(RSpace.s2),
          child: ConfirmSheet(
            action: action,
            laptopName: laptopName,
            startAtStage2: startAtStage2,
            onConfirmed: () => Navigator.of(routeContext).pop(action),
            onCancel: () => Navigator.of(routeContext).pop(),
          ),
        ),
      ),
    ),
    transitionsBuilder: (routeContext, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: reduced.curve(RMotion.standard),
        reverseCurve: reduced.curve(RMotion.accelerate),
      );
      if (reduced.enabled) {
        return FadeTransition(opacity: curved, child: child);
      }
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 1),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      );
    },
  );

  final result = await navigator.push<PowerAction>(route);

  if (previousFocus != null && previousFocus.context != null) {
    previousFocus.requestFocus();
  }
  return result;
}
