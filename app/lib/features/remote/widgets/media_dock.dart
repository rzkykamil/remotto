import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:remotto/core/strings/remote_strings.dart';
import 'package:remotto/core/theme/r_behavior.dart';
import 'package:remotto/core/theme/reduced_motion.dart';
import 'package:remotto/core/theme/theme_extensions.dart';
import 'package:remotto/core/theme/tokens.g.dart';
import 'package:remotto/features/remote/state/media_providers.dart';
import 'package:remotto/ui/glass_key.dart';
import 'package:remotto/ui/glass_panel.dart';
import 'package:remotto/ui/play_key.dart';
import 'package:remotto/ui/r_icon.dart';
import 'package:remotto/ui/r_icons_data.dart';

/// Glyph size of prev and next (`design/export/artboards/States-light.dc.html`,
/// svg 28). Not a design token.
const double _skipIconSize = 28;

/// Opacity at the dip of the prev/next blink (`design/components.md` C03).
/// Not a design token.
const double _blinkDimOpacity = 0.35;

/// Media dock of SCR-010 (`design/components.md` C01 dock, C03, C10):
/// prev, play/pause, next, on one glass capsule.
///
/// [enabled] false disables all three keys (connecting, offline, powered off,
/// token rejected). The state comes from [mediaControllerProvider].
final class MediaDock extends ConsumerWidget {
  const MediaDock({super.key, required this.enabled, this.compact = false});

  /// False disables every key and sends no command.
  final bool enabled;

  /// 360 dp layout: smaller keys.
  final bool compact;

  /// Full height of the dock: play key plus the dock padding on both sides.
  /// The screen uses it to lift toasts above the dock.
  static double heightFor(bool compact) =>
      (compact ? RSize.playCompact : RSize.play) + RSpace.s2 * 2;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final media = ref.watch(mediaControllerProvider);
    final controller = ref.read(mediaControllerProvider.notifier);
    final skipSize = compact ? GlassKeySize.mediaCompact : GlassKeySize.media;

    return GlassPanel(
      variant: GlassPanelVariant.dock,
      padding: const EdgeInsets.all(RSpace.s2),
      semanticsLabel: RemoteStrings.mediaGroupLabel,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          GlassKey(
            semanticsLabel: RemoteStrings.prevLabel,
            onPressed: enabled ? controller.prev : null,
            variant: GlassKeyVariant.ghost,
            size: skipSize,
            icon: _BlinkIcon(
              tick: media.blinkPrev,
              child: _skipIcon(context, RIcons.skipPrev),
            ),
          ),
          PlayKey(
            playing: media.playing,
            processing: media.playProcessing,
            ringVisible: media.ringVisible,
            compact: compact,
            semanticsLabel: media.playing
                ? RemoteStrings.pauseLabel
                : RemoteStrings.playLabel,
            processingHint: RemoteStrings.playSendingHint,
            onPressed: enabled ? controller.togglePlay : null,
          ),
          GlassKey(
            semanticsLabel: RemoteStrings.nextLabel,
            onPressed: enabled ? controller.next : null,
            variant: GlassKeyVariant.ghost,
            size: skipSize,
            icon: _BlinkIcon(
              tick: media.blinkNext,
              child: _skipIcon(context, RIcons.skipNext),
            ),
          ),
        ],
      ),
    );
  }

  /// Same colour rule as the ghost key: `fg` when enabled, `fg.disabled`
  /// otherwise.
  Widget _skipIcon(BuildContext context, RIconData data) {
    final color = enabled
        ? Theme.of(context).colorScheme.onSurface
        : context.control.fgDisabled;
    return RIcon(data, size: _skipIconSize, color: color, filled: true);
  }
}

/// Dips the icon once to [_blinkDimOpacity] and back, over
/// [RBehavior.prevNextBlink], each time [tick] changes. Reduced motion shows
/// the icon without any change.
final class _BlinkIcon extends StatefulWidget {
  const _BlinkIcon({required this.tick, required this.child});

  final int tick;
  final Widget child;

  @override
  State<_BlinkIcon> createState() => _BlinkIconState();
}

final class _BlinkIconState extends State<_BlinkIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: RBehavior.prevNextBlink,
  );

  late final Animation<double> _opacity = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(begin: 1.0, end: _blinkDimOpacity),
      weight: 1,
    ),
    TweenSequenceItem(
      tween: Tween(begin: _blinkDimOpacity, end: 1.0),
      weight: 1,
    ),
  ]).animate(_controller);

  bool _reduced = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = ReducedMotion.of(context).enabled;
    if (_reduced) _controller.stop();
  }

  @override
  void didUpdateWidget(_BlinkIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.tick != oldWidget.tick && !_reduced) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_reduced) return widget.child;
    return FadeTransition(opacity: _opacity, child: widget.child);
  }
}
