import 'dart:async';

import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/connection/connection_providers.dart';
import '../../../core/connection/connection_state.dart';
import '../../../core/network/agent_status.dart';
import '../../../core/storage/storage_providers.dart';
import '../../../core/strings/power_strings.dart';
import '../../../core/theme/reduced_motion.dart';
import '../../../core/theme/tokens.g.dart';
import '../../../core/toast/toast_controller.dart';
import '../data/power_repository.dart';
import 'confirm_sheet_route.dart';
import 'countdown_screen.dart';
import 'power_flow_state.dart';
import 'power_providers.dart';
import 'result_screen.dart';

/// Builds the Remote content. [onSelected] starts the confirm flow for a
/// power key (`PowerRow`).
typedef PowerFlowBuilder = Widget Function(
  BuildContext context,
  ValueChanged<PowerAction> onSelected,
);

/// Owns the navigation of the power flow over the Remote screen
/// (`design/scope-and-flows.md` (c), `design/components.md` C11, C13, C14).
///
/// This is the only place that listens to [powerFlowControllerProvider] and
/// decides which route is open:
/// - countdown (C13) while scheduling, counting, and cancelling;
/// - result (C14) for sent, not scheduled, and too late;
/// - toast on Remote after a cancel (P08), then the flow is dismissed.
///
/// A `pending` schedule from the status poll starts the countdown (P13) or the
/// too-late screen (P14) while the flow is idle (T11, FR-4.9, FR-4.10). The
/// controller decides whether the schedule is shown.
///
/// At most one flow route is open at a time. The routes are pushed on the
/// Navigator above Remote, not through go_router, because they are temporary
/// modals on top of Remote.
///
/// Nothing is sent without the user. "Coba lagi" after a failed schedule opens
/// the confirm sheet again, and the user confirms once more.
final class PowerFlowHost extends ConsumerStatefulWidget {
  const PowerFlowHost({super.key, required this.builder});

  final PowerFlowBuilder builder;

  @override
  ConsumerState<PowerFlowHost> createState() => _PowerFlowHostState();
}

/// Screen kinds that [_PowerFlowHostState] can show.
enum _FlowScreen { countdown, result }

final class _PowerFlowHostState extends ConsumerState<PowerFlowHost> {
  /// The one route this host has open for the flow, or null.
  Route<void>? _route;

  /// What [_route] shows.
  _FlowScreen? _shown;

  /// Navigator that [_route] was pushed on. Kept because `dispose` cannot
  /// read it from the context.
  NavigatorState? _navigator;

  @override
  void initState() {
    super.initState();
    // A flow can already run when Remote opens again (the countdown outlives
    // the screen). Sync after the first frame, because routes are pushed then.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _onFlowChanged(ref.read(powerFlowControllerProvider));
      // A schedule the status already holds when this host mounts (app opened,
      // or Remote opened again). The connection phase is checked inside
      // [_livePending], so a stale status is not used before the first poll.
      _resumeFrom(_livePending(ref.read(connectionControllerProvider)));
    });
  }

  @override
  void dispose() {
    final route = _route;
    final navigator = _navigator;
    if (route != null && navigator != null) {
      // Remote can leave the stack while the flow route is open. dispose runs
      // during the tree update, where the Navigator cannot change, so remove
      // the route right after.
      scheduleMicrotask(() {
        if (route.isActive) navigator.removeRoute(route);
      });
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<PowerFlowState>(
      powerFlowControllerProvider,
      (previous, next) => _onFlowChanged(next),
    );
    // Fires on each new `pending` from the status poll, including one that
    // appears while Remote is open (for example scheduled from another phone).
    // Equal pending values from later polls do not fire it.
    ref.listen<Pending?>(
      connectionControllerProvider.select(_livePending),
      (previous, next) => _resumeFrom(next),
    );
    return widget.builder(context, _select);
  }

  // Routing -----------------------------------------------------------------

  void _onFlowChanged(PowerFlowState state) {
    switch (state) {
      case PowerFlowIdle():
        _closeFlow();
      case PowerFlowScheduling() ||
          PowerFlowCounting() ||
          PowerFlowCancelling():
        if (_shown != _FlowScreen.countdown) {
          _openRoute(_FlowScreen.countdown, const CountdownScreen());
        }
      case PowerFlowResult(:final result):
        switch (result) {
          case PowerCancelled(:final action):
            _closeFlow();
            ref
                .read(toastControllerProvider.notifier)
                .show(ToastMessage(text: _cancelledText(action)));
            ref.read(powerFlowControllerProvider.notifier).dismiss();
          case PowerSent() || PowerNotScheduled() || PowerTooLate():
            _openRoute(_FlowScreen.result, _resultScreen(result));
        }
    }
  }

  /// Starts the countdown (P13) or the too-late screen (P14) for [pending]. Only
  /// the controller decides: it ignores the call unless the flow is idle and the
  /// user has not closed this schedule. Null does nothing.
  void _resumeFrom(Pending? pending) {
    if (pending == null) return;
    ref.read(powerFlowControllerProvider.notifier).resumeFromStatus(pending);
  }

  /// Shows [screen] in place of the flow route that is open, or pushes it.
  void _openRoute(_FlowScreen kind, Widget screen) {
    final navigator = Navigator.of(context);
    final previous = _route;
    final route = _flowRoute(screen);

    _route = route;
    _shown = kind;
    _navigator = navigator;

    if (previous != null && previous.isActive) {
      if (previous.isCurrent) {
        unawaited(navigator.pushReplacement(route));
      } else {
        navigator.removeRoute(previous);
        unawaited(navigator.push(route));
      }
    } else {
      unawaited(navigator.push(route));
    }

    unawaited(
      route.popped.then((_) {
        if (identical(_route, route)) {
          _route = null;
          _shown = null;
        }
      }),
    );
  }

  /// Removes the flow route, if any. Does nothing when none is open.
  void _closeFlow() {
    final route = _route;
    final navigator = _navigator;
    _route = null;
    _shown = null;
    if (route == null || navigator == null || !route.isActive) return;
    if (route.isCurrent) {
      navigator.pop();
    } else {
      navigator.removeRoute(route);
    }
  }

  PageRouteBuilder<void> _flowRoute(Widget screen) {
    final reduced = ReducedMotion.of(context);
    return PageRouteBuilder<void>(
      // The countdown and result screens paint their own backdrop. Remote
      // stays mounted underneath.
      opaque: false,
      barrierDismissible: false,
      transitionDuration: reduced.duration(RMotion.screen),
      reverseTransitionDuration: reduced.duration(RMotion.screen),
      pageBuilder: (routeContext, animation, secondaryAnimation) => screen,
      transitionsBuilder: (routeContext, animation, secondaryAnimation, page) {
        return FadeTransition(
          opacity: CurvedAnimation(
            parent: animation,
            curve: reduced.curve(RMotion.standard),
          ),
          child: page,
        );
      },
    );
  }

  Widget _resultScreen(PowerResult result) {
    return ResultScreen(
      result: result,
      laptopName: _laptopName(),
      onPrimary: switch (result) {
        PowerNotScheduled(:final action) => () => _retry(action),
        _ => _dismiss,
      },
      onClose: result is PowerNotScheduled ? _dismiss : null,
    );
  }

  // Actions -----------------------------------------------------------------

  /// Power key tapped on Remote. Shows the confirm sheet, and sends the command
  /// only when the user confirms it.
  void _select(PowerAction action) {
    unawaited(_confirmAndBegin(action, startAtStage2: false));
  }

  Future<void> _confirmAndBegin(
    PowerAction action, {
    required bool startAtStage2,
  }) async {
    final confirmed = await showConfirmSheet(
      context,
      action: action,
      laptopName: _laptopName(),
      startAtStage2: startAtStage2,
    );
    if (confirmed == null || !mounted) return;
    await ref.read(powerFlowControllerProvider.notifier).begin(action);
  }

  /// P10 "Coba lagi": closes the result and opens the confirm sheet again.
  /// Shutdown and restart go straight to the hold step, because the user
  /// already confirmed them. Nothing is sent until the user confirms again.
  void _retry(PowerAction action) {
    ref.read(powerFlowControllerProvider.notifier).dismiss();
    unawaited(
      _confirmAndBegin(action, startAtStage2: action != PowerAction.sleep),
    );
  }

  void _dismiss() {
    ref.read(powerFlowControllerProvider.notifier).dismiss();
  }

  // Helpers -----------------------------------------------------------------

  /// The `pending` of the status, but only while the laptop is reachable
  /// (online or back). Offline phases keep the last status, which can be stale.
  static Pending? _livePending(ConnectionState state) {
    final reachable =
        state.phase == ConnectionPhase.online ||
        state.phase == ConnectionPhase.back;
    return reachable ? state.status?.pending : null;
  }

  /// Same source as the Remote header: the agent name, else the saved one.
  String _laptopName() {
    final status = ref.read(connectionControllerProvider).status;
    return status?.name ?? ref.read(pairingProvider)?.laptopName ?? '';
  }

  static String _cancelledText(PowerAction action) => switch (action) {
    PowerAction.shutdown => PowerStrings.toastCancelledShutdown,
    PowerAction.restart => PowerStrings.toastCancelledRestart,
    PowerAction.sleep => PowerStrings.toastCancelledSleep,
  };
}
