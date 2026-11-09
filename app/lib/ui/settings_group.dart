import 'package:flutter/material.dart';

import '../core/theme/theme_extensions.dart';
import '../core/theme/tokens.g.dart';
import 'glass_panel.dart';
import 'pressable.dart';
import 'r_icon.dart';
import 'r_icons_data.dart';

/// Padding horizontal isi grup: 18 dp dari `Settings-light.dc.html`. Bukan
/// token, sama seperti konstanta artboard di `status_pill.dart`.
const double _groupPaddingX = 18;

/// Inset caption dari tepi kiri (`.cap` 4 dp di artboard).
const double _captionInset = RSpace.s1;

/// Tebal pemisah antar baris: 1 dp (`design/components.md` C19).
const double _dividerHeight = 1;

/// Chevron di artboard: 18 dp, stroke 2.2.
const double _chevronSize = 18;
const double _chevronStroke = 2.2;

/// Grup Pengaturan (`design/components.md` C19): caption kapital di atas,
/// lalu satu [GlassPanel] varian group berisi [children].
///
/// Pemisah 1 dp dipasang di antara baris, tidak di atas baris pertama.
/// Hanya satu lapis blur: baris di dalam grup tidak memakai blur.
final class SettingsGroup extends StatelessWidget {
  const SettingsGroup({
    super.key,
    required this.caption,
    required this.children,
  });

  /// Judul grup, ditampilkan kapital. Tidak dijadikan label container karena
  /// label container menggabungkan semua baris menjadi satu node.
  final String caption;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final captionStyle =
        (Theme.of(context).textTheme.labelSmall ?? const TextStyle()).copyWith(
          color: scheme.onSurfaceVariant,
        );

    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        rows.add(
          SizedBox(
            height: _dividerHeight,
            child: ColoredBox(color: context.glass.lowlight),
          ),
        );
      }
      rows.add(children[i]);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: _captionInset),
          child: Text(caption.toUpperCase(), style: captionStyle),
        ),
        const SizedBox(height: RSpace.s2),
        GlassPanel(
          variant: GlassPanelVariant.group,
          padding: const EdgeInsets.symmetric(horizontal: _groupPaddingX),
          // explicitChildNodes menjaga setiap baris tetap satu node, tidak
          // digabung ke container panel.
          child: Semantics(
            explicitChildNodes: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: rows,
            ),
          ),
        ),
      ],
    );
  }
}

/// Varian baris Pengaturan (`design/components.md` C19).
enum SettingsRowVariant {
  /// Label kiri, nilai kanan mono. Tidak bisa ditekan.
  info,

  /// Teks aksi `accent.text` semibold dengan chevron.
  action,

  /// Label dengan chevron.
  navigation,

  /// Label, subteks opsional, dan [SettingsRow.trailing] (mis. switch).
  switchRow,
}

/// Baris grup Pengaturan, tinggi minimal `RSize.control` (56 dp).
///
/// Baris yang bisa ditekan dibungkus [Pressable]. Baris info memakai Semantics
/// biasa, jadi keduanya tetap satu node dengan label gabungan. Baris Pengaturan
/// tidak memakai haptic karena tidak ada di tabel `design/design-system.md`.
final class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.variant,
    required this.label,
    this.value,
    this.subtitle,
    this.trailing,
    this.onPressed,
    this.toggled,
  }) : assert(
         variant != SettingsRowVariant.info || value != null,
         'Baris info wajib punya value.',
       ),
       assert(
         variant != SettingsRowVariant.switchRow || trailing != null,
         'Baris switchRow wajib punya trailing.',
       );

  final SettingsRowVariant variant;
  final String label;

  /// Nilai kanan untuk varian info.
  final String? value;

  /// Subteks opsional untuk varian switchRow.
  final String? subtitle;

  /// Widget kanan untuk varian switchRow, dibuat pemanggil.
  final Widget? trailing;
  final VoidCallback? onPressed;

  /// Status toggle untuk varian switchRow.
  final bool? toggled;

  String get _semanticsLabel => switch (variant) {
    SettingsRowVariant.info => '$label, $value',
    SettingsRowVariant.switchRow =>
      subtitle == null ? label : '$label, $subtitle',
    _ => label,
  };

  @override
  Widget build(BuildContext context) {
    // Baris info tidak bisa ditekan. Pressable selalu menandai button, jadi
    // baris info memakai Semantics biasa agar tidak terbaca sebagai tombol.
    if (variant == SettingsRowVariant.info) {
      return Semantics(
        label: _semanticsLabel,
        excludeSemantics: true,
        child: _frame(context, highlighted: false),
      );
    }
    return Pressable(
      semanticsLabel: _semanticsLabel,
      onPressed: onPressed,
      toggled: toggled,
      haptic: PressHaptic.none,
      pressedScale: 1.0,
      focusRingRadius: RRadius.sm,
      builder: (context, pressed) =>
          _frame(context, highlighted: pressed && onPressed != null),
    );
  }

  Widget _frame(BuildContext context, {required bool highlighted}) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: RSize.control),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: highlighted ? context.glass.chipPressed : null,
          borderRadius: BorderRadius.circular(RRadius.sm),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: RSpace.s2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: _content(context),
          ),
        ),
      ),
    );
  }

  List<Widget> _content(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final body = theme.textTheme.bodyLarge ?? const TextStyle();
    final chevron = RIcon(
      RIcons.chevronRight,
      size: _chevronSize,
      color: scheme.onSurfaceVariant,
      strokeWidth: _chevronStroke,
    );

    switch (variant) {
      case SettingsRowVariant.info:
        return [
          Expanded(child: Text(label, style: body)),
          const SizedBox(width: RSpace.s3),
          Flexible(
            child: Text(
              value!,
              textAlign: TextAlign.end,
              style: body.copyWith(
                fontFamily: RFont.mono,
                fontFamilyFallback: const ['monospace'],
                fontFeatures: const [FontFeature.tabularFigures()],
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ];
      case SettingsRowVariant.action:
        return [
          Expanded(
            child: Text(
              label,
              style: body.copyWith(
                color: context.accent.text,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          chevron,
        ];
      case SettingsRowVariant.navigation:
        return [Expanded(child: Text(label, style: body)), chevron];
      case SettingsRowVariant.switchRow:
        final sub = subtitle;
        return [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: body),
                if (sub != null)
                  Text(
                    sub,
                    style: (theme.textTheme.labelLarge ?? const TextStyle())
                        .copyWith(color: scheme.onSurfaceVariant),
                  ),
              ],
            ),
          ),
          const SizedBox(width: RSpace.s3),
          trailing!,
        ];
    }
  }
}
