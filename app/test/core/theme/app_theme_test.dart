import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotto/core/theme/app_theme.dart';
import 'package:remotto/core/theme/theme_extensions.dart';
import 'package:remotto/core/theme/tokens.g.dart';

import '../../support/test_app.dart';

void main() {
  group('ColorScheme mapping', () {
    for (final (name, theme, t) in [
      ('light', AppTheme.light, kLightTokens),
      ('dark', AppTheme.dark, kDarkTokens),
    ]) {
      test('$name matches the design tokens (table section 2)', () {
        final s = theme.colorScheme;
        expect(s.primary, t.accent.defaultColor);
        expect(s.onPrimary, t.accent.on);
        expect(s.secondary, t.accent.text);
        expect(s.onSecondary, t.bg.base);
        expect(s.error, t.status.danger);
        expect(s.onError, t.status.onDanger);
        expect(s.surface, t.bg.base);
        expect(s.onSurface, t.fg.primary);
        expect(s.onSurfaceVariant, t.fg.secondary);
      });

      test('$name surfaceTint is transparent', () {
        expect(theme.colorScheme.surfaceTint, Colors.transparent);
      });

      test('$name scaffold background is transparent', () {
        expect(theme.scaffoldBackgroundColor, Colors.transparent);
      });

      test('$name uses NoSplash', () {
        expect(theme.splashFactory, NoSplash.splashFactory);
      });
    }

    test('brightness follows the theme', () {
      expect(AppTheme.light.brightness, Brightness.light);
      expect(AppTheme.dark.brightness, Brightness.dark);
    });
  });

  group('ThemeExtension', () {
    test('all five extensions exist in both themes', () {
      for (final theme in [AppTheme.light, AppTheme.dark]) {
        expect(theme.extension<GlassTokens>(), isNotNull);
        expect(theme.extension<AccentTokens>(), isNotNull);
        expect(theme.extension<StatusTokens>(), isNotNull);
        expect(theme.extension<ControlTokens>(), isNotNull);
        expect(theme.extension<BackdropTokens>(), isNotNull);
      }
    });

    test('lerp at 0.5 lands between two colors', () {
      final a = GlassTokens.fromSet(kLightTokens);
      final b = GlassTokens.fromSet(kDarkTokens);
      final mid = a.lerp(b, 0.5);
      expect(mid.solid, Color.lerp(a.solid, b.solid, 0.5));
      expect(mid.solid, isNot(a.solid));
      expect(mid.solid, isNot(b.solid));
    });

    test('lerp with another type returns this', () {
      final a = BackdropTokens.fromSet(kLightTokens);
      expect(a.lerp(null, 0.5).glowA, a.glowA);
    });

    test('copyWith overrides only one field', () {
      final a = AccentTokens.fromSet(kLightTokens);
      final c = a.copyWith(text: const Color(0xFF000000));
      expect(c.text, const Color(0xFF000000));
      expect(c.highlight, a.highlight);
      expect(c.shadow, a.shadow);
    });

    test('ControlTokens carries fg.disabled', () {
      expect(
        ControlTokens.fromSet(kDarkTokens).fgDisabled,
        kDarkTokens.fg.disabled,
      );
    });

    testWidgets('BuildContext helpers read the active theme', (tester) async {
      late GlassTokens glass;
      late BackdropTokens backdrop;
      await pumpApp(
        tester,
        Builder(
          builder: (context) {
            glass = context.glass;
            backdrop = context.backdrop;
            return const SizedBox.shrink();
          },
        ),
        dark: true,
      );
      expect(glass.solid, kDarkTokens.glass.solid);
      expect(backdrop.glowA, kDarkTokens.bg.glowA);
    });
  });

  group('text theme', () {
    test('displayVolume is Geist Mono with tabular figures', () {
      final style = AppTheme.light.textTheme.displayLarge!;
      expect(style.fontFamily, 'Geist Mono');
      expect(style.fontFeatures, contains(const FontFeature.tabularFigures()));
      expect(style.color, kLightTokens.fg.primary);
    });

    test('titleXl is Geist 28 with height 34/28', () {
      final style = AppTheme.light.textTheme.headlineSmall!;
      expect(style.fontFamily, 'Geist');
      expect(style.fontSize, 28);
      expect(style.height, closeTo(34 / 28, 1e-9));
      expect(style.fontFeatures, isNull);
    });
  });
}
