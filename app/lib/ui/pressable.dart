import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/haptics/r_haptics.dart';
import '../core/theme/reduced_motion.dart';
import '../core/theme/theme_extensions.dart';
import '../core/theme/tokens.g.dart';

/// Haptic yang dipicu saat jari turun. Pemetaan momen: `design/design-system.md`.
enum PressHaptic { none, light }

/// Focus ring C02: 3 dp `accent.text`. Sama dengan cincin PlayKey.
const double _focusRingWidth = RComponent.playKeyRingWidth;

/// Primitif tombol satu-satunya di app: press, haptic, focus, dan Semantics
/// lewat satu tempat (`docs/design-system.md` bagian 5). Tanpa ripple Material.
///
/// Tekan = skala [pressedScale] + haptic saat jari turun. Aksi dipicu saat
/// jari dilepas di dalam area; geser keluar = batal. Bila [onPressed] null,
/// tombol disabled: tanpa skala, tanpa haptic, Semantics `enabled: false`.
final class Pressable extends ConsumerStatefulWidget {
  const Pressable({
    super.key,
    required this.builder,
    required this.semanticsLabel,
    this.onPressed,
    this.semanticsHint,
    this.toggled,
    this.haptic = PressHaptic.light,
    this.pressedScale = RComponent.keyPressedScale,
    this.focusRingRadius = RRadius.full,
  });

  /// Konstruktor praktis untuk isi yang tidak bergantung pada state tekan.
  factory Pressable.child({
    Key? key,
    required Widget child,
    required String semanticsLabel,
    VoidCallback? onPressed,
    String? semanticsHint,
    bool? toggled,
    PressHaptic haptic = PressHaptic.light,
    double pressedScale = RComponent.keyPressedScale,
    double focusRingRadius = RRadius.full,
  }) => Pressable(
    key: key,
    builder: (_, _) => child,
    semanticsLabel: semanticsLabel,
    onPressed: onPressed,
    semanticsHint: semanticsHint,
    toggled: toggled,
    haptic: haptic,
    pressedScale: pressedScale,
    focusRingRadius: focusRingRadius,
  );

  /// Isi tombol. `pressed` true selama jari menekan tombol yang aktif.
  final Widget Function(BuildContext context, bool pressed) builder;
  final String semanticsLabel;

  /// Dipanggil saat jari dilepas di dalam area, atau saat Enter/Space.
  final VoidCallback? onPressed;
  final String? semanticsHint;

  /// Null untuk tombol biasa; true/false untuk tombol toggle.
  final bool? toggled;
  final PressHaptic haptic;
  final double pressedScale;
  final double focusRingRadius;

  @override
  ConsumerState<Pressable> createState() => _PressableState();
}

final class _PressableState extends ConsumerState<Pressable> {
  bool _pressed = false;
  bool _focused = false;

  bool get _enabled => widget.onPressed != null;

  void _setPressed(bool value) {
    if (_pressed != value) {
      setState(() => _pressed = value);
    }
  }

  void _handleTapDown(TapDownDetails details) {
    _setPressed(true);
    if (widget.haptic == PressHaptic.light) {
      ref.read(hapticsProvider).press();
    }
  }

  void _handleFocusHighlight({required bool value}) {
    if (_focused != value) {
      setState(() => _focused = value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = _enabled;
    final reduced = ReducedMotion.of(context);
    final pressed = _pressed && enabled;

    // Tekan turun dan lepas memakai durasi serta kurva yang berbeda.
    final content = AnimatedScale(
      scale: pressed ? reduced.pressedScale(widget.pressedScale) : 1.0,
      duration: reduced.duration(pressed ? RMotion.pressDown : RMotion.pressUp),
      curve: pressed
          ? reduced.curve(Curves.easeOut)
          : reduced.curve(RMotion.spring),
      child: widget.builder(context, pressed),
    );

    // Ring digambar di luar batas child agar tata letak tidak bergeser.
    final framed = Stack(
      clipBehavior: Clip.none,
      children: [
        content,
        if (_focused)
          Positioned(
            left: -_focusRingWidth,
            top: -_focusRingWidth,
            right: -_focusRingWidth,
            bottom: -_focusRingWidth,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: context.accent.text,
                    width: _focusRingWidth,
                  ),
                  borderRadius: BorderRadius.circular(widget.focusRingRadius),
                ),
              ),
            ),
          ),
      ],
    );

    final hitArea = ConstrainedBox(
      constraints: const BoxConstraints(
        minWidth: RSize.touchMin,
        minHeight: RSize.touchMin,
      ),
      child: Center(child: framed),
    );

    final gesture = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? _handleTapDown : null,
      onTapUp: enabled ? (_) => _setPressed(false) : null,
      onTapCancel: enabled ? () => _setPressed(false) : null,
      onTap: widget.onPressed,
      child: hitArea,
    );

    final semantics = Semantics(
      button: true,
      enabled: enabled,
      label: widget.semanticsLabel,
      hint: widget.semanticsHint,
      toggled: widget.toggled,
      onTap: widget.onPressed,
      excludeSemantics: true,
      child: gesture,
    );

    return FocusableActionDetector(
      enabled: enabled,
      onShowFocusHighlight: (value) => _handleFocusHighlight(value: value),
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<Intent>(
          onInvoke: (_) {
            widget.onPressed?.call();
            return null;
          },
        ),
      },
      child: semantics,
    );
  }
}
