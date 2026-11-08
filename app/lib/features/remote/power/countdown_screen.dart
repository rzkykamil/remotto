import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/connection/connection_providers.dart';
import '../../../core/storage/storage_providers.dart';
import '../../../core/strings/power_strings.dart';
import '../../../core/theme/reduced_motion.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../core/theme/tokens.g.dart';
import '../../../ui/pressable.dart';
import '../../../ui/r_icon.dart';
import '../../../ui/r_icons_data.dart';
import '../data/power_repository.dart';
import 'power_flow_controller.dart';
import 'power_flow_state.dart';
import 'power_providers.dart';
import 'wakelock_controller.dart';

// Not tokens. Values come from the artboards (`design/export/artboards/`,
// Power-light P07, P11, P12, P13).

/// Background of the full-screen overlay: artboard `countBg` (bg at 0.94).
const double _backgroundAlpha = 0.94;

/// Top and bottom page padding (artboard 72 and 36 dp, minus the safe area).
const double _pageTop = RSpace.s8;
const double _pageBottom = RSpace.s6;

/// Gap between the stacked blocks (artboard flex gap 24 dp).
const double _gap = RSpace.s6;

/// Warning banner in P11 (artboard: radius 20, padding 14 x 16, border 1.5).
const double _bannerRadius = 20;
const double _bannerPaddingY = 14;
const double _bannerBorder = 1.5;

/// Alert icon in the P11 banner (artboard: 20 dp).
const double _bannerIconSize = 20;

/// Reduced-motion segments (artboard P12): 40 x 8 dp, radius 4, gap 8 dp.
const double _segmentWidth = 40;
const double _segmentHeight = 8;
const double _segmentRadius = 4;
const double _segmentGap = RSpace.s2;

/// The number stays at most this large when the system text scale is above
/// it (`design/tokens.json` `displayCountdown`: textScaler maks 1.3).
const double _numberMaxTextScale = 1.3;

/// Seconds at which the time is announced again, after the first announce
/// (`design/components.md` C13: umumkan di awal, lalu di 3 dan 1).
const Set<int> _announceAt = {3, 1};

/// Cancel button: artboard `button.key.strong`, 20 px label.
const double _cancelLabelSize = 20;

/// Full-screen countdown (`design/components.md` C13, artboards P07, P11,
/// P12, P13).
///
/// Shows the countdown from [powerFlowControllerProvider]. Only the
/// `PowerFlowCounting` and `PowerFlowCancelling` states are drawn. Anything
/// else (idle, scheduling, result) renders nothing, so the navigation layer
/// (T10) decides what replaces it.
///
/// Back and the cancel button both call [PowerFlowController.cancel]. The
/// route never pops by itself.
final class CountdownScreen extends ConsumerStatefulWidget {
  const CountdownScreen({super.key});

  @override
  ConsumerState<CountdownScreen> createState() => _CountdownScreenState();
}

final class _CountdownScreenState extends ConsumerState<CountdownScreen> {
  late final WakelockController _wakelock;
  final FocusNode _cancelFocus = FocusNode(debugLabel: 'countdown cancel');

  @override
  void initState() {
    super.initState();
    // Read here, not in dispose, because `ref` cannot be used in dispose.
    _wakelock = ref.read(wakelockControllerProvider);
    unawaited(_wakelock.enable());

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final counting = _countingOf(ref.read(powerFlowControllerProvider));
      if (counting != null) {
        _announce(_timeMessage(counting), assertive: false);
      }
      if (_cancelFocus.context != null) _cancelFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    unawaited(_wakelock.disable());
    _cancelFocus.dispose();
    super.dispose();
  }

  // Announcements -------------------------------------------------------------

  /// Announces the remaining time at 3 and 1 seconds, and a failed cancel
  /// (P11) as assertive. Ticks that do not reach those values say nothing.
  void _onFlowChanged(PowerFlowState? previous, PowerFlowState next) {
    if (!mounted) return;
    final current = _countingOf(next);
    if (current == null) return;
    final before = _countingOf(previous);

    final failedNow =
        next is PowerFlowCounting &&
        next.cancelFailed &&
        !(previous is PowerFlowCounting && previous.cancelFailed);
    if (failedNow) {
      _announce(PowerStrings.countdownCancelWarning, assertive: true);
      return;
    }

    if (before?.remaining != current.remaining &&
        _announceAt.contains(current.remaining)) {
      _announce(_timeMessage(current), assertive: false);
    }
  }

  /// "Laptop mati dalam 3 detik" (C13 Semantics).
  static String _timeMessage(PowerFlowCounting counting) =>
      PowerStrings.countdownAnnounce(
        _title(counting.action),
        counting.remaining,
      );

  void _announce(String message, {required bool assertive}) {
    final view = View.of(context);
    final direction = Directionality.of(context);
    unawaited(
      SemanticsService.sendAnnouncement(
        view,
        message,
        direction,
        assertiveness: assertive
            ? Assertiveness.assertive
            : Assertiveness.polite,
      ),
    );
  }

  // Build ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    ref.listen<PowerFlowState>(powerFlowControllerProvider, _onFlowChanged);
    final state = ref.watch(powerFlowControllerProvider);
    final counting = _countingOf(state);
    if (counting == null) return const SizedBox.shrink();

    final connection = ref.watch(connectionControllerProvider);
    final pairing = ref.watch(pairingProvider);
    final laptopName = connection.status?.name ?? pairing?.laptopName ?? '';
    final cancelling = state is PowerFlowCancelling;
    final reduced = ReducedMotion.of(context).enabled;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final color = _ringColor(context, counting.action);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        unawaited(ref.read(powerFlowControllerProvider.notifier).cancel());
      },
      child: Semantics(
        scopesRoute: true,
        namesRoute: true,
        explicitChildNodes: true,
        role: SemanticsRole.alertDialog,
        label: _title(counting.action),
        child: ColoredBox(
          color: scheme.surface.withValues(alpha: _backgroundAlpha),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                RSize.screenMargin,
                _pageTop,
                RSize.screenMargin,
                _pageBottom,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    laptopName.toUpperCase(),
                    textAlign: TextAlign.center,
                    style: textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: _gap),
                  Text(
                    _title(counting.action),
                    textAlign: TextAlign.center,
                    style: textTheme.titleLarge?.copyWith(
                      color: scheme.onSurface,
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: reduced
                            ? _SegmentedCountdown(
                                remaining: counting.remaining,
                                total: counting.total,
                                color: color,
                                track: context.control.segTrack,
                              )
                            : _RingCountdown(
                                remaining: counting.remaining,
                                total: counting.total,
                                color: color,
                                track: context.control.segTrack,
                                inner: context.control.countdownInner,
                              ),
                      ),
                    ),
                  ),
                  if (counting.cancelFailed) ...[
                    const _WarningBanner(
                      message: PowerStrings.countdownCancelWarning,
                    ),
                    const SizedBox(height: _gap),
                  ],
                  Text(
                    counting.cancelFailed
                        ? PowerStrings.countdownFailedHint
                        : PowerStrings.countdownHint,
                    textAlign: TextAlign.center,
                    style: textTheme.bodyLarge?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  if (counting.since case final int since) ...[
                    const SizedBox(height: RSpace.s2),
                    Text(
                      PowerStrings.since(
                        since,
                        fromThisPhone: counting.fromThisPhone,
                      ),
                      textAlign: TextAlign.center,
                      style: textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: _gap),
                  Focus(
                    focusNode: _cancelFocus,
                    includeSemantics: false,
                    child: _CancelButton(
                      label: cancelling
                          ? PowerStrings.countdownCancelling
                          : counting.cancelFailed
                          ? PowerStrings.countdownCancelAgain
                          : PowerStrings.countdownCancel,
                      processing: cancelling,
                      onPressed: cancelling
                          ? null
                          : () => unawaited(
                              ref
                                  .read(powerFlowControllerProvider.notifier)
                                  .cancel(),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Helpers -------------------------------------------------------------------

  static PowerFlowCounting? _countingOf(PowerFlowState? state) {
    return switch (state) {
      PowerFlowCounting() => state,
      PowerFlowCancelling(:final counting) => counting,
      _ => null,
    };
  }

  static String _title(PowerAction action) => switch (action) {
    PowerAction.shutdown => PowerStrings.countdownTitleShutdown,
    PowerAction.restart => PowerStrings.countdownTitleRestart,
    PowerAction.sleep => PowerStrings.countdownTitleSleep,
  };

  /// Ring and segments: danger for restart and shutdown, accent for sleep
  /// (C13). Shutdown and restart use `status.dangerText`, the danger color
  /// that is readable on the glass surface (see the report for the gap).
  static Color _ringColor(BuildContext context, PowerAction action) {
    return action == PowerAction.sleep
        ? context.accent.text
        : context.status.dangerText;
  }
}

/// Ring with the number inside (P07, P11, P13). Drawn with [CustomPainter].
/// Shows the remaining share right away, with no animation from full.
final class _RingCountdown extends StatelessWidget {
  const _RingCountdown({
    required this.remaining,
    required this.total,
    required this.color,
    required this.track,
    required this.inner,
  });

  final int remaining;
  final int total;
  final Color color;
  final Color track;
  final Color inner;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: RSize.ring,
      height: RSize.ring,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: const Size.square(RSize.ring),
            painter: _RingPainter(
              fraction: _fraction(remaining, total),
              color: color,
              track: track,
              inner: inner,
              stroke: RComponent.countdownRingStroke,
            ),
          ),
          _Number(remaining: remaining, color: scheme.onSurface),
        ],
      ),
    );
  }
}

/// Reduced motion (P12): the number, then [total] segments. Lit segments
/// count [remaining] (artboard: 4 lit of 5 at 4 seconds left).
final class _SegmentedCountdown extends StatelessWidget {
  const _SegmentedCountdown({
    required this.remaining,
    required this.total,
    required this.color,
    required this.track,
  });

  final int remaining;
  final int total;
  final Color color;
  final Color track;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final segments = math.max(total, 0);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Number(remaining: remaining, color: scheme.onSurface),
        const SizedBox(height: _gap),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < segments; i++) ...[
              if (i > 0) const SizedBox(width: _segmentGap),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: i < remaining ? color : track,
                  borderRadius: BorderRadius.circular(_segmentRadius),
                ),
                child: const SizedBox(
                  width: _segmentWidth,
                  height: _segmentHeight,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// The number, `displayCountdown` (mono 120 sp). Its text scale is clamped
/// to [_numberMaxTextScale]. Readers get it from the Text itself.
final class _Number extends StatelessWidget {
  const _Number({required this.remaining, required this.color});

  final int remaining;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: _numberMaxTextScale,
      child: Text(
        '$remaining',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.displayMedium
            ?.copyWith(color: color),
      ),
    );
  }
}

/// P11 warning banner: danger-soft fill, danger border, alert icon.
final class _WarningBanner extends StatelessWidget {
  const _WarningBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = context.status;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: status.dangerSoft,
        borderRadius: BorderRadius.circular(_bannerRadius),
        border: Border.all(color: status.dangerText, width: _bannerBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: RSpace.s4,
          vertical: _bannerPaddingY,
        ),
        child: Row(
          children: [
            RIcon(
              RIcons.alertTriangle,
              size: _bannerIconSize,
              color: status.dangerText,
            ),
            const SizedBox(width: RSpace.s3),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodyLarge
                    ?.copyWith(color: scheme.onSurface),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Batal" (C13): full-width strong key, height `component.countdown.cancelHeight`
/// (80 dp, the thumb zone). Disabled while [processing].
final class _CancelButton extends StatelessWidget {
  const _CancelButton({
    required this.label,
    required this.processing,
    required this.onPressed,
  });

  final String label;
  final bool processing;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final control = context.control;
    final enabled = onPressed != null;
    final fill = enabled ? scheme.onSurface : control.fgDisabled;
    final text = Theme.of(context).textTheme.titleMedium
        ?.copyWith(color: scheme.surface, fontSize: _cancelLabelSize);

    return Pressable(
      semanticsLabel: label,
      semanticsHint: processing ? PowerStrings.countdownCancellingHint : null,
      onPressed: onPressed,
      builder: (context, pressed) => SizedBox(
        width: double.infinity,
        child: Container(
          height: RSize.cancel,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: RSpace.s5),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(RRadius.full),
          ),
          child: Text(label, textAlign: TextAlign.center, style: text),
        ),
      ),
    );
  }
}

/// Fraction of the ring that is still lit, 0 to 1.
double _fraction(int remaining, int total) {
  if (total <= 0) return 0;
  return (remaining / total).clamp(0.0, 1.0);
}

/// Draws the track, the remaining arc (clockwise from the top, like the
/// artboard's conic gradient), and the inner disc.
final class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.fraction,
    required this.color,
    required this.track,
    required this.inner,
    required this.stroke,
  });

  final double fraction;
  final Color color;
  final Color track;
  final Color inner;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - stroke / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = track;
    canvas.drawArc(rect, 0, math.pi * 2, false, trackPaint);

    if (fraction > 0) {
      final arcPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.butt
        ..color = color;
      canvas.drawArc(
        rect,
        -math.pi / 2,
        math.pi * 2 * fraction,
        false,
        arcPaint,
      );
    }

    canvas.drawCircle(center, size.width / 2 - stroke, Paint()..color = inner);
  }

  @override
  bool shouldRepaint(_RingPainter old) {
    return old.fraction != fraction ||
        old.color != color ||
        old.track != track ||
        old.inner != inner ||
        old.stroke != stroke;
  }
}
