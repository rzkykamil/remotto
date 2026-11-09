import 'dart:async';

import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/connection/connection_controller.dart';
import '../../core/connection/connection_providers.dart';
import '../../core/connection/connection_state.dart';
import '../../core/router/app_router.dart';
import '../../core/storage/storage_providers.dart';
import '../../core/strings/remote_strings.dart';
import '../../core/strings/uptime_format.dart';
import '../../core/theme/tokens.g.dart';
import '../../core/toast/toast_controller.dart';
import '../../ui/glass_panel.dart';
import '../../ui/status_pill.dart';
import '../settings/widgets/repair_confirm.dart';
import 'power/power_flow_host.dart';
import 'power/power_flow_state.dart';
import 'power/power_providers.dart';
import 'widgets/media_dock.dart';
import 'widgets/power_row.dart';
import 'widgets/remote_header.dart';
import 'widgets/volume_panel.dart';

/// Widths below this use the compact margin (360 dp artboard).
const double _compactWidth = 380;

/// Remote screen SCR-010 (`design/components.md` C10, `States-light`).
///
/// Header, the power row (C09), the volume panel, and the media dock. The
/// power flow (confirm sheet, countdown, result) runs in [PowerFlowHost]
/// above this screen. Polling starts when the screen opens and stops when
/// the screen closes.
class RemoteScreen extends ConsumerStatefulWidget {
  const RemoteScreen({super.key});

  @override
  ConsumerState<RemoteScreen> createState() => _RemoteScreenState();
}

class _RemoteScreenState extends ConsumerState<RemoteScreen>
    with WidgetsBindingObserver {
  // Stored in initState so dispose does not use `ref`.
  late final ConnectionController _connection;
  late final ToastBottomInset _toastInset;
  bool _retrying = false;

  @override
  void initState() {
    super.initState();
    _connection = ref.read(connectionControllerProvider.notifier);
    _toastInset = ref.read(toastBottomInsetProvider.notifier);
    WidgetsBinding.instance.addObserver(this);
    // start() changes a provider; Riverpod forbids that in initState. Run
    // after the first frame. If the screen was already closed, nothing starts.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _connection.start();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connection.stop();
    // dispose runs during the tree update, where Riverpod rejects provider
    // changes. The reset runs right after it.
    final toastInset = _toastInset;
    Future.microtask(() => toastInset.set(0));
    super.dispose();
  }

  /// Polling stops in the background (FR-6.6) and restarts on return. inactive
  /// and hidden are ignored: a notification shade or system dialog must not
  /// stop polling.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _connection.pause();
      case AppLifecycleState.resumed:
        _connection.resume();
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        break;
    }
  }

  /// Lifts toasts above the dock. Changing a provider is not allowed during
  /// build, so the update runs after the frame.
  void _syncToastInset(double height) {
    if (ref.read(toastBottomInsetProvider) == height) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _toastInset.set(height);
    });
  }

  void _retry() {
    if (_retrying) return;
    setState(() => _retrying = true);
    unawaited(
      _connection.pollOnce().whenComplete(() {
        if (mounted) setState(() => _retrying = false);
      }),
    );
  }

  /// Pairing ulang dari offline (C08 → C22 → Q01). Nama laptop dari status,
  /// atau dari data pairing bila status belum ada.
  void _repair() {
    final name =
        ref.read(connectionControllerProvider).status?.name ??
        ref.read(pairingProvider)?.laptopName ??
        '';
    unawaited(runRepairFlow(context, ref, laptopName: name));
  }

  @override
  Widget build(BuildContext context) {
    // S11: offline then reconnected -> brief info toast with no action.
    ref.listen<ConnectionState>(connectionControllerProvider, (previous, next) {
      final was = previous?.phase;
      final back = next.phase == ConnectionPhase.back;
      final fromOffline =
          was == ConnectionPhase.offline || was == ConnectionPhase.poweredOff;
      if (back && fromOffline) {
        ref
            .read(toastControllerProvider.notifier)
            .show(const ToastMessage(text: RemoteStrings.toastBackOnline));
      }
    });

    final connection = ref.watch(connectionControllerProvider);
    final lastPowerCommand = ref.watch(lastPowerCommandProvider);
    final pairing = ref.watch(pairingProvider);
    final name = connection.status?.name ?? pairing?.laptopName ?? '';
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < _compactWidth;
    final margin = compact ? RSize.screenMarginCompact : RSize.screenMargin;
    final phase = connection.phase;
    final dockEnabled =
        phase == ConnectionPhase.online || phase == ConnectionPhase.back;
    // Power keys need a live laptop and no flow already running (one schedule
    // at a time, BR-5). Rebuilds only when the idle state changes, not on
    // every countdown tick.
    final powerIdle = ref.watch(
      powerFlowControllerProvider.select((state) => state is PowerFlowIdle),
    );
    final powerEnabled = dockEnabled && powerIdle;
    // The dock sits above the screen's bottom padding (RSpace.s6), and
    // ToastHost measures from the screen bottom, so the inset includes it.
    // The power row sits above the volume panel, so the dock height is the
    // same as before.
    _syncToastInset(MediaDock.heightFor(compact) + RSpace.s6);

    return PowerFlowHost(
      builder: (context, onPowerSelected) => Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(margin, RSpace.s4, margin, RSpace.s6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                RemoteHeader(
                  laptopName: name,
                  pillVariant: _pillVariant(phase),
                  pillLabel: _pillLabel(phase, connection.uptime),
                  pillSemanticsLabel: _pillSemantics(phase),
                  onSettings: () => context.push(AppRoutes.settings),
                ),
                const SizedBox(height: RSpace.s6),
                Semantics(
                  container: true,
                  label: RemoteStrings.powerGroupLabel,
                  child: PowerRow(
                    enabled: powerEnabled,
                    onSelected: onPowerSelected,
                  ),
                ),
                const SizedBox(height: RSpace.s5),
                Expanded(
                  child: GlassPanel(
                    padding: const EdgeInsets.all(RSpace.s5),
                    semanticsLabel: RemoteStrings.volumeGroupLabel,
                    child: VolumePanel(
                      phase: phase,
                      onRetry: _retry,
                      onRepair: _repair,
                      retrying: _retrying,
                      compact: compact,
                      lastCommand: lastPowerCommand,
                    ),
                  ),
                ),
                const SizedBox(height: RSpace.s5),
                MediaDock(enabled: dockEnabled, compact: compact),
              ],
            ),
          ),
        ),
      ),
    );
  }

  StatusPillVariant _pillVariant(ConnectionPhase phase) => switch (phase) {
    ConnectionPhase.connecting => StatusPillVariant.connecting,
    ConnectionPhase.online => StatusPillVariant.online,
    ConnectionPhase.back => StatusPillVariant.back,
    ConnectionPhase.offline => StatusPillVariant.offline,
    ConnectionPhase.poweredOff => StatusPillVariant.off,
    ConnectionPhase.tokenRejected => StatusPillVariant.offline,
  };

  String _pillLabel(ConnectionPhase phase, Duration? uptime) => switch (phase) {
    ConnectionPhase.connecting => RemoteStrings.pillConnecting,
    ConnectionPhase.online => RemoteStrings.pillOnline(
      formatUptime(uptime ?? Duration.zero),
    ),
    ConnectionPhase.back => RemoteStrings.pillBack,
    ConnectionPhase.offline => RemoteStrings.pillOffline,
    ConnectionPhase.poweredOff => RemoteStrings.pillOff,
    ConnectionPhase.tokenRejected => RemoteStrings.pillOffline,
  };

  String _pillSemantics(ConnectionPhase phase) => switch (phase) {
    ConnectionPhase.connecting => RemoteStrings.pillConnectingA11y,
    ConnectionPhase.online => RemoteStrings.pillOnlineA11y,
    ConnectionPhase.back => RemoteStrings.pillBackA11y,
    ConnectionPhase.offline => RemoteStrings.pillOfflineA11y,
    ConnectionPhase.poweredOff => RemoteStrings.pillOffA11y,
    ConnectionPhase.tokenRejected => RemoteStrings.pillOfflineA11y,
  };
}
