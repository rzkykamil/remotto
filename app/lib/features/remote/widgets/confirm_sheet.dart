import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/haptics/r_haptics.dart';
import '../../../core/strings/power_strings.dart';
import '../../../core/theme/glass_mode.dart';
import '../../../core/theme/reduced_motion.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../core/theme/tokens.g.dart';
import '../../../ui/hold_to_confirm.dart';
import '../../../ui/pressable.dart';
import '../../../ui/r_icon.dart';
import '../../../ui/r_icons_data.dart';
import '../data/power_repository.dart';

/// Bottom padding under the actions (artboard P01, 28 dp). Not a token.
const double _bottomPadding = 28;

/// Handle bar 40 x 5 dp, radius 3, opacity 0.4 (artboard P01). Not tokens.
const double _handleWidth = 40;
const double _handleHeight = 5;
const double _handleRadius = 3;
const double _handleAlpha = 0.4;

/// Icon inside the badge (artboard P01, 26 dp). Not a token.
const double _iconSize = 26;

/// Outline width of the stage 1 danger button (artboard P02, 1.5 dp).
const double _outlineWidth = 1.5;

/// Sheet shadow (artboard P01: `0 -20px 60px`). Not a token.
const Offset _shadowOffset = Offset(0, -20);
const double _shadowBlur = 60;

/// Downward fling speed (dp/s) that dismisses the sheet from the handle. Not
/// a token.
const double _dismissVelocity = 300;

/// Stage 1 "Lanjut" and the sleep action share the 56 dp control height.
const double _primaryHeight = RSize.control;

/// "Nggak jadi" is the largest action and sits closest to the thumb.
const double _cancelHeight = RSize.action;

/// Which step of a shutdown or restart is showing. Sleep has only [one].
enum _Stage { one, two }

/// Confirmation sheet for `sleep`, `restart`, and `shutdown`
/// (`design/components.md` C11, artboards P01, P02, P03, P06).
///
/// Sleep is a single step with "Sleep-in". Restart and shutdown start at
/// stage 1 ("Lanjut" in a red outline). Stage 2 replaces it with
/// [HoldToConfirm] and turns the icon and action red. The crossfade keeps the
/// same sheet.
///
/// The sheet only reports the outcome: [onConfirmed] when the user finishes
/// the action, [onCancel] for "Nggak jadi", and for the drag handle. Scrim
/// taps and the system back button are handled by the route in
/// `confirm_sheet_route.dart`. The sheet itself does not pop.
final class ConfirmSheet extends ConsumerStatefulWidget {
  const ConfirmSheet({
    super.key,
    required this.action,
    required this.laptopName,
    required this.onConfirmed,
    required this.onCancel,
    this.startAtStage2 = false,
  });

  final PowerAction action;

  /// Name from `/status`, used in the copy.
  final String laptopName;

  /// Called once the action is confirmed (sleep button or completed hold).
  final VoidCallback onConfirmed;

  /// Called for "Nggak jadi" and for a downward swipe on the handle.
  final VoidCallback onCancel;

  /// Opens shutdown or restart directly at stage 2. Ignored for sleep.
  final bool startAtStage2;

  @override
  ConsumerState<ConfirmSheet> createState() => _ConfirmSheetState();
}

final class _ConfirmSheetState extends ConsumerState<ConfirmSheet> {
  late _Stage _stage;
  final FocusNode _titleFocus = FocusNode(debugLabel: 'confirm sheet title');

  bool get _hasTwoStages => widget.action != PowerAction.sleep;

  @override
  void initState() {
    super.initState();
    _stage = widget.startAtStage2 && _hasTwoStages ? _Stage.two : _Stage.one;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(hapticsProvider).press();
      _focusTitle();
    });
  }

  @override
  void dispose() {
    _titleFocus.dispose();
    super.dispose();
  }

  /// Moves focus to the title so a screen reader starts on the question.
  void _focusTitle() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _titleFocus.requestFocus();
    });
  }

  void _advanceToStage2() {
    setState(() => _stage = _Stage.two);
    _focusTitle();
  }

  void _handleDragEnd(DragEndDetails details) {
    if ((details.primaryVelocity ?? 0) > _dismissVelocity) {
      widget.onCancel();
    }
  }

  @override
  Widget build(BuildContext context) {
    final solid = GlassMode.isSolid(context, ref);
    final reduced = ReducedMotion.of(context);

    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: _title(widget.action, _stage),
      child: Listener(
        // Absorbs taps on the sheet so they do not reach the scrim.
        behavior: HitTestBehavior.opaque,
        child: _surface(
          context,
          solid: solid,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _handle(context),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(
                    RSpace.s6,
                    0,
                    RSpace.s6,
                    _bottomPadding,
                  ),
                  child: AnimatedSwitcher(
                    duration: reduced.duration(RMotion.status),
                    switchInCurve: reduced.curve(RMotion.standard),
                    switchOutCurve: reduced.curve(RMotion.accelerate),
                    child: _stageContent(context, key: ValueKey(_stage)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Drag handle, also the swipe-down target. The area is 48 dp tall.
  Widget _handle(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragEnd: _handleDragEnd,
      child: SizedBox(
        width: double.infinity,
        height: RSize.touchMin,
        child: Center(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.onSurfaceVariant
                  .withValues(alpha: _handleAlpha),
              borderRadius: BorderRadius.circular(_handleRadius),
            ),
            child: const SizedBox(width: _handleWidth, height: _handleHeight),
          ),
        ),
      ),
    );
  }

  /// Glass sheet: one blur layer, solid fallback when [solid] is true.
  Widget _surface(
    BuildContext context, {
    required bool solid,
    required Widget child,
  }) {
    final glass = context.glass;
    final radius = BorderRadius.circular(RRadius.xl);

    Widget body = DecoratedBox(
      decoration: BoxDecoration(
        color: solid ? glass.solid : glass.sheet,
        borderRadius: radius,
        border: Border.all(
          color: glass.edge,
          width: RComponent.glassPanelEdgeWidth,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: RComponent.glassPanelEdgeWidth,
            child: ColoredBox(color: glass.highlight),
          ),
          child,
        ],
      ),
    );

    if (!solid) {
      body = BackdropFilter(
        filter: ImageFilter.blur(sigmaX: RBlur.sheet, sigmaY: RBlur.sheet),
        child: body,
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: glass.shadow,
            offset: _shadowOffset,
            blurRadius: _shadowBlur,
          ),
        ],
      ),
      child: ClipRRect(borderRadius: radius, child: body),
    );
  }

  /// Content of one stage. The [key] lets [AnimatedSwitcher] crossfade.
  Widget _stageContent(BuildContext context, {required Key key}) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = context.status;
    final action = widget.action;
    final stage = _stage;
    final danger = action != PowerAction.sleep && stage == _Stage.two;

    final badgeFill = danger ? status.dangerSoft : context.glass.chip;
    final badgeIcon = danger ? status.dangerText : scheme.onSurface;

    return Column(
      key: key,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              width: RSize.control,
              height: RSize.control,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: badgeFill,
                shape: BoxShape.circle,
              ),
              child: RIcon(_icon(action), size: _iconSize, color: badgeIcon),
            ),
            Text(
              _kicker(action, stage),
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: RSpace.s5),
        Focus(
          focusNode: _titleFocus,
          child: Semantics(
            header: true,
            child: Text(
              _title(action, stage),
              style: theme.textTheme.titleLarge?.copyWith(
                color: scheme.onSurface,
              ),
            ),
          ),
        ),
        const SizedBox(height: RSpace.s2),
        Text(
          _body(action, stage, widget.laptopName),
          style: theme.textTheme.bodyLarge?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: RSpace.s4),
        ..._actions(context),
      ],
    );
  }

  List<Widget> _actions(BuildContext context) {
    final action = widget.action;
    final cancel = _SheetButton(
      label: PowerStrings.cancelAction,
      tone: _Tone.neutral,
      height: _cancelHeight,
      onPressed: widget.onCancel,
    );

    if (action == PowerAction.sleep) {
      return [
        _SheetButton(
          label: PowerStrings.sleepAction,
          tone: _Tone.strong,
          height: _primaryHeight,
          onPressed: widget.onConfirmed,
        ),
        const SizedBox(height: RSpace.s3),
        cancel,
      ];
    }

    if (_stage == _Stage.one) {
      return [
        _SheetButton(
          label: PowerStrings.stage1Action,
          tone: _Tone.dangerOutline,
          height: _primaryHeight,
          onPressed: _advanceToStage2,
        ),
        const SizedBox(height: RSpace.s3),
        cancel,
      ];
    }

    return [
      HoldToConfirm(
        label: _holdLabel(action),
        icon: _icon(action),
        idleHint: PowerStrings.holdIdleHint,
        holdingHint: PowerStrings.holdingHint,
        releasedHint: PowerStrings.holdReleasedHint,
        semanticsLabel: _holdLabel(action),
        semanticsHint: PowerStrings.holdSemanticsHint,
        customActionLabel: action == PowerAction.restart
            ? PowerStrings.holdNowRestart
            : PowerStrings.holdNowShutdown,
        onCompleted: widget.onConfirmed,
      ),
      const SizedBox(height: RSpace.s3),
      cancel,
    ];
  }

  static String _kicker(PowerAction action, _Stage stage) => switch (action) {
    PowerAction.sleep => PowerStrings.sleepKicker,
    _ =>
      stage == _Stage.one
          ? PowerStrings.stage1Kicker
          : PowerStrings.stage2Kicker,
  };

  static String _title(PowerAction action, _Stage stage) => switch (action) {
    PowerAction.sleep => PowerStrings.sleepTitle,
    PowerAction.shutdown =>
      stage == _Stage.one
          ? PowerStrings.shutdownStage1Title
          : PowerStrings.shutdownHoldTitle,
    PowerAction.restart =>
      stage == _Stage.one
          ? PowerStrings.restartStage1Title
          : PowerStrings.restartHoldTitle,
  };

  static String _body(PowerAction action, _Stage stage, String laptopName) =>
      switch (action) {
        PowerAction.sleep => PowerStrings.sleepBody(laptopName),
        PowerAction.shutdown =>
          stage == _Stage.one
              ? PowerStrings.stage1Body(laptopName)
              : PowerStrings.shutdownHoldBody,
        PowerAction.restart =>
          stage == _Stage.one
              ? PowerStrings.stage1Body(laptopName)
              : PowerStrings.restartHoldBody,
      };

  static String _holdLabel(PowerAction action) => switch (action) {
    PowerAction.restart => PowerStrings.restartHoldLabel,
    _ => PowerStrings.shutdownHoldLabel,
  };

  static RIconData _icon(PowerAction action) => switch (action) {
    PowerAction.sleep => RIcons.moon,
    PowerAction.shutdown => RIcons.power,
    PowerAction.restart => RIcons.restart,
  };
}

/// Visual tone of a [_SheetButton] (artboard P01-P03).
enum _Tone {
  /// Sleep: fill `fg.primary`, text on the background (`.key.strong`).
  strong,

  /// Stage 1 "Lanjut": transparent, 1.5 dp `status.dangerText` outline.
  dangerOutline,

  /// "Nggak jadi": chip fill with a 1 dp edge.
  neutral,
}

/// Full-width capsule button for the sheet. Built on [Pressable] for press,
/// haptic, focus ring, and Semantics. It is not [GlassKey], which does not
/// stretch to the full width the artboard needs.
final class _SheetButton extends StatelessWidget {
  const _SheetButton({
    required this.label,
    required this.tone,
    required this.height,
    required this.onPressed,
  });

  final String label;
  final _Tone tone;
  final double height;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = context.status;
    final glass = context.glass;
    final style = Theme.of(context).textTheme.labelLarge ?? const TextStyle();

    final (fill, edge, edgeWidth, text) = switch (tone) {
      _Tone.strong => (scheme.onSurface, null, 0.0, scheme.surface),
      _Tone.dangerOutline => (
        Colors.transparent,
        status.dangerText,
        _outlineWidth,
        status.dangerText,
      ),
      _Tone.neutral => (
        glass.chip,
        glass.edge,
        RComponent.glassPanelEdgeWidth,
        scheme.onSurface,
      ),
    };

    return Pressable(
      semanticsLabel: label,
      onPressed: onPressed,
      builder: (context, pressed) => SizedBox(
        width: double.infinity,
        child: Container(
          constraints: BoxConstraints(minHeight: height),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: RSpace.s5),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(RRadius.full),
            border: edge == null
                ? null
                : Border.all(color: edge, width: edgeWidth),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: style.copyWith(color: text),
          ),
        ),
      ),
    );
  }
}
