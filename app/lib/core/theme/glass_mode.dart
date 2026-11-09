import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Why glass surfaces are drawn solid instead of blurred.
enum GlassFallbackReason { none, highContrast, reduceTransparency, slowRaster }

/// Set by the platform channel (iOS reduce transparency, wired in M5).
final class ReduceTransparencyNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) => state = value;
}

/// Set by the raster timing monitor when frames are consistently slow
/// (wired in M6). Lasts for the whole session.
final class SlowRasterNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) => state = value;
}

final reduceTransparencyProvider =
    NotifierProvider<ReduceTransparencyNotifier, bool>(
      ReduceTransparencyNotifier.new,
    );

final slowRasterProvider = NotifierProvider<SlowRasterNotifier, bool>(
  SlowRasterNotifier.new,
);

/// True when either platform flag forces solid glass.
final glassForcedSolidProvider = Provider<bool>(
  (ref) =>
      ref.watch(reduceTransparencyProvider) || ref.watch(slowRasterProvider),
);

/// Single entry point for "should this surface be solid?".
///
/// Widgets call this instead of checking the sources themselves, so the
/// fallback rules stay in one place (design-system.md section 7).
abstract final class GlassMode {
  static bool isSolid(BuildContext context, WidgetRef ref) =>
      MediaQuery.highContrastOf(context) || ref.watch(glassForcedSolidProvider);

  /// Reason for the fallback, checked in order: reduce transparency,
  /// high contrast, slow raster, then none.
  static GlassFallbackReason reason(BuildContext context, WidgetRef ref) {
    if (ref.watch(reduceTransparencyProvider)) {
      return GlassFallbackReason.reduceTransparency;
    }
    if (MediaQuery.highContrastOf(context)) {
      return GlassFallbackReason.highContrast;
    }
    if (ref.watch(slowRasterProvider)) {
      return GlassFallbackReason.slowRaster;
    }
    return GlassFallbackReason.none;
  }
}
