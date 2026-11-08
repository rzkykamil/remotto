import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/haptics/r_haptics.dart';
import '../../../core/strings/power_strings.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../core/theme/tokens.g.dart';
import '../../../ui/light_backdrop.dart';
import '../../../ui/pressable.dart';
import '../../../ui/r_icon.dart';
import '../../../ui/r_icons_data.dart';
import '../data/power_repository.dart';
import 'power_flow_state.dart';

/// Icon badge 80 dp (artboards P09, P10, P14). Not a token.
const double _badgeSize = 80;

/// Icon inside the badge, 36 dp (artboards P09, P10, P14). Not a token.
const double _iconSize = 36;

/// Space above the content (artboards P09-P14: 72 dp). Not a token.
const double _topPadding = 72;

/// Space below the actions (artboards P09-P14: 36 dp). Not a token.
const double _bottomPadding = 36;

/// Body max width: 300 dp for P09/P10, 310 dp for P14. Not tokens.
const double _bodyMaxWidth = 300;
const double _lateBodyMaxWidth = 310;

/// Neutral badge fill of P09 (`neutralIcon`, light 0.08, dark 0.10 of the
/// foreground). Applied to `onSurface`, which flips with the theme.
const double _neutralBadgeAlpha = 0.08;

/// Gap between the badge and the title (artboard P09: 16 dp).
const double _badgeGap = RSpace.s4;

/// Gap between the two actions on P10 (artboard 12 dp).
const double _actionGap = RSpace.s3;

/// Below this width the side gutter is 20 dp instead of 24 dp.
const double _compactWidth = 400;

/// Outcome screen of the power flow (`design/components.md` C14, artboards
/// P09, P10, P14). Replaces the countdown screen after the outcome is known.
///
/// Variants by [result]:
/// - [PowerSent] (P09): check badge, "Oke" back to the remote.
/// - [PowerNotScheduled] (P10): warning badge, "Coba lagi" and "Tutup".
/// - [PowerTooLate] (P14): check badge, "Oke", no cancel action (BR-19).
///
/// [PowerCancelled] is a toast, not a screen, so it is not accepted here.
///
/// The title is a Semantics header with live region and gets initial focus.
/// System back runs the primary action, or [onClose] for P10. The route
/// itself does not pop (`PopScope`), so the caller decides where to go.
final class ResultScreen extends ConsumerStatefulWidget {
  const ResultScreen({
    super.key,
    required this.result,
    required this.laptopName,
    required this.onPrimary,
    this.onClose,
  }) : assert(
         result is! PowerCancelled,
         'A cancelled schedule is shown as a toast, not a result screen.',
       ),
       assert(
         result is! PowerNotScheduled || onClose != null,
         'P10 needs onClose for its "Tutup" action.',
       );

  final PowerResult result;

  /// Name from `/status`, used in the copy.
  final String laptopName;

  /// Primary action: "Oke" (P09, P14) or "Coba lagi" (P10).
  final VoidCallback onPrimary;

  /// "Tutup" on P10. Also the system back action on P10.
  final VoidCallback? onClose;

  @override
  ConsumerState<ResultScreen> createState() => _ResultScreenState();
}

final class _ResultScreenState extends ConsumerState<ResultScreen> {
  final FocusNode _titleFocus = FocusNode(debugLabel: 'result screen title');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.result is PowerNotScheduled) {
        // P10 is a failed send: short vibrate (`design/design-system.md`).
        ref.read(hapticsProvider).failure();
      }
      _titleFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _titleFocus.dispose();
    super.dispose();
  }

  /// System back: "Tutup" on P10, the primary action on P09 and P14.
  void _onBack() {
    final isNotScheduled = widget.result is PowerNotScheduled;
    final callback = isNotScheduled ? widget.onClose : widget.onPrimary;
    callback?.call();
  }

  @override
  Widget build(BuildContext context) {
    final view = _ResultView.of(context, widget.result, widget.laptopName);
    final width = MediaQuery.sizeOf(context).width;
    final gutter = width < _compactWidth
        ? RSize.screenMarginCompact
        : RSize.screenMargin;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: LightBackdrop(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  gutter,
                  _topPadding,
                  gutter,
                  _bottomPadding,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight:
                        (constraints.maxHeight - _topPadding - _bottomPadding)
                            .clamp(0.0, double.infinity),
                  ),
                  child: IntrinsicHeight(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: Container(
                            width: _badgeSize,
                            height: _badgeSize,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: view.badgeFill,
                              shape: BoxShape.circle,
                              border: view.badgeEdge == null
                                  ? null
                                  : Border.all(
                                      color: view.badgeEdge!,
                                      width: RComponent.glassPanelEdgeWidth,
                                    ),
                            ),
                            child: RIcon(
                              view.icon,
                              size: _iconSize,
                              color: view.iconColor,
                            ),
                          ),
                        ),
                        const SizedBox(height: _badgeGap),
                        Semantics(
                          header: true,
                          liveRegion: true,
                          child: Focus(
                            focusNode: _titleFocus,
                            child: Text(
                              view.title,
                              textAlign: TextAlign.center,
                              style: textTheme.titleLarge?.copyWith(
                                color: scheme.onSurface,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: RSpace.s2),
                        Center(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: view.bodyMaxWidth,
                            ),
                            child: Text(
                              view.body,
                              textAlign: TextAlign.center,
                              style: textTheme.bodyLarge?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: RSpace.s6),
                        _ResultButton(
                          label: view.primaryLabel,
                          height: RSize.action,
                          strong: true,
                          onPressed: widget.onPrimary,
                        ),
                        if (view.showClose) ...[
                          const SizedBox(height: _actionGap),
                          _ResultButton(
                            label: PowerStrings.scheduleFailedClose,
                            height: RSize.control,
                            strong: false,
                            onPressed: widget.onClose,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Copy, icon, and colors of one variant. Built from the artboard's `d` object
/// and the copy in [PowerStrings].
final class _ResultView {
  const _ResultView({
    required this.title,
    required this.body,
    required this.bodyMaxWidth,
    required this.primaryLabel,
    required this.showClose,
    required this.icon,
    required this.iconColor,
    required this.badgeFill,
    required this.badgeEdge,
  });

  factory _ResultView.of(
    BuildContext context,
    PowerResult result,
    String laptopName,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final status = context.status;
    final glass = context.glass;

    return switch (result) {
      PowerSent(:final action) => _ResultView(
        title: _doneTitle(action),
        body: _doneBody(action, laptopName),
        bodyMaxWidth: _bodyMaxWidth,
        primaryLabel: PowerStrings.doneAction,
        showClose: false,
        icon: RIcons.check,
        iconColor: status.success,
        badgeFill: scheme.onSurface.withValues(alpha: _neutralBadgeAlpha),
        badgeEdge: null,
      ),
      PowerNotScheduled() => _ResultView(
        title: PowerStrings.scheduleFailedTitle,
        body: PowerStrings.scheduleFailedBody,
        bodyMaxWidth: _bodyMaxWidth,
        primaryLabel: PowerStrings.scheduleFailedRetry,
        showClose: true,
        icon: RIcons.alertTriangle,
        iconColor: status.dangerText,
        badgeFill: status.dangerSoft,
        badgeEdge: null,
      ),
      PowerTooLate(:final action, :final elapsed, :final fromThisPhone) =>
        _ResultView(
          title: PowerStrings.lateTitle,
          body: _lateBody(action, laptopName, elapsed, fromThisPhone),
          bodyMaxWidth: _lateBodyMaxWidth,
          primaryLabel: PowerStrings.lateAction,
          showClose: false,
          icon: RIcons.check,
          iconColor: status.success,
          badgeFill: glass.chip,
          badgeEdge: glass.edge,
        ),
      PowerCancelled() => throw ArgumentError.value(
        result,
        'result',
        'A cancelled schedule is shown as a toast.',
      ),
    };
  }

  final String title;
  final String body;
  final double bodyMaxWidth;
  final String primaryLabel;
  final bool showClose;
  final RIconData icon;
  final Color iconColor;
  final Color badgeFill;
  final Color? badgeEdge;

  static String _doneTitle(PowerAction action) => switch (action) {
    PowerAction.shutdown => PowerStrings.doneShutdownTitle,
    PowerAction.sleep => PowerStrings.doneSleepTitle,
    PowerAction.restart => PowerStrings.doneRestartTitle,
  };

  static String _doneBody(PowerAction action, String laptopName) =>
      switch (action) {
        PowerAction.shutdown => PowerStrings.doneShutdownBody(laptopName),
        PowerAction.sleep => PowerStrings.doneSleepBody(laptopName),
        PowerAction.restart => PowerStrings.doneRestartBody,
      };

  static String _lateBody(
    PowerAction action,
    String laptopName,
    int elapsed,
    bool fromThisPhone,
  ) => switch (action) {
    PowerAction.shutdown => PowerStrings.lateShutdownBody(
      laptopName,
      elapsed,
      fromThisPhone: fromThisPhone,
    ),
    PowerAction.restart => PowerStrings.lateRestartBody(
      laptopName,
      elapsed,
      fromThisPhone: fromThisPhone,
    ),
    PowerAction.sleep => PowerStrings.lateSleepBody(
      laptopName,
      elapsed,
      fromThisPhone: fromThisPhone,
    ),
  };
}

/// Full-width capsule for the result actions. Built on [Pressable] for press,
/// haptic, focus ring, and Semantics. [strong] is the primary action (fill
/// `onSurface`); otherwise it is the neutral chip with a 1 dp edge.
final class _ResultButton extends StatelessWidget {
  const _ResultButton({
    required this.label,
    required this.height,
    required this.strong,
    required this.onPressed,
  });

  final String label;
  final double height;
  final bool strong;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final glass = context.glass;
    final style = Theme.of(context).textTheme.labelLarge ?? const TextStyle();

    final fill = strong ? scheme.onSurface : glass.chip;
    final text = strong ? scheme.surface : scheme.onSurface;

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
            border: strong
                ? null
                : Border.all(
                    color: glass.edge,
                    width: RComponent.glassPanelEdgeWidth,
                  ),
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
