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
import 'widgets/media_dock.dart';
import 'widgets/offline_content.dart';
import 'widgets/remote_header.dart';

/// Widths below this use the compact margin (360 dp artboard).
const double _compactWidth = 380;

/// Remote screen SCR-010 (`design/components.md` C10, `States-light`).
///
/// Header, status panel, and the media dock. Power and volume controls
/// come later in M3-M4. Polling starts when the screen opens and stops when
/// the screen closes.
class RemoteScreen extends ConsumerStatefulWidget {
  const RemoteScreen({super.key});

  @override
  ConsumerState<RemoteScreen> createState() => _RemoteScreenState();
}

class _RemoteScreenState extends ConsumerState<RemoteScreen> {
  // Stored in initState so dispose does not use `ref`.
  late final ConnectionController _connection;
  late final ToastBottomInset _toastInset;
  bool _retrying = false;

  @override
  void initState() {
    super.initState();
    _connection = ref.read(connectionControllerProvider.notifier);
    _toastInset = ref.read(toastBottomInsetProvider.notifier);
    // start() changes a provider; Riverpod forbids that in initState. Run
    // after the first frame. If the screen was already closed, nothing starts.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _connection.start();
    });
  }

  @override
  void dispose() {
    _connection.stop();
    // dispose runs during the tree update, where Riverpod rejects provider
    // changes. The reset runs right after it.
    final toastInset = _toastInset;
    Future.microtask(() => toastInset.set(0));
    super.dispose();
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

  void _repair() => context.go(AppRoutes.pairing);

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
    final pairing = ref.watch(pairingProvider);
    final name = connection.status?.name ?? pairing?.laptopName ?? '';
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < _compactWidth;
    final margin = compact ? RSize.screenMarginCompact : RSize.screenMargin;
    final phase = connection.phase;
    final dockEnabled =
        phase == ConnectionPhase.online || phase == ConnectionPhase.back;
    // The dock sits above the screen's bottom padding (RSpace.s6), and
    // ToastHost measures from the screen bottom, so the inset includes it.
    _syncToastInset(MediaDock.heightFor(compact) + RSpace.s6);

    return Scaffold(
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
              const SizedBox(height: RSpace.s5),
              Expanded(
                child: GlassPanel(
                  padding: const EdgeInsets.all(RSpace.s5),
                  child: Center(child: _panelContent(phase)),
                ),
              ),
              const SizedBox(height: RSpace.s5),
              MediaDock(enabled: dockEnabled, compact: compact),
            ],
          ),
        ),
      ),
    );
  }

  Widget? _panelContent(ConnectionPhase phase) {
    switch (phase) {
      case ConnectionPhase.connecting:
        return Text(
          RemoteStrings.hintWaiting,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        );
      case ConnectionPhase.offline:
      case ConnectionPhase.poweredOff:
        return OfflineContent(
          onRetry: _retry,
          onRepair: _repair,
          retrying: _retrying,
          poweredOff: phase == ConnectionPhase.poweredOff,
        );
      case ConnectionPhase.online:
      case ConnectionPhase.back:
      case ConnectionPhase.tokenRejected:
        // The volume panel content does not exist yet in M1 (M3).
        return null;
    }
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
