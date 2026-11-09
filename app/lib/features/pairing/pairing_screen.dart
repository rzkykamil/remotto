import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'state/pairing_flow_controller.dart';
import 'state/pairing_flow_state.dart';
import 'widgets/intro_view.dart';
import 'widgets/manual_view.dart';
import 'widgets/permission_blocked_view.dart';
import 'widgets/permission_view.dart';
import 'widgets/result_views.dart';
import 'widgets/scan_view.dart';
import 'widgets/testing_view.dart';

/// Route `/pairing`. One screen with internal steps (see [PairingStep]).
/// The back button goes back one step; at Q01 back exits the app.
class PairingScreen extends ConsumerStatefulWidget {
  const PairingScreen({super.key});

  @override
  ConsumerState<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends ConsumerState<PairingScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(ref.read(pairingFlowProvider.notifier).onResumed());
    }
  }

  @override
  Widget build(BuildContext context) {
    final step = ref.watch(pairingFlowProvider).step;
    final flow = ref.read(pairingFlowProvider.notifier);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (!flow.handleBack()) {
          unawaited(SystemNavigator.pop());
        }
      },
      child: _stepView(step, flow),
    );
  }

  Widget _stepView(PairingStep step, PairingFlowController flow) {
    switch (step) {
      case PairingStep.intro:
        return IntroView(
          onScan: flow.onScanPressed,
          onManual: () => flow.openManual(),
        );
      case PairingStep.permission:
        return PermissionView(
          onAllow: flow.requestCamera,
          onManual: () => flow.openManual(),
        );
      case PairingStep.scan:
        return const ScanView();
      case PairingStep.permissionBlocked:
        return PermissionBlockedView(
          onOpenSettings: flow.openAppSettings,
          onManual: () => flow.openManual(),
        );
      case PairingStep.manual:
        return const ManualView();
      case PairingStep.testing:
        return TestingView(
          address:
              '${ref.watch(pairingFlowProvider).target?.host}:${ref.watch(pairingFlowProvider).target?.port}',
          activeStep: ref.watch(pairingFlowProvider).testStep.index,
          onCancel: flow.cancelTest,
        );
      case PairingStep.success:
        return SuccessView(
          laptopName: ref.watch(pairingFlowProvider).laptopName ?? '',
        );
      case PairingStep.timeout:
        return TimeoutView(
          address:
              '${ref.watch(pairingFlowProvider).target?.host}:${ref.watch(pairingFlowProvider).target?.port}',
          onRetry: flow.retryTest,
          onChangeAddress: flow.editAddress,
        );
      case PairingStep.rejected:
        return RejectedView(
          onRescan: flow.onScanPressed,
          onManual: () => flow.openManual(),
        );
      case PairingStep.expired:
        return ExpiredView(
          laptopName: ref.watch(pairingFlowProvider).laptopName ?? '',
          onRescan: flow.onScanPressed,
          onManual: () => flow.openManual(),
        );
    }
  }
}
