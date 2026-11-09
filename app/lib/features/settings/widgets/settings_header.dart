import 'package:flutter/material.dart';

import '../../../core/strings/settings_strings.dart';
import '../../../core/theme/tokens.g.dart';
import '../../../ui/glass_key.dart';
import '../../../ui/r_icon.dart';
import '../../../ui/r_icons_data.dart';

/// Ikon back di dalam tombol 48 dp (`design/components.md` C02: 17-22 dp).
const double _backIconSize = 20;

/// Judul SCR-020 di artboard: 20 semibold. Bukan token (titleMd 22, titleLg 24),
/// jadi ukurannya dipakai sebagai override dari `titleLarge`.
const double _titleSize = 20;

/// Header SCR-020: tombol back 48 dp di kiri dan judul "Pengaturan" di sebelahnya.
///
/// Tidak memakai `AppBar`. Back memanggil [onBack]; pemanggil yang menentukan
/// aksinya (di layar ini `context.pop()`).
final class SettingsHeader extends StatelessWidget {
  const SettingsHeader({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titleStyle = (theme.textTheme.titleLarge ?? const TextStyle())
        .copyWith(fontSize: _titleSize, fontWeight: FontWeight.w600);

    return SizedBox(
      height: RSize.touchMin,
      child: Row(
        children: [
          GlassKey(
            semanticsLabel: SettingsStrings.backSemantics,
            onPressed: onBack,
            variant: GlassKeyVariant.chip,
            size: GlassKeySize.touch,
            icon: RIcon(
              RIcons.back,
              size: _backIconSize,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(width: RSpace.s3),
          Expanded(
            child: Semantics(
              header: true,
              child: Text(SettingsStrings.title, style: titleStyle),
            ),
          ),
        ],
      ),
    );
  }
}
