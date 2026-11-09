import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/connection/connection_providers.dart';
import '../../../core/router/app_router.dart';
import '../../../core/storage/storage_providers.dart';
import '../../../core/strings/remote_strings.dart';
import '../../../core/strings/settings_strings.dart';
import '../../../core/toast/toast_controller.dart';
import '../../../ui/simple_confirm_sheet.dart';
import '../../pairing/state/pairing_flow_controller.dart';

/// Konfirmasi "Pairing ulang?" (SCR-021, artboard R04). Sheet satu tahap tanpa
/// tahan-konfirmasi, karena data bisa didapat lagi lewat scan QR.
///
/// Completes with `true` only when the user taps "Hapus & pairing ulang".
/// Every other way of closing the sheet completes with `false`.
Future<bool> showRepairConfirmSheet(
  BuildContext context, {
  required String laptopName,
}) {
  return showSimpleConfirmSheet(
    context,
    title: SettingsStrings.repairSheetTitle,
    body: SettingsStrings.repairSheetBody(laptopName),
    confirmLabel: SettingsStrings.repairSheetConfirm,
    cancelLabel: SettingsStrings.repairSheetCancel,
  );
}

/// Alur pairing ulang dari Pengaturan dan dari Remote offline (C08 → C22 → Q01).
///
/// Sheet false/null tidak mengubah apa pun. Setelah true: reset alur pairing,
/// hapus data pairing (ikut menghapus `lastPowerCommand`), hentikan polling,
/// lalu ganti stack navigasi ke `/pairing` supaya back tidak kembali ke layar
/// sebelumnya. Bila penghapusan gagal, tampilkan toast dan tetap di layar.
Future<void> runRepairFlow(
  BuildContext context,
  WidgetRef ref, {
  required String laptopName,
}) async {
  final confirmed = await showRepairConfirmSheet(
    context,
    laptopName: laptopName,
  );
  if (!confirmed) return;
  if (!context.mounted) return;
  // Pairing sudah hilang saat sheet tertutup (mis. dihapus dari tempat lain).
  if (ref.read(pairingProvider) == null) return;

  try {
    ref.read(pairingFlowProvider.notifier).reset();
    await ref.read(pairingProvider.notifier).clear();
  } catch (_) {
    if (!context.mounted) return;
    ref
        .read(toastControllerProvider.notifier)
        .show(
          const ToastMessage(
            text: RemoteStrings.toastCommandFailed,
            variant: ToastVariant.error,
          ),
        );
    return;
  }
  if (!context.mounted) return;

  ref.read(connectionControllerProvider.notifier).stop();
  context.go(AppRoutes.pairing);
}
