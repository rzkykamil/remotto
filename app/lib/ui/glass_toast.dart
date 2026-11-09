import 'dart:async';

import 'package:flutter/material.dart';

import '../core/theme/reduced_motion.dart';
import '../core/theme/theme_extensions.dart';
import '../core/theme/tokens.g.dart';
import '../core/toast/toast_controller.dart';
import 'glass_panel.dart';
import 'link_button.dart';
import 'r_icon.dart';
import 'r_icons_data.dart';

/// Toast icon size (`design/components.md` C07: icon 18 dp).
const double _iconSize = 18;

/// Minimum downward drag (dp) for a downward swipe to count as dismissing the toast.
const double _swipeDismissDistance = 24;

/// Minimum downward velocity (dp/second) for a downward swipe to dismiss the toast.
const double _swipeDismissVelocity = 300;

/// Slide in and out distance (dp): the toast rises from the bottom when entering.
const double _slideDistance = 8;

/// Glass toast (`design/components.md` C07). Used via ToastHost, which
/// holds the single-toast queue and its position.
///
/// The timer pauses while the toast is touched and resumes when the finger lifts. Swiping
/// down dismisses the toast. Enter and exit use RMotion.toast; with
/// reduced motion it is only a fade.
///
/// Semantics: the message text is a liveRegion (polite). Focus is not moved.
class GlassToast extends StatefulWidget {
  const GlassToast({super.key, required this.message, required this.onDismiss});

  final ToastMessage message;

  /// Called after the exit animation finishes (timer, swipe, or system).
  final VoidCallback onDismiss;

  @override
  State<GlassToast> createState() => _GlassToastState();
}

final class _GlassToastState extends State<GlassToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  late final CurvedAnimation _curve;
  final Stopwatch _watch = Stopwatch();
  Timer? _timer;
  late Duration _remaining;
  bool _held = false;
  bool _closing = false;
  double _dragDy = 0;

  Duration get _lifetime => switch (widget.message.variant) {
    ToastVariant.error => RComponent.toastDurationError,
    ToastVariant.info => RComponent.toastDurationInfo,
  };

  @override
  void initState() {
    super.initState();
    _remaining = _lifetime;
    _anim = AnimationController(vsync: this, duration: RMotion.toast);
    _curve = CurvedAnimation(parent: _anim, curve: RMotion.standard);
    _anim.forward();
    _startTimer();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _anim.duration = ReducedMotion.of(context).duration(RMotion.toast);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _watch.stop();
    _curve.dispose();
    _anim.dispose();
    super.dispose();
  }

  void _startTimer() {
    if (_held || _closing) return;
    _watch
      ..reset()
      ..start();
    _timer = Timer(_remaining, _close);
  }

  void _pauseTimer() {
    _timer?.cancel();
    _timer = null;
    if (_watch.isRunning) {
      _watch.stop();
      _remaining -= _watch.elapsed;
      if (_remaining < Duration.zero) _remaining = Duration.zero;
    }
  }

  void _hold() {
    _held = true;
    _pauseTimer();
  }

  void _release() {
    _held = false;
    _startTimer();
  }

  /// Exit animation, then report to the caller. Runs only once.
  void _close() {
    if (_closing) return;
    _closing = true;
    _timer?.cancel();
    _watch.stop();
    _anim.reverse().whenComplete(() {
      if (mounted) widget.onDismiss();
    });
  }

  void _onDragUpdate(DragUpdateDetails details) {
    setState(() {
      _dragDy = (_dragDy + details.delta.dy).clamp(0.0, double.infinity);
    });
  }

  void _onDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (_dragDy > _swipeDismissDistance || velocity > _swipeDismissVelocity) {
      _close();
    } else {
      setState(() => _dragDy = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final slide = ReducedMotion.of(context).slide(_slideDistance);
    final isError = message.variant == ToastVariant.error;
    final actionLabel = message.actionLabel;
    final onAction = message.onAction;
    final style = Theme.of(context).textTheme.labelLarge!;

    final icon = isError
        ? RIcon(
            RIcons.alertTriangle,
            size: _iconSize,
            color: context.accent.text,
          )
        : RIcon(RIcons.check, size: _iconSize, color: context.status.success);

    final content = GlassPanel(
      variant: GlassPanelVariant.toast,
      padding: const EdgeInsets.fromLTRB(
        RSpace.s4,
        RSpace.s1,
        RSpace.s1,
        RSpace.s1,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: RSize.touchMin),
        child: Row(
          children: [
            icon,
            const SizedBox(width: RSpace.s3),
            Expanded(
              child: Semantics(
                liveRegion: true,
                child: Text(message.text, style: style),
              ),
            ),
            if (actionLabel != null && onAction != null)
              RLinkButton(
                label: actionLabel,
                semanticsLabel: actionLabel,
                onPressed: onAction,
              ),
          ],
        ),
      ),
    );

    return Listener(
      onPointerDown: (_) => _hold(),
      onPointerUp: (_) => _release(),
      onPointerCancel: (_) => _release(),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onVerticalDragUpdate: _onDragUpdate,
        onVerticalDragEnd: _onDragEnd,
        child: AnimatedBuilder(
          animation: _curve,
          child: content,
          builder: (context, child) {
            final t = _curve.value;
            return Opacity(
              opacity: t,
              child: Transform.translate(
                offset: Offset(0, (1 - t) * slide + _dragDy),
                child: child,
              ),
            );
          },
        ),
      ),
    );
  }
}
