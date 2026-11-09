import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/strings/pairing_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/r_behavior.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../core/theme/tokens.g.dart';
import '../../../core/toast/toast_controller.dart';
import '../../../ui/glass_key.dart';
import '../../../ui/glass_toast.dart';
import '../../../ui/qr_viewfinder_frame.dart';
import '../../../ui/r_icon.dart';
import '../../../ui/r_icons_data.dart';
import '../state/pairing_flow_controller.dart';
import 'qr_viewfinder.dart';

/// Scan screen Q03 and banner Q04. This subtree is always dark theme, because
/// the camera preview is dark in both themes (`design/components.md` C16).
///
/// Data and actions come from [pairingFlowProvider]. QR codes are read by the
/// flow controller via [qrScannerSourceProvider]; this widget only
/// shows the frame, hint, banner, and buttons.
final class ScanView extends ConsumerStatefulWidget {
  const ScanView({super.key});

  @override
  ConsumerState<ScanView> createState() => _ScanViewState();
}

final class _ScanViewState extends ConsumerState<ScanView> {
  Timer? _bannerTimer;

  @override
  void dispose() {
    _bannerTimer?.cancel();
    super.dispose();
  }

  /// Every wrong QR restarts the banner timer. After
  /// [RBehavior.qrErrorBanner] the banner is removed from state.
  void _startBannerTimer() {
    _bannerTimer?.cancel();
    _bannerTimer = Timer(RBehavior.qrErrorBanner, () {
      if (!mounted) return;
      ref.read(pairingFlowProvider.notifier).dismissQrError();
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(pairingFlowProvider.select((s) => s.qrErrorId), (prev, next) {
      if (next != prev && next > 0) _startBannerTimer();
    });

    final flow = ref.read(pairingFlowProvider.notifier);
    final errorId = ref.watch(pairingFlowProvider.select((s) => s.qrErrorId));
    final bannerShown = ref.watch(
      pairingFlowProvider.select((s) => s.qrError != null),
    );

    return Theme(
      data: AppTheme.dark,
      child: Builder(
        builder: (context) {
          final scheme = Theme.of(context).colorScheme;
          final frameColor = bannerShown
              ? context.accent.text
              : scheme.onSurface;

          return Stack(
            fit: StackFit.expand,
            children: [
              const QrViewfinder(),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: RSize.screenMarginCompact,
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          GlassKey(
                            semanticsLabel: PairingStrings.scanBack,
                            variant: GlassKeyVariant.glass,
                            size: GlassKeySize.touch,
                            onPressed: () {
                              flow.handleBack();
                            },
                            icon: RIcon(
                              RIcons.back,
                              size: RSpace.s5,
                              color: scheme.onSurface,
                            ),
                          ),
                          const QrTorchKey(),
                        ],
                      ),
                      Expanded(
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              QrViewfinderFrame(color: frameColor),
                              const SizedBox(height: RSpace.s6),
                              Text(
                                PairingStrings.scanHint,
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.bodyLarge
                                    ?.copyWith(color: scheme.onSurface),
                              ),
                              if (bannerShown) ...[
                                const SizedBox(height: RSpace.s4),
                                GlassToast(
                                  key: ValueKey(errorId),
                                  message: const ToastMessage(
                                    text: PairingStrings.scanInvalidBanner,
                                    variant: ToastVariant.error,
                                  ),
                                  onDismiss: _noop,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(
                          top: RSpace.s4,
                          bottom: RSpace.s8,
                        ),
                        child: GlassKey(
                          semanticsLabel: PairingStrings.manualLink,
                          label: PairingStrings.manualLink,
                          variant: GlassKeyVariant.glass,
                          size: GlassKeySize.control,
                          onPressed: () => flow.openManual(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

void _noop() {}
