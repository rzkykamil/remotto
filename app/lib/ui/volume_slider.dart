import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter/material.dart';

import '../core/theme/theme_extensions.dart';
import '../core/theme/tokens.g.dart';

/// Level range of the laptop volume (`docs/api-spec.md`, 0 to 100).
const int _minLevel = 0;
const int _maxLevel = 100;

/// Handle is 5 x 24 dp, centred vertically (`States-light.dc.html`: track
/// handle width 5px, left calc(vol% - 14px)). No token.
const double _handleWidth = 5;
const double _handleHeight = 24;
const double _handleLeftOffset = 14;

/// Handle is hidden at or below this level (`vol > 6` in the artboard).
const int _handleHideAtOrBelow = 6;

/// Inset shadow `0 1px 2px glLo` approximated as a thin top gradient, since
/// Flutter has no inset box shadow. Share of the track height. No token.
const double _insetShadowStop = 0.12;

/// Level steps that trigger the detent haptic (`RComponent`).
const int _detentStep = RComponent.volumeSliderHapticDetent;

/// Maps a horizontal position in the track to a level, rounded and clamped to
/// 0 to 100. A zero or negative [width] gives 0.
int levelFromDx(double dx, double width) {
  if (width <= 0) return _minLevel;
  final raw = (dx / width * _maxLevel).round();
  return raw < _minLevel ? _minLevel : (raw > _maxLevel ? _maxLevel : raw);
}

/// Volume track (`design/components.md` C04). Pure UI primitive: the caller
/// owns the state and the haptics mapping of a detent or limit is given as
/// callbacks.
///
/// Tap on the track jumps to the level: start, changed, end. A horizontal
/// drag gives start, then changed per level step, then end. Vertical drags
/// are ignored. [enabled] false ignores all gestures; if it turns false while
/// dragging, [onCancel] fires once and no end event follows.
final class VolumeSlider extends StatefulWidget {
  const VolumeSlider({
    super.key,
    required this.value,
    required this.muted,
    required this.enabled,
    required this.dragging,
    required this.onChanged,
    required this.onChangeStart,
    required this.onChangeEnd,
    required this.onCancel,
    required this.semanticsLabel,
    required this.semanticsValue,
    required this.semanticsIncreasedValue,
    required this.semanticsDecreasedValue,
    required this.onIncrease,
    required this.onDecrease,
    required this.onDetent,
    required this.onLimit,
  });

  /// Current level, 0 to 100.
  final int value;

  /// True draws the fill in the disabled colour.
  final bool muted;

  /// False disables the slider and its gestures.
  final bool enabled;

  /// True draws the 68 dp track and stops animating the fill.
  final bool dragging;

  final ValueChanged<int> onChanged;
  final ValueChanged<int> onChangeStart;
  final ValueChanged<int> onChangeEnd;
  final VoidCallback onCancel;

  /// Semantics label, from the caller.
  final String semanticsLabel;

  /// Semantics value, for example "35 persen". Not updated while [dragging].
  final String semanticsValue;

  /// Values announced after increase and decrease, required by Semantics when
  /// the actions are set. Not updated while [dragging].
  final String semanticsIncreasedValue;
  final String semanticsDecreasedValue;

  final VoidCallback? onIncrease;
  final VoidCallback? onDecrease;

  /// Called when the drag crosses a multiple of 5 (not at 0 or 100).
  final ValueChanged<int> onDetent;

  /// Called when the drag reaches 0 or 100 from another level.
  final VoidCallback onLimit;

  @override
  State<VolumeSlider> createState() => _VolumeSliderState();
}

enum _Gesture { idle, pending, dragging, ignored }

final class _VolumeSliderState extends State<VolumeSlider> {
  _Gesture _gesture = _Gesture.idle;
  int? _pointer;
  double _downX = 0;
  double _downY = 0;
  int _downLevel = 0;
  int _lastLevel = 0;
  double _width = 0;
  late String _announced = widget.semanticsValue;
  late String _increased = widget.semanticsIncreasedValue;
  late String _decreased = widget.semanticsDecreasedValue;

  @override
  void didUpdateWidget(VolumeSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && _gesture != _Gesture.idle) {
      final wasDragging = _gesture == _Gesture.dragging;
      _reset();
      if (wasDragging) {
        // Parent may be building now; notify after the frame.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) widget.onCancel();
        });
      }
    }
  }

  void _reset() {
    _gesture = _Gesture.idle;
    _pointer = null;
  }

  void _onDown(PointerDownEvent event) {
    if (!widget.enabled || _gesture != _Gesture.idle) return;
    _pointer = event.pointer;
    _downX = event.localPosition.dx;
    _downY = event.localPosition.dy;
    _downLevel = levelFromDx(_downX, _width);
    _gesture = _Gesture.pending;
  }

  void _onMove(PointerMoveEvent event) {
    if (event.pointer != _pointer) return;
    final dx = event.localPosition.dx - _downX;
    final dy = event.localPosition.dy - _downY;
    switch (_gesture) {
      case _Gesture.pending:
        if (dx.abs() < kTouchSlop && dy.abs() < kTouchSlop) return;
        if (dy.abs() > dx.abs()) {
          _gesture = _Gesture.ignored;
          return;
        }
        _gesture = _Gesture.dragging;
        _lastLevel = _downLevel;
        widget.onChangeStart(_downLevel);
        _moveTo(event.localPosition.dx);
      case _Gesture.dragging:
        _moveTo(event.localPosition.dx);
      case _Gesture.idle:
      case _Gesture.ignored:
        break;
    }
  }

  void _onUp(PointerUpEvent event) {
    if (event.pointer != _pointer) return;
    switch (_gesture) {
      case _Gesture.pending:
        // Tap: jump to the position without haptics (backlog: tap jump).
        final level = levelFromDx(event.localPosition.dx, _width);
        widget.onChangeStart(level);
        _lastLevel = level;
        widget.onChanged(level);
        widget.onChangeEnd(level);
      case _Gesture.dragging:
        _moveTo(event.localPosition.dx);
        widget.onChangeEnd(_lastLevel);
      case _Gesture.idle:
      case _Gesture.ignored:
        break;
    }
    _reset();
  }

  void _onCancel(PointerCancelEvent event) {
    if (event.pointer != _pointer) return;
    final wasDragging = _gesture == _Gesture.dragging;
    _reset();
    if (wasDragging) widget.onCancel();
  }

  void _moveTo(double dx) {
    final level = levelFromDx(dx, _width);
    if (level == _lastLevel) return;
    final previous = _lastLevel;
    _lastLevel = level;
    widget.onChanged(level);
    if (level == _minLevel || level == _maxLevel) {
      widget.onLimit();
    } else if (_crossesDetent(previous, level)) {
      widget.onDetent(level);
    }
  }

  static bool _crossesDetent(int a, int b) {
    final low = a < b ? a : b;
    final high = a < b ? b : a;
    return high ~/ _detentStep > low ~/ _detentStep;
  }

  @override
  Widget build(BuildContext context) {
    final control = context.control;
    final glass = context.glass;
    if (!widget.dragging) {
      _announced = widget.semanticsValue;
      _increased = widget.semanticsIncreasedValue;
      _decreased = widget.semanticsDecreasedValue;
    }
    final fillColor = (widget.muted || !widget.enabled)
        ? control.fgDisabled
        : control.sliderFill;
    final handleColor = Theme.of(context).colorScheme.surface;
    final trackHeight = widget.dragging ? RSize.trackActive : RSize.track;
    // Animate outside-driven changes (rollback, poll sync) only; never while
    // the user drags.
    final fillDuration = widget.dragging ? Duration.zero : RMotion.fast;

    return Semantics(
      slider: true,
      enabled: widget.enabled,
      label: widget.semanticsLabel,
      value: _announced,
      increasedValue: _increased,
      decreasedValue: _decreased,
      onIncrease: widget.enabled ? widget.onIncrease : null,
      onDecrease: widget.enabled ? widget.onDecrease : null,
      child: SizedBox(
        // Fixed at the dragging height so the layout does not jump.
        height: RSize.trackActive,
        child: LayoutBuilder(
          builder: (context, constraints) {
            _width = constraints.maxWidth;
            return Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: _onDown,
              onPointerMove: _onMove,
              onPointerUp: _onUp,
              onPointerCancel: _onCancel,
              child: Center(
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(end: widget.value / _maxLevel),
                  duration: fillDuration,
                  curve: RMotion.standard,
                  builder: (context, fraction, _) => _Track(
                    key: const ValueKey('volume-slider-track'),
                    height: trackHeight,
                    width: _width,
                    fraction: fraction,
                    fillColor: fillColor,
                    trackColor: control.sliderTrack,
                    insetColor: glass.lowlight,
                    handleColor: handleColor,
                    handleVisible: widget.value > _handleHideAtOrBelow,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Visual track: capsule, fill up to [fraction], and handle. Excluded from
/// Semantics; the slider above carries the label and value.
final class _Track extends StatelessWidget {
  const _Track({
    super.key,
    required this.height,
    required this.width,
    required this.fraction,
    required this.fillColor,
    required this.trackColor,
    required this.insetColor,
    required this.handleColor,
    required this.handleVisible,
  });

  final double height;
  final double width;
  final double fraction;
  final Color fillColor;
  final Color trackColor;
  final Color insetColor;
  final Color handleColor;
  final bool handleVisible;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(RRadius.full);
    final fillEdge = fraction * width;

    return ExcludeSemantics(
      child: Container(
        height: height,
        decoration: BoxDecoration(color: trackColor, borderRadius: radius),
        foregroundDecoration: BoxDecoration(
          borderRadius: radius,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [insetColor, insetColor.withValues(alpha: 0)],
            stops: const [0, _insetShadowStop],
          ),
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: fillEdge,
                child: ColoredBox(color: fillColor),
              ),
              Positioned(
                left: fillEdge - _handleLeftOffset,
                top: (height - _handleHeight) / 2,
                width: _handleWidth,
                height: _handleHeight,
                child: Opacity(
                  key: const ValueKey('volume-slider-handle'),
                  opacity: handleVisible ? 1 : 0,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: handleColor,
                      borderRadius: BorderRadius.circular(_handleWidth),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
