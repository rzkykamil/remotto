import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/connection/connection_providers.dart';
import '../../core/connection/connection_state.dart';
import '../../core/storage/storage_providers.dart';
import '../../core/strings/settings_strings.dart';
import '../../core/strings/uptime_format.dart';
import '../../core/theme/tokens.g.dart';
import '../../ui/glass_switch.dart';
import '../../ui/settings_group.dart';
import '../../ui/theme_segmented.dart';
import 'widgets/laptop_info_row.dart';
import 'widgets/repair_confirm.dart';
import 'widgets/settings_header.dart';

/// Lebar di bawah nilai ini memakai margin kompak, sama dengan layar pairing.
const double _compactWidth = 400;

/// SCR-020 Pengaturan (`design/screens.md`, artboard R01-R06).
///
/// Dibuka dengan push dari tombol pengaturan di Remote; back memanggil
/// `context.pop()`. Tanpa `Scaffold`: latar datang dari `LightBackdrop` di
/// `app.dart`. Layar ini hanya membaca state; tidak menyalakan atau mematikan
/// polling. Perubahan tema dan haptic langsung berlaku tanpa tombol Simpan.
final class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final width = MediaQuery.sizeOf(context).width;
    final gutter = width < _compactWidth
        ? RSize.screenMarginCompact
        : RSize.screenMargin;

    final connection = ref.watch(connectionControllerProvider);
    final pairing = ref.watch(pairingProvider);
    final themeMode = ref.watch(themeModeProvider);
    final hapticEnabled = ref.watch(hapticEnabledProvider);

    final name = connection.status?.name ?? pairing?.laptopName ?? '';
    final address = pairing == null ? '' : '${pairing.host}:${pairing.port}';
    final online =
        connection.phase == ConnectionPhase.online ||
        connection.phase == ConnectionPhase.back;
    // Uptime hanya dari status yang sedang tersambung; offline memakai "—".
    final uptime = online ? connection.uptime : null;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: gutter),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SettingsHeader(onBack: () => context.pop()),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(
                  top: RSpace.s4,
                  bottom: RSpace.s8,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SettingsGroup(
                      caption: SettingsStrings.laptopCaption,
                      children: [
                        LaptopInfoRow(
                          name: name,
                          address: address,
                          online: online,
                        ),
                        SettingsRow(
                          variant: SettingsRowVariant.info,
                          label: SettingsStrings.uptimeLabel,
                          value: uptime == null
                              ? SettingsStrings.uptimeUnknown
                              : formatUptimeLong(uptime),
                        ),
                        SettingsRow(
                          variant: SettingsRowVariant.action,
                          label: SettingsStrings.repairPairing,
                          onPressed: () =>
                              unawaited(_repair(context, ref, name)),
                        ),
                      ],
                    ),
                    const SizedBox(height: RSpace.s6),
                    SettingsGroup(
                      caption: SettingsStrings.displayCaption,
                      children: [
                        _ThemeRow(
                          value: themeMode,
                          onChanged: (mode) => unawaited(
                            ref.read(themeModeProvider.notifier).set(mode),
                          ),
                        ),
                        SettingsRow(
                          variant: SettingsRowVariant.switchRow,
                          label: SettingsStrings.hapticLabel,
                          subtitle: hapticEnabled
                              ? SettingsStrings.hapticOn
                              : SettingsStrings.hapticOff,
                          toggled: hapticEnabled,
                          onPressed: () => unawaited(
                            ref
                                .read(hapticEnabledProvider.notifier)
                                .set(enabled: !hapticEnabled),
                          ),
                          // Switch hanya tampilan; sentuhan ditangani seluruh
                          // baris agar satu baris tetap satu node.
                          trailing: GlassSwitch(
                            value: hapticEnabled,
                            onChanged: null,
                            semanticsLabel: SettingsStrings.hapticLabel,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _repair(BuildContext context, WidgetRef ref, String name) =>
      runRepairFlow(context, ref, laptopName: name);
}

/// Baris "Tema": label di atas, lalu [ThemeSegmented] selebar baris.
final class _ThemeRow extends StatelessWidget {
  const _ThemeRow({required this.value, required this.onChanged});

  final ThemeMode value;
  final ValueChanged<ThemeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final body = Theme.of(context).textTheme.bodyLarge ?? const TextStyle();

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: RSize.control),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: RSpace.s3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Label dibaca lewat Semantics "Tema" milik ThemeSegmented.
            ExcludeSemantics(
              child: Text(SettingsStrings.themeLabel, style: body),
            ),
            const SizedBox(height: RSpace.s2),
            // ThemeSegmented memakai Row stretch; di dalam Column scroll tinggi
            // tak terbatas, jadi tinggi dikunci ke tinggi isi.
            IntrinsicHeight(
              child: ThemeSegmented(value: value, onChanged: onChanged),
            ),
          ],
        ),
      ),
    );
  }
}
