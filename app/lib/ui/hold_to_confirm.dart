import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/haptics/r_haptics.dart';
import '../core/theme/reduced_motion.dart';
import '../core/theme/theme_extensions.dart';
import '../core/theme/tokens.g.dart';
import 'r_icon.dart';

/// Outline width of the capsule (artboard P03, 1.5 dp). Not a token.
const double _outlineWidth = 1.5;

/// Icon size inside the capsule (artboard P03, 22 dp). Not a token.
const double _iconSize = 22;

/// Icon stroke in viewBox units (artboard P03, 2.2). Not a token.
const double _iconStroke = 2.2;

/// Progress at which the haptic `holdHalf` fires.
const double _halfwayProgress = 0.5;

/// Progress from which the label switches to `onDanger` (artboard P04).
const double _labelSwitchProgress = 0.55;

/// Press-and-hold confirmation control (`design/components.md` C12).
///
/// Visual and gesture primitive with no domain knowledge: all copy is passed
/// in. The fill runs linearly over [RMotion.hold]. Releasing early rewinds the
/// fill over [RMotion.holdRewind] and shows [releasedHint] in bold. Leaving
/// the area or a pointer cancel resets without [releasedHint]. A plain tap
/// does nothing.
///
/// When the fill reaches 100% [onCompleted] is called once. The control then
/// stays locked until the parent rebuilds it with a new key.
///
/// Screen reader users get [semanticsLabel] with [semanticsHint]. Double-tap
/// and hold (long press) calls [onCompleted] directly, as does
/// [customActionLabel]. The countdown after this control is the safety net.
final class HoldToConfirm extends ConsumerStatefulWidget {
  const HoldToConfirm({
    super.key,
    required this.label,
    required this.icon,
    required this.idleHint,
    required this.holdingHint,
    required this.releasedHint,
    required this.semanticsLabel,
    required this.semanticsHint,
    required this.customActionLabel,
    required this.onCompleted,
  });

  /// Text inside the capsule, e.g. "Tahan buat matiin".
  final String label;

  /// Icon inside the capsule.
  final RIconData icon;

  /// Hint below the capsule while idle.
  final String idleHint;

  /// Hint below the capsule while the pointer is down.
  final String holdingHint;

  /// Bold hint shown after an early release.
  final String releasedHint;

  /// Semantics label of the control.
  final String semanticsLabel;

  /// Semantics hint, e.g. "tahan" (the hold gesture).
  final String semanticsHint;

  /// Name of the custom Semantics action that completes at once.
  final String customActionLabel;

  /// Called once when the hold completes or the custom action runs.
  final VoidCallback onCompleted;

  @override
  ConsumerState<HoldToConfirm> createState() => _HoldToConfirmState();
}

final class _HoldToConfirmState extends ConsumerState<HoldToConfirm>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  final GlobalKey _capsuleKey = GlobalKey();

  bool _pressing = false;
  bool _released = false;
  bool _halfFired = false;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: RMotion.hold)
      ..addListener(_onTick);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Drives both haptics and completion from the value, so the frame that
  /// reaches 100 % is the one that completes (status can lag a frame).
  void _onTick() {
    if (!_pressing || _completed) return;
    if (!_halfFired && _controller.value >= _halfwayProgress) {
      _halfFired = true;
      ref.read(hapticsProvider).holdHalf();
    }
    if (_controller.value >= 1) {
      ref.read(hapticsProvider).holdDone();
      _finish();
    }
  }

  void _finish() {
    if (_completed) return;
    _completed = true;
    _pressing = false;
    _released = false;
    widget.onCompleted();
  }

  /// Semantics path: completes at once, without the hold.
  void _completeNow() {
    if (_completed) return;
    setState(() => _pressing = false);
    _controller.stop();
    _controller.value = 1;
    _finish();
  }

  void _handleDown(PointerDownEvent event) {
    if (_completed) return;
    setState(() {
      _pressing = true;
      _released = false;
      _halfFired = false;
    });
    _controller.forward();
  }

  void _handleMove(PointerMoveEvent event) {
    if (!_pressing) return;
    final box = _capsuleKey.currentContext?.findRenderObject() as RenderBox?;
    final size = box?.size;
    if (size == null || !(Offset.zero & size).contains(event.localPosition)) {
      _endPress(released: false);
    }
  }

  void _handleUp(PointerUpEvent event) => _endPress(released: true);

  void _handleCancel(PointerCancelEvent event) => _endPress(released: false);

  void _endPress({required bool released}) {
    if (!_pressing) return;
    _pressing = false;
    _released = released;
    final reduced = ReducedMotion.of(context);
    _controller.animateTo(0, duration: reduced.duration(RMotion.holdRewind));
    setState(() {});
  }

  String get _hint {
    if (_pressing || _completed) return widget.holdingHint;
    if (_released) return widget.releasedHint;
    return widget.idleHint;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final releasedShown = _released && !_pressing && !_completed;
    final hintBase = theme.textTheme.bodySmall ?? const TextStyle();

    return Semantics(
      button: true,
      label: widget.semanticsLabel,
      hint: widget.semanticsHint,
      onLongPress: _completeNow,
      customSemanticsActions: {
        CustomSemanticsAction(label: widget.customActionLabel): _completeNow,
      },
      excludeSemantics: true,
      child: SizedBox(
        width: double.infinity,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              key: _capsuleKey,
              width: double.infinity,
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: _handleDown,
                onPointerMove: _handleMove,
                onPointerUp: _handleUp,
                onPointerCancel: _handleCancel,
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) => _capsule(context, _controller.value),
                ),
              ),
            ),
            const SizedBox(height: RSpace.s2),
            Text(
              _hint,
              textAlign: TextAlign.center,
              style: hintBase.copyWith(
                color: releasedShown
                    ? scheme.onSurface
                    : scheme.onSurfaceVariant,
                fontWeight: releasedShown ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _capsule(BuildContext context, double progress) {
    final status = context.status;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final labelColor = progress >= _labelSwitchProgress
        ? scheme.onError
        : status.dangerText;
    final labelStyle = (theme.textTheme.labelLarge ?? const TextStyle())
        .copyWith(color: labelColor);

    return DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(RRadius.full),
        border: Border.all(color: status.dangerText, width: _outlineWidth),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(RRadius.full),
        child: ColoredBox(
          color: status.dangerSoft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: RSize.hold),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned.fill(
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: progress,
                    child: ColoredBox(color: scheme.error),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: RSpace.s5),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      RIcon(
                        widget.icon,
                        size: _iconSize,
                        color: labelColor,
                        strokeWidth: _iconStroke,
                      ),
                      const SizedBox(width: RSpace.s2),
                      Flexible(
                        child: Text(
                          widget.label,
                          textAlign: TextAlign.center,
                          style: labelStyle,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
