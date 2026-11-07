import 'package:flutter/material.dart';

import 'tokens.g.dart';

Color _lerpColor(Color a, Color b, double t) => Color.lerp(a, b, t)!;

/// Kaca: panel, dock, pill, toast, dan sheet (`glass.*`).
final class GlassTokens extends ThemeExtension<GlassTokens> {
  const GlassTokens({
    required this.fill,
    required this.edge,
    required this.highlight,
    required this.lowlight,
    required this.shadow,
    required this.chip,
    required this.chipPressed,
    required this.chipDisabled,
    required this.solid,
    required this.sheet,
    required this.toast,
    required this.scrim,
  });

  factory GlassTokens.fromSet(TokenSet t) => GlassTokens(
    fill: t.glass.fill,
    edge: t.glass.edge,
    highlight: t.glass.highlight,
    lowlight: t.glass.lowlight,
    shadow: t.glass.shadow,
    chip: t.glass.chip,
    chipPressed: t.glass.chipPressed,
    chipDisabled: t.glass.chipDisabled,
    solid: t.glass.solid,
    sheet: t.glass.sheet,
    toast: t.glass.toast,
    scrim: t.glass.scrim,
  );

  final Color fill;
  final Color edge;
  final Color highlight;
  final Color lowlight;
  final Color shadow;
  final Color chip;
  final Color chipPressed;
  final Color chipDisabled;
  final Color solid;
  final Color sheet;
  final Color toast;
  final Color scrim;

  @override
  GlassTokens copyWith({
    Color? fill,
    Color? edge,
    Color? highlight,
    Color? lowlight,
    Color? shadow,
    Color? chip,
    Color? chipPressed,
    Color? chipDisabled,
    Color? solid,
    Color? sheet,
    Color? toast,
    Color? scrim,
  }) => GlassTokens(
    fill: fill ?? this.fill,
    edge: edge ?? this.edge,
    highlight: highlight ?? this.highlight,
    lowlight: lowlight ?? this.lowlight,
    shadow: shadow ?? this.shadow,
    chip: chip ?? this.chip,
    chipPressed: chipPressed ?? this.chipPressed,
    chipDisabled: chipDisabled ?? this.chipDisabled,
    solid: solid ?? this.solid,
    sheet: sheet ?? this.sheet,
    toast: toast ?? this.toast,
    scrim: scrim ?? this.scrim,
  );

  @override
  GlassTokens lerp(ThemeExtension<GlassTokens>? other, double t) {
    if (other is! GlassTokens) return this;
    return GlassTokens(
      fill: _lerpColor(fill, other.fill, t),
      edge: _lerpColor(edge, other.edge, t),
      highlight: _lerpColor(highlight, other.highlight, t),
      lowlight: _lerpColor(lowlight, other.lowlight, t),
      shadow: _lerpColor(shadow, other.shadow, t),
      chip: _lerpColor(chip, other.chip, t),
      chipPressed: _lerpColor(chipPressed, other.chipPressed, t),
      chipDisabled: _lerpColor(chipDisabled, other.chipDisabled, t),
      solid: _lerpColor(solid, other.solid, t),
      sheet: _lerpColor(sheet, other.sheet, t),
      toast: _lerpColor(toast, other.toast, t),
      scrim: _lerpColor(scrim, other.scrim, t),
    );
  }
}

/// Aksen teks dan bayangan (`accent.highlight`, `accent.shadow`, `accent.text`).
/// Warna utama tombol ada di `ColorScheme.primary`.
final class AccentTokens extends ThemeExtension<AccentTokens> {
  const AccentTokens({
    required this.highlight,
    required this.shadow,
    required this.text,
  });

  factory AccentTokens.fromSet(TokenSet t) => AccentTokens(
    highlight: t.accent.highlight,
    shadow: t.accent.shadow,
    text: t.accent.text,
  );

  final Color highlight;
  final Color shadow;
  final Color text;

  @override
  AccentTokens copyWith({Color? highlight, Color? shadow, Color? text}) =>
      AccentTokens(
        highlight: highlight ?? this.highlight,
        shadow: shadow ?? this.shadow,
        text: text ?? this.text,
      );

  @override
  AccentTokens lerp(ThemeExtension<AccentTokens>? other, double t) {
    if (other is! AccentTokens) return this;
    return AccentTokens(
      highlight: _lerpColor(highlight, other.highlight, t),
      shadow: _lerpColor(shadow, other.shadow, t),
      text: _lerpColor(text, other.text, t),
    );
  }
}

/// Warna status (`status.success`, `status.warning`, `status.dangerText`,
/// `status.dangerSoft`).
final class StatusTokens extends ThemeExtension<StatusTokens> {
  const StatusTokens({
    required this.success,
    required this.warning,
    required this.dangerText,
    required this.dangerSoft,
  });

  factory StatusTokens.fromSet(TokenSet t) => StatusTokens(
    success: t.status.success,
    warning: t.status.warning,
    dangerText: t.status.dangerText,
    dangerSoft: t.status.dangerSoft,
  );

  final Color success;
  final Color warning;
  final Color dangerText;
  final Color dangerSoft;

  @override
  StatusTokens copyWith({
    Color? success,
    Color? warning,
    Color? dangerText,
    Color? dangerSoft,
  }) => StatusTokens(
    success: success ?? this.success,
    warning: warning ?? this.warning,
    dangerText: dangerText ?? this.dangerText,
    dangerSoft: dangerSoft ?? this.dangerSoft,
  );

  @override
  StatusTokens lerp(ThemeExtension<StatusTokens>? other, double t) {
    if (other is! StatusTokens) return this;
    return StatusTokens(
      success: _lerpColor(success, other.success, t),
      warning: _lerpColor(warning, other.warning, t),
      dangerText: _lerpColor(dangerText, other.dangerText, t),
      dangerSoft: _lerpColor(dangerSoft, other.dangerSoft, t),
    );
  }
}

/// Kontrol: slider, segmen, switch, cincin hitung mundur, dan `fg.disabled`.
final class ControlTokens extends ThemeExtension<ControlTokens> {
  const ControlTokens({
    required this.sliderFill,
    required this.sliderTrack,
    required this.segTrack,
    required this.segOn,
    required this.switchOff,
    required this.switchThumb,
    required this.countdownInner,
    required this.fgDisabled,
  });

  factory ControlTokens.fromSet(TokenSet t) => ControlTokens(
    sliderFill: t.slider.fill,
    sliderTrack: t.slider.track,
    segTrack: t.control.segTrack,
    segOn: t.control.segOn,
    switchOff: t.control.switchOff,
    switchThumb: t.control.switchThumb,
    countdownInner: t.control.countdownInner,
    fgDisabled: t.fg.disabled,
  );

  final Color sliderFill;
  final Color sliderTrack;
  final Color segTrack;
  final Color segOn;
  final Color switchOff;
  final Color switchThumb;
  final Color countdownInner;
  final Color fgDisabled;

  @override
  ControlTokens copyWith({
    Color? sliderFill,
    Color? sliderTrack,
    Color? segTrack,
    Color? segOn,
    Color? switchOff,
    Color? switchThumb,
    Color? countdownInner,
    Color? fgDisabled,
  }) => ControlTokens(
    sliderFill: sliderFill ?? this.sliderFill,
    sliderTrack: sliderTrack ?? this.sliderTrack,
    segTrack: segTrack ?? this.segTrack,
    segOn: segOn ?? this.segOn,
    switchOff: switchOff ?? this.switchOff,
    switchThumb: switchThumb ?? this.switchThumb,
    countdownInner: countdownInner ?? this.countdownInner,
    fgDisabled: fgDisabled ?? this.fgDisabled,
  );

  @override
  ControlTokens lerp(ThemeExtension<ControlTokens>? other, double t) {
    if (other is! ControlTokens) return this;
    return ControlTokens(
      sliderFill: _lerpColor(sliderFill, other.sliderFill, t),
      sliderTrack: _lerpColor(sliderTrack, other.sliderTrack, t),
      segTrack: _lerpColor(segTrack, other.segTrack, t),
      segOn: _lerpColor(segOn, other.segOn, t),
      switchOff: _lerpColor(switchOff, other.switchOff, t),
      switchThumb: _lerpColor(switchThumb, other.switchThumb, t),
      countdownInner: _lerpColor(countdownInner, other.countdownInner, t),
      fgDisabled: _lerpColor(fgDisabled, other.fgDisabled, t),
    );
  }
}

/// Cahaya latar statis (`bg.glowA`, `bg.glowB`). Warna dasar ada di
/// `ColorScheme.surface`.
final class BackdropTokens extends ThemeExtension<BackdropTokens> {
  const BackdropTokens({required this.glowA, required this.glowB});

  factory BackdropTokens.fromSet(TokenSet t) =>
      BackdropTokens(glowA: t.bg.glowA, glowB: t.bg.glowB);

  final Color glowA;
  final Color glowB;

  @override
  BackdropTokens copyWith({Color? glowA, Color? glowB}) =>
      BackdropTokens(glowA: glowA ?? this.glowA, glowB: glowB ?? this.glowB);

  @override
  BackdropTokens lerp(ThemeExtension<BackdropTokens>? other, double t) {
    if (other is! BackdropTokens) return this;
    return BackdropTokens(
      glowA: _lerpColor(glowA, other.glowA, t),
      glowB: _lerpColor(glowB, other.glowB, t),
    );
  }
}

/// Akses cepat ke ThemeExtension dari `BuildContext`.
extension RThemeContext on BuildContext {
  GlassTokens get glass => Theme.of(this).extension<GlassTokens>()!;
  AccentTokens get accent => Theme.of(this).extension<AccentTokens>()!;
  StatusTokens get status => Theme.of(this).extension<StatusTokens>()!;
  ControlTokens get control => Theme.of(this).extension<ControlTokens>()!;
  BackdropTokens get backdrop => Theme.of(this).extension<BackdropTokens>()!;
}
