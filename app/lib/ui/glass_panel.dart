import 'dart:ui' show ImageFilter;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:remotto/core/theme/glass_mode.dart';
import 'package:remotto/core/theme/theme_extensions.dart';
import 'package:remotto/core/theme/tokens.g.dart';

/// Varian permukaan kaca (`design/components.md` C01).
enum GlassPanelVariant {
  /// Panel volume: radius `lg`, isi `glass.fill`, blur `glass`.
  panel,

  /// Dock media: radius penuh, isi `glass.fill`, blur `glass`.
  dock,

  /// Pill status: radius penuh, isi `glass.fill`. Tinggi diatur pemanggil.
  pill,

  /// Toast: radius `sm`, isi `glass.toast`, blur `sheet`, tanpa saturasi.
  toast,
}

/// Bayangan luar kaca. Bukan token: nilainya dari `Remote-360-dark.dc.html`
/// (`0 12px 32px var(--glShadow)`), warnanya `glass.shadow`.
const Offset _shadowOffset = Offset(0, 12);
const double _shadowBlur = 32;

/// Permukaan kaca: blur latar, isi tint, garis tepi, highlight atas.
///
/// Maksimal satu lapis blur per area: jangan menumpuk [GlassPanel] di dalam
/// [GlassPanel] lain. Isi panel memakai chip tanpa blur (GlassKey chip).
///
/// Saat [GlassMode.isSolid] bernilai true (high contrast, reduce
/// transparency, atau raster lambat), blur dan bayangan dilepas dan isi
/// memakai `glass.solid`; garis tepi dan highlight tetap.
class GlassPanel extends ConsumerWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.variant = GlassPanelVariant.panel,
    this.padding,
    this.semanticsLabel,
  });

  final Widget child;
  final GlassPanelVariant variant;
  final EdgeInsetsGeometry? padding;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final solid = GlassMode.isSolid(context, ref);
    final glass = context.glass;
    final radius = BorderRadius.circular(_radius(variant));

    final fill = solid
        ? glass.solid
        : switch (variant) {
            GlassPanelVariant.toast => glass.toast,
            _ => glass.fill,
          };

    final body = Stack(
      fit: StackFit.passthrough,
      children: [
        // Highlight dalam atas, di bawah isi dan tetap terpotong radius.
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: RComponent.glassPanelEdgeWidth,
          child: ColoredBox(color: glass.highlight),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: fill,
            border: Border.all(
              color: glass.edge,
              width: RComponent.glassPanelEdgeWidth,
            ),
            borderRadius: radius,
          ),
          child: padding == null
              ? child
              : Padding(padding: padding!, child: child),
        ),
      ],
    );

    final clipped = ClipRRect(
      borderRadius: radius,
      child: solid
          ? body
          : BackdropFilter(filter: _blurFilter(variant), child: body),
    );

    return Semantics(
      container: true,
      label: semanticsLabel,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: solid
              ? null
              : [
                  BoxShadow(
                    color: glass.shadow,
                    offset: _shadowOffset,
                    blurRadius: _shadowBlur,
                  ),
                ],
        ),
        child: clipped,
      ),
    );
  }

  static double _radius(GlassPanelVariant variant) => switch (variant) {
    GlassPanelVariant.panel => RRadius.lg,
    GlassPanelVariant.dock => RRadius.full,
    GlassPanelVariant.pill => RRadius.full,
    GlassPanelVariant.toast => RRadius.sm,
  };

  /// Blur dibagi dua untuk sigma (`design-system.md` section 9).
  ///
  /// Saturasi `component.glassPanel.saturation` belum diterapkan: API
  /// `ImageFilter` Flutter 3.47 tidak punya `colorFilter`, dan
  /// `ImageFilter.compose` hanya menerima dua `ImageFilter`. Lihat laporan.
  static ImageFilter _blurFilter(GlassPanelVariant variant) {
    final blur = variant == GlassPanelVariant.toast ? RBlur.sheet : RBlur.glass;
    return ImageFilter.blur(sigmaX: blur / 2, sigmaY: blur / 2);
  }
}
