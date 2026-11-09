import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/glass_mode.dart';
import '../core/theme/reduced_motion.dart';
import '../core/theme/theme_extensions.dart';
import '../core/theme/tokens.g.dart';
import 'pressable.dart';

/// Inset sheet dari tepi layar: 8 dp (`design/components.md` C22). Bukan
/// token; sama dengan `ConfirmSheet` (C11).
const double _sheetInset = RSpace.s2;

/// Padding sheet: atas 12, samping 24, bawah 28. Atas dan samping memakai
/// token; bawah 28 bukan token.
const double _paddingTop = RSpace.s3;
const double _paddingX = RSpace.s6;
const double _paddingBottom = 28;

/// Handle 40 x 5 dp, radius 3, opacity 0.4 (artboard R04). Bukan token.
const double _handleWidth = 40;
const double _handleHeight = 5;
const double _handleRadius = 3;
const double _handleAlpha = 0.4;

/// Judul 24/30 semibold memakai `titleXl` dengan bobot semibold; body 16/24
/// memakai `bodyLarge`.
const FontWeight _titleWeight = FontWeight.w600;

/// Jarak judul ke body dan body ke aksi (artboard R04: gap 20 dp). Bukan
/// token.
const double _sectionGap = RSpace.s5;

/// Jarak antar tombol aksi (artboard R04: 12 dp).
const double _actionGap = RSpace.s3;

/// Bayangan sheet (artboard: `0 -20px 60px`). Bukan token.
const Offset _shadowOffset = Offset(0, -20);
const double _shadowBlur = 60;

/// Kecepatan fling ke bawah (dp/s) yang menutup sheet dari handle. Bukan
/// token; sama dengan `ConfirmSheet`.
const double _dismissVelocity = 300;

/// Sheet konfirmasi satu tahap tanpa ikon dan tanpa tahan-konfirmasi
/// (`design/components.md` C22, artboard R04).
///
/// Aksi utama [confirmLabel] tampil sebagai `strong` dan paling atas. Aksi
/// [cancelLabel] tampil di bawah, paling besar, dan paling dekat jempol.
///
/// Widget ini hanya melapor. Tap scrim, back sistem, dan pop route diurus
/// [showSimpleConfirmSheet].
final class SimpleConfirmSheet extends ConsumerStatefulWidget {
  const SimpleConfirmSheet({
    super.key,
    required this.title,
    required this.body,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.onConfirm,
    required this.onCancel,
  });

  /// Judul; juga dipakai sebagai label route Semantics.
  final String title;
  final String body;
  final String confirmLabel;
  final String cancelLabel;
  final VoidCallback onConfirm;

  /// Dipanggil untuk [cancelLabel] dan untuk swipe ke bawah di handle.
  final VoidCallback onCancel;

  @override
  ConsumerState<SimpleConfirmSheet> createState() => _SimpleConfirmSheetState();
}

final class _SimpleConfirmSheetState extends ConsumerState<SimpleConfirmSheet> {
  final FocusNode _titleFocus = FocusNode(debugLabel: 'simple confirm title');

  @override
  void initState() {
    super.initState();
    // Fokus ke judul supaya screen reader mulai dari pertanyaan.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _titleFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _titleFocus.dispose();
    super.dispose();
  }

  void _handleDragEnd(DragEndDetails details) {
    if ((details.primaryVelocity ?? 0) > _dismissVelocity) {
      widget.onCancel();
    }
  }

  @override
  Widget build(BuildContext context) {
    final solid = GlassMode.isSolid(context, ref);

    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: widget.title,
      child: Listener(
        // Menyerap tap di sheet supaya tidak sampai ke scrim.
        behavior: HitTestBehavior.opaque,
        child: _surface(
          context,
          solid: solid,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _handle(),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  _paddingX,
                  0,
                  _paddingX,
                  _paddingBottom,
                ),
                child: _content(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Handle dan area tarik ke bawah. Area sentuh 48 dp, bar 40 x 5.
  Widget _handle() {
    return Padding(
      padding: const EdgeInsets.only(top: _paddingTop),
      child: GestureDetector(
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
      ),
    );
  }

  /// Permukaan kaca: satu lapis blur, fallback solid saat [solid].
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

    return Padding(
      padding: const EdgeInsets.all(_sheetInset),
      child: DecoratedBox(
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
      ),
    );
  }

  Widget _content(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Focus(
          focusNode: _titleFocus,
          child: Semantics(
            header: true,
            child: Text(
              widget.title,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: scheme.onSurface,
                fontWeight: _titleWeight,
              ),
            ),
          ),
        ),
        const SizedBox(height: RSpace.s2),
        Text(
          widget.body,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: _sectionGap),
        _SheetButton(
          label: widget.confirmLabel,
          tone: _Tone.strong,
          height: RSize.control,
          onPressed: widget.onConfirm,
        ),
        const SizedBox(height: _actionGap),
        _SheetButton(
          label: widget.cancelLabel,
          tone: _Tone.neutral,
          height: RSize.action,
          onPressed: widget.onCancel,
        ),
      ],
    );
  }
}

/// Nada tombol sheet. `strong` mengisi `fg.primary`; `neutral` memakai chip
/// kaca dengan tepi 1 dp.
enum _Tone { strong, neutral }

/// Tombol kapsul lebar penuh. Dibangun di atas [Pressable] untuk tekan,
/// haptic, fokus, dan Semantics.
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final glass = context.glass;
    final style = theme.textTheme.labelLarge ?? const TextStyle();

    final (fill, edge, text) = switch (tone) {
      _Tone.strong => (scheme.onSurface, null, scheme.surface),
      _Tone.neutral => (glass.chip, glass.edge, scheme.onSurface),
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
                : Border.all(
                    color: edge,
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

/// Membuka [SimpleConfirmSheet] sebagai route modal non-opaque di atas layar
/// (`design/components.md` C22).
///
/// Hasil `true` hanya saat aksi konfirmasi ditekan. Tutup dengan cara apa pun
/// lainnya (cancel, tap scrim, swipe handle, back sistem) menghasilkan `false`.
/// Fokus dikembalikan ke widget yang difokuskan sebelum sheet terbuka.
Future<bool> showSimpleConfirmSheet(
  BuildContext context, {
  required String title,
  required String body,
  required String confirmLabel,
  required String cancelLabel,
}) async {
  final reduced = ReducedMotion.of(context);
  final previousFocus = FocusManager.instance.primaryFocus;
  final navigator = Navigator.of(context);

  final route = PageRouteBuilder<bool>(
    opaque: false,
    barrierDismissible: true,
    barrierColor: context.glass.scrim,
    barrierLabel: cancelLabel,
    transitionDuration: reduced.duration(RMotion.sheetOpen),
    reverseTransitionDuration: reduced.duration(RMotion.sheetClose),
    settings: const RouteSettings(name: 'simple_confirm_sheet'),
    pageBuilder: (routeContext, _, _) => Align(
      alignment: Alignment.bottomCenter,
      child: SafeArea(
        top: false,
        child: SimpleConfirmSheet(
          title: title,
          body: body,
          confirmLabel: confirmLabel,
          cancelLabel: cancelLabel,
          onConfirm: () => Navigator.of(routeContext).pop(true),
          onCancel: () => Navigator.of(routeContext).pop(false),
        ),
      ),
    ),
    transitionsBuilder: (routeContext, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: reduced.curve(RMotion.standard),
        reverseCurve: reduced.curve(RMotion.accelerate),
      );
      if (reduced.enabled) {
        return FadeTransition(opacity: curved, child: child);
      }
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 1),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      );
    },
  );

  final result = await navigator.push<bool>(route);

  if (previousFocus != null && previousFocus.context != null) {
    previousFocus.requestFocus();
  }
  return result ?? false;
}
