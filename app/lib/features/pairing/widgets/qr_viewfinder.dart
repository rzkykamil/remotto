import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/strings/pairing_strings.dart';
import '../../../core/theme/tokens.g.dart';
import '../../../ui/glass_key.dart';
import '../../../ui/r_icon.dart';
import '../../../ui/r_icons_data.dart';
import '../data/qr_scanner_source.dart';
import '../state/pairing_flow_controller.dart';

/// The only file that imports `mobile_scanner`. Other screens use
/// [QrScannerSource] and the widgets in this file.

/// Camera controller. Lives for the app lifetime; [QrViewfinder] turns the camera on and
/// off while the scan screen is shown.
final mobileScannerControllerProvider = Provider<MobileScannerController>((
  ref,
) {
  final controller = MobileScannerController(
    autoStart: false,
    formats: const [BarcodeFormat.qrCode],
  );
  ref.onDispose(controller.dispose);
  return controller;
});

/// Real implementation of [QrScannerSource] via `mobile_scanner`. To be
/// overridden into `qrScannerSourceProvider` in app assembly (T17).
final mobileScannerQrSourceProvider = Provider<QrScannerSource>(
  (ref) => MobileScannerQrSource(ref.watch(mobileScannerControllerProvider)),
);

/// Turns a camera result into a raw QR value. Codes without content are dropped.
final class MobileScannerQrSource implements QrScannerSource {
  MobileScannerQrSource(MobileScannerController controller)
    : _codes = controller.barcodes.expand(_rawValues).asBroadcastStream();

  final Stream<String> _codes;

  @override
  Stream<String> get codes => _codes;

  static Iterable<String> _rawValues(BarcodeCapture capture) sync* {
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw != null && raw.isNotEmpty) yield raw;
    }
  }
}

/// Full camera preview. Turns the camera on when shown and off
/// when disposed. Permission denied at start is routed to the permission flow via
/// [PairingFlowController.onScanPressed]. Other camera errors have no copy
/// in the artboard, so the preview stays dark and "Isi manual" remains available.
final class QrViewfinder extends ConsumerStatefulWidget {
  const QrViewfinder({super.key});

  @override
  ConsumerState<QrViewfinder> createState() => _QrViewfinderState();
}

final class _QrViewfinderState extends ConsumerState<QrViewfinder> {
  late final MobileScannerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ref.read(mobileScannerControllerProvider);
    unawaited(_start());
  }

  @override
  void dispose() {
    unawaited(_stop());
    super.dispose();
  }

  Future<void> _start() async {
    try {
      await _controller.start();
    } on MobileScannerException catch (error) {
      if (!mounted) return;
      if (error.errorCode == MobileScannerErrorCode.permissionDenied) {
        await ref.read(pairingFlowProvider.notifier).onScanPressed();
      }
    }
  }

  Future<void> _stop() async {
    try {
      await _controller.stop();
    } on MobileScannerException {
      // The camera already stopped or the controller was disposed: nothing to
      // do when the screen closes.
    }
  }

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    return MobileScanner(
      controller: _controller,
      fit: BoxFit.cover,
      placeholderBuilder: (_) => ColoredBox(color: surface),
      errorBuilder: (_, _) => ColoredBox(color: surface),
    );
  }
}

/// Flashlight button (`design/export/artboards/Pairing-light.dc.html`, Q03).
/// Disabled if the device has no flashlight. The on state is read out as a
/// toggle.
final class QrTorchKey extends ConsumerWidget {
  const QrTorchKey({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(mobileScannerControllerProvider);
    final scheme = Theme.of(context).colorScheme;

    return ValueListenableBuilder<MobileScannerState>(
      valueListenable: controller,
      builder: (context, state, _) {
        final torch = state.torchState;
        return GlassKey(
          semanticsLabel: PairingStrings.scanTorch,
          variant: GlassKeyVariant.glass,
          size: GlassKeySize.touch,
          toggled: torch == TorchState.on,
          onPressed: torch == TorchState.unavailable
              ? null
              : () => unawaited(controller.toggleTorch()),
          icon: RIcon(
            RIcons.flashlight,
            size: RSpace.s5,
            color: scheme.onSurface,
          ),
        );
      },
    );
  }
}
