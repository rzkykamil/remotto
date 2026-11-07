import 'package:flutter/material.dart';

import 'theme_extensions.dart';
import 'tokens.g.dart';

/// Tema terang dan gelap, dibangun dari `kLightTokens` dan `kDarkTokens`.
abstract final class AppTheme {
  static ThemeData get light => _build(kLightTokens, Brightness.light);

  static ThemeData get dark => _build(kDarkTokens, Brightness.dark);

  static ThemeData _build(TokenSet t, Brightness brightness) {
    final scheme = ColorScheme(
      brightness: brightness,
      primary: t.accent.defaultColor,
      onPrimary: t.accent.on,
      secondary: t.accent.text,
      onSecondary: t.bg.base,
      error: t.status.danger,
      onError: t.status.onDanger,
      surface: t.bg.base,
      onSurface: t.fg.primary,
      onSurfaceVariant: t.fg.secondary,
      surfaceTint: Colors.transparent,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      // Latar digambar LightBackdrop (M0 T13), bukan Scaffold.
      scaffoldBackgroundColor: Colors.transparent,
      splashFactory: NoSplash.splashFactory,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      hoverColor: Colors.transparent,
      textTheme: _textTheme(t.fg.primary),
      // Transisi layar diatur router lewat CustomTransitionPage (M0 T14),
      // jadi transisi default platform dimatikan.
      pageTransitionsTheme: PageTransitionsTheme(
        builders: {
          for (final p in TargetPlatform.values)
            p: const _NoTransitionsBuilder(),
        },
      ),
      extensions: [
        GlassTokens.fromSet(t),
        AccentTokens.fromSet(t),
        StatusTokens.fromSet(t),
        ControlTokens.fromSet(t),
        BackdropTokens.fromSet(t),
      ],
    );
  }

  static TextTheme _textTheme(Color color) {
    final base = Typography.material2021().black.apply(
      bodyColor: color,
      displayColor: color,
    );
    return base.merge(
      TextTheme(
        displayLarge: _style(RType.displayVolume, color),
        displayMedium: _style(RType.displayCountdown, color),
        headlineSmall: _style(RType.titleXl, color),
        titleLarge: _style(RType.titleLg, color),
        titleMedium: _style(RType.titleMd, color),
        bodyLarge: _style(RType.body, color),
        labelLarge: _style(RType.label, color),
        // Caption dikapitalkan oleh pemakai (teks di-uppercase), bukan di sini.
        labelSmall: _style(RType.caption, color),
      ),
    );
  }

  static TextStyle _style(TypeSpec spec, Color color) {
    final mono = spec.family == RFont.mono;
    return TextStyle(
      fontFamily: spec.family,
      // Fallback sistem bila font bundel gagal dimuat.
      fontFamilyFallback: mono ? const ['monospace'] : const ['Roboto'],
      fontSize: spec.size,
      fontWeight: spec.weight,
      height: spec.height,
      letterSpacing: spec.letterSpacing,
      color: color,
      fontFeatures: mono ? const [FontFeature.tabularFigures()] : null,
    );
  }
}

/// Transisi halaman kosong: router yang mengatur gerak layar.
final class _NoTransitionsBuilder extends PageTransitionsBuilder {
  const _NoTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child;
}
