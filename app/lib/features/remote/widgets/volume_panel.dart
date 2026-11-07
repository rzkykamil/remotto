import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:remotto/core/connection/connection_state.dart';
import 'package:remotto/core/strings/remote_strings.dart';
import 'package:remotto/core/theme/theme_extensions.dart';
import 'package:remotto/core/theme/tokens.g.dart';
import 'package:remotto/features/remote/state/volume_controller.dart';
import 'package:remotto/features/remote/state/volume_providers.dart';
import 'package:remotto/features/remote/widgets/offline_content.dart';
import 'package:remotto/ui/glass_key.dart';
import 'package:remotto/ui/r_icon.dart';
import 'package:remotto/ui/r_icons_data.dart';
import 'package:remotto/ui/volume_readout.dart';
import 'package:remotto/ui/volume_slider.dart';

/// Below this height the hint hides and the number shrinks (C10).
/// Not a token; the 700 dp threshold is to be checked on a real phone.
const double _shortHeight = 700;

/// Height of the title row, the minimum of the artboard row (`States-light`).
const double _titleRowHeight = 28;

/// Artboard-only sizes of the volume panel (`States-light.dc.html`). No token;
/// listed in the backlog (frontend, M3).
const double _badgeHeight = 28;
const double _badgePadding = 10;
const double _badgeGap = 6;
const double _badgeIconSize = 14;
const double _muteIconSize = 20;
const double _stepIconSize = 22;
const double _stepKeyWidth = 72;
const double _keyGap = 10;

/// Stroke of the badge icon in viewBox units (artboard 2.2).
const double _badgeStroke = 2.2;

/// Step of the −/+ keys, and of the Semantics increase and decrease values.
const int _step = RComponent.volumeSliderButtonStep;

/// Volume panel content (`design/components.md` C04, C05, C10, C08). Sits
/// inside the single [GlassPanel] of the screen, which provides the glass and
/// the "Volume" group label.
///
/// Panel layout: title row (VOLUME, BISU badge when muted), the middle area
/// (readout, or [OfflineContent] when the laptop is out of reach), slider, and
/// the row of mute, − and +. The panel only maps [VolumeState] to widgets;
/// commands go to [volumeControllerProvider].
final class VolumePanel extends ConsumerWidget {
  const VolumePanel({
    super.key,
    required this.phase,
    required this.onRetry,
    required this.onRepair,
    this.retrying = false,
    this.compact = false,
  });

  /// Connection phase of the screen. Online or back enables the controls.
  final ConnectionPhase phase;

  /// "Coba lagi" in the offline content.
  final VoidCallback onRetry;

  /// "Pairing ulang" in the offline content.
  final VoidCallback onRepair;

  /// True while a manual poll runs ("Nyoba…").
  final bool retrying;

  /// 360 dp wide layout: 108 sp number.
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(volumeControllerProvider);
    final controller = ref.read(volumeControllerProvider.notifier);
    final scheme = Theme.of(context).colorScheme;
    final control = context.control;

    final online =
        phase == ConnectionPhase.online || phase == ConnectionPhase.back;
    final enabled = online && state.known;
    final short = MediaQuery.sizeOf(context).height < _shortHeight;
    final offline =
        phase == ConnectionPhase.offline || phase == ConnectionPhase.poweredOff;
    final level = state.level;

    final tone = state.dragging
        ? VolumeReadoutTone.dragging
        : (state.muted || !enabled)
        ? VolumeReadoutTone.dim
        : VolumeReadoutTone.normal;

    // The hint is not shown on a short screen (C10).
    final hint = short ? null : _hint(state, phase);

    final muted = state.muted;
    final muteText = muted
        ? RemoteStrings.unmuteLabel
        : RemoteStrings.muteLabel;
    final muteIcon = muted ? RIcons.volumeOn : RIcons.volumeOff;
    final mutedColor = enabled ? scheme.onSurface : control.fgDisabled;

    final known = state.known;
    final valueText = known
        ? RemoteStrings.volumeValueA11y(level)
        : RemoteStrings.volumeUnknownA11y;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TitleRow(muted: muted),
        Expanded(
          child: offline
              // Offline content is taller than the readout. At large text
              // scales it scrolls instead of overflowing the fixed panel.
              ? _CenteredScroll(
                  child: OfflineContent(
                    onRetry: onRetry,
                    onRepair: onRepair,
                    retrying: retrying,
                    poweredOff: phase == ConnectionPhase.poweredOff,
                  ),
                )
              : Center(
                  child: VolumeReadout(
                    value: known ? level : null,
                    hint: hint,
                    tone: tone,
                    compact: compact,
                    short: short,
                  ),
                ),
        ),
        const SizedBox(height: RSpace.s4),
        VolumeSlider(
          value: level,
          muted: muted,
          enabled: enabled,
          dragging: state.dragging,
          onChanged: controller.dragUpdate,
          onChangeStart: controller.dragStart,
          onChangeEnd: controller.dragEnd,
          onCancel: controller.dragCancel,
          semanticsLabel: RemoteStrings.volumeGroupLabel,
          semanticsValue: valueText,
          semanticsIncreasedValue: known
              ? RemoteStrings.volumeValueA11y((level + _step).clamp(0, 100))
              : valueText,
          semanticsDecreasedValue: known
              ? RemoteStrings.volumeValueA11y((level - _step).clamp(0, 100))
              : valueText,
          onIncrease: controller.up,
          onDecrease: controller.down,
          // Haptics for detents and limits are fired by the controller
          // while the value changes, so the slider needs no action here.
          onDetent: (_) {},
          onLimit: () {},
        ),
        const SizedBox(height: RSpace.s4),
        Row(
          children: [
            Expanded(
              child: GlassKey(
                variant: GlassKeyVariant.chip,
                size: GlassKeySize.control,
                toggled: muted,
                semanticsLabel: muteText,
                label: muteText,
                icon: RIcon(muteIcon, size: _muteIconSize, color: mutedColor),
                onPressed: enabled ? controller.toggleMute : null,
              ),
            ),
            const SizedBox(width: _keyGap),
            SizedBox(
              width: _stepKeyWidth,
              child: GlassKey(
                variant: GlassKeyVariant.chip,
                size: GlassKeySize.control,
                semanticsLabel: RemoteStrings.volumeDownLabel,
                icon: RIcon(
                  RIcons.minus,
                  size: _stepIconSize,
                  color: enabled && level > 0
                      ? scheme.onSurface
                      : control.fgDisabled,
                  strokeWidth: 2.4,
                ),
                onPressed: enabled && level > 0 ? controller.down : null,
              ),
            ),
            const SizedBox(width: _keyGap),
            SizedBox(
              width: _stepKeyWidth,
              child: GlassKey(
                variant: GlassKeyVariant.chip,
                size: GlassKeySize.control,
                semanticsLabel: RemoteStrings.volumeUpLabel,
                icon: RIcon(
                  RIcons.plus,
                  size: _stepIconSize,
                  color: enabled && level < 100
                      ? scheme.onSurface
                      : control.fgDisabled,
                  strokeWidth: 2.4,
                ),
                onPressed: enabled && level < 100 ? controller.up : null,
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Hint by priority (C05): connecting or unknown, muted, dragging, minimum,
  /// maximum, idle. Connecting or unknown shows the waiting hint, because the
  /// level is not valid yet.
  String _hint(VolumeState state, ConnectionPhase phase) {
    if (phase == ConnectionPhase.connecting || !state.known) {
      return RemoteStrings.hintWaiting;
    }
    if (state.muted) return RemoteStrings.hintMuted;
    if (state.dragging) return RemoteStrings.hintDragging;
    if (state.level == 0) return RemoteStrings.hintMin;
    if (state.level == 100) return RemoteStrings.hintMax;
    return RemoteStrings.hintIdle;
  }
}

/// Centers [child] in the space it is given, and scrolls when it does not fit.
final class _CenteredScroll extends StatelessWidget {
  const _CenteredScroll({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(child: child),
        ),
      ),
    );
  }
}

/// Title row: VOLUME, and the BISU badge while muted. Excluded from
/// Semantics: the group label and the mute toggle carry the same meaning.
final class _TitleRow extends StatelessWidget {
  const _TitleRow({required this.muted});

  final bool muted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final labelStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
      fontFamily: RFont.mono,
      fontWeight: FontWeight.w500,
      color: scheme.onSurfaceVariant,
    );

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: _titleRowHeight),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ExcludeSemantics(
            child: Text(RemoteStrings.volumeLabel, style: labelStyle),
          ),
          if (muted) const ExcludeSemantics(child: _MutedBadge()),
        ],
      ),
    );
  }
}

/// Capsule chip "BISU" with the muted icon (artboard: 28 dp high, chip fill,
/// glass edge).
final class _MutedBadge extends StatelessWidget {
  const _MutedBadge();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final glass = context.glass;
    final text = Theme.of(context).textTheme.labelSmall?.copyWith(
      fontFamily: RFont.mono,
      fontWeight: FontWeight.w600,
      color: scheme.onSurface,
    );

    return Container(
      height: _badgeHeight,
      padding: const EdgeInsets.symmetric(horizontal: _badgePadding),
      decoration: BoxDecoration(
        color: glass.chip,
        borderRadius: BorderRadius.circular(RRadius.full),
        border: Border.all(
          color: glass.edge,
          width: RComponent.glassPanelEdgeWidth,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          RIcon(
            RIcons.volumeOff,
            size: _badgeIconSize,
            color: scheme.onSurface,
            strokeWidth: _badgeStroke,
          ),
          const SizedBox(width: _badgeGap),
          Text(RemoteStrings.mutedBadge, style: text),
        ],
      ),
    );
  }
}
