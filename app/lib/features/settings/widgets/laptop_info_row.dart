import 'package:flutter/material.dart';

import '../../../core/strings/settings_strings.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../core/theme/tokens.g.dart';

/// Diameter titik status. Ukuran di artboard tidak ada token, jadi dipakai
/// nilai perkiraan dari `Settings-light.dc.html`.
const double _dotSize = 12;

/// Tebal cincin saat offline (artboard: 2 dp).
const double _ringWidth = 2;

/// Nama laptop di artboard: 18 dp semibold. Bukan token (bodyLarge 16).
const double _nameSize = 18;

/// Baris info laptop di grup LAPTOP: nama (dibungkus penuh, tanpa ellipsis),
/// `host:port` mono di bawahnya, dan status di kanan.
///
/// Status tidak hanya warna: online memakai titik terisi dan teks
/// "NYAMBUNG", offline memakai cincin kosong dan teks "NGGAK KEJANGKAU".
/// Satu node Semantics dengan label gabungan termasuk teks status.
final class LaptopInfoRow extends StatelessWidget {
  const LaptopInfoRow({
    super.key,
    required this.name,
    required this.address,
    required this.online,
  });

  final String name;

  /// `host:port` dari pairing.
  final String address;

  /// True untuk online dan back; false untuk offline, poweredOff, connecting.
  final bool online;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final body = theme.textTheme.bodyLarge ?? const TextStyle();
    final mono = (theme.textTheme.labelLarge ?? const TextStyle()).copyWith(
      fontFamily: RFont.mono,
      fontFamilyFallback: const ['monospace'],
      color: scheme.onSurfaceVariant,
    );

    final statusColor = online
        ? context.status.success
        : scheme.onSurfaceVariant;
    final statusText = online
        ? SettingsStrings.statusOnline
        : SettingsStrings.statusOffline;
    final statusStyle = (theme.textTheme.labelSmall ?? const TextStyle())
        .copyWith(
          fontFamily: RFont.mono,
          fontFamilyFallback: const ['monospace'],
          fontWeight: FontWeight.w600,
          color: statusColor,
        );

    return Semantics(
      label: '$name, $address, $statusText',
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: RSize.control),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: RSpace.s2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name,
                      style: body.copyWith(
                        fontSize: _nameSize,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(address, style: mono),
                  ],
                ),
              ),
              const SizedBox(width: RSpace.s3),
              ExcludeSemantics(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _StatusDot(online: online, color: statusColor),
                    const SizedBox(width: RSpace.s2),
                    Text(statusText, style: statusStyle),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Titik terisi (online) atau cincin kosong (offline), keduanya berwarna [color].
final class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.online, required this.color});

  final bool online;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: online ? color : null,
        border: online ? null : Border.all(color: color, width: _ringWidth),
      ),
      child: const SizedBox(width: _dotSize, height: _dotSize),
    );
  }
}
