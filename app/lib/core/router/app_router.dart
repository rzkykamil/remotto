import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/pairing/pairing_screen.dart';
import '../../features/pairing/state/pairing_flow_controller.dart';
import '../../features/remote/remote_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../connection/connection_providers.dart';
import '../connection/connection_state.dart';
import '../storage/pairing_data.dart';
import '../storage/storage_providers.dart';
import 'route_transitions.dart';

abstract final class AppRoutes {
  /// Has no screen; only redirects to `/remote` or `/pairing`.
  static const home = '/';
  static const pairing = '/pairing';
  static const remote = '/remote';
  static const settings = '/settings';
}

/// Pure redirect based on whether pairing data exists.
///
/// `/pairing` may still be opened when data exists (re-pairing R04 and
/// recovery Q12 keep/delete the data then open `/pairing`).
String? redirectFor({required bool hasPairing, required String location}) {
  if (location == AppRoutes.home) {
    return hasPairing ? AppRoutes.remote : AppRoutes.pairing;
  }
  if (!hasPairing &&
      (location == AppRoutes.remote || location == AppRoutes.settings)) {
    return AppRoutes.pairing;
  }
  return null;
}

/// Notifies GoRouter whenever [pairingProvider] changes.
final class _PairingRefresh extends ChangeNotifier {
  void poke() => notifyListeners();
}

/// The stack root is `/remote` (system back exits the app). Settings is opened
/// via `push` from Remote, so back returns to Remote. `/pairing`
/// is also a root; internal back steps of pairing live in M1.
final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _PairingRefresh();
  ref.listen<PairingData?>(pairingProvider, (previous, next) => refresh.poke());

  final router = GoRouter(
    initialLocation: AppRoutes.home,
    refreshListenable: refresh,
    redirect: (context, state) => redirectFor(
      hasPairing: ref.read(pairingProvider) != null,
      location: state.uri.path,
    ),
    routes: [
      // Never shown: the global redirect always redirects `/`.
      GoRoute(path: AppRoutes.home, redirect: (context, state) => null),
      GoRoute(
        path: AppRoutes.pairing,
        name: 'pairing',
        pageBuilder: (context, state) =>
            appPage(context, state, const PairingScreen()),
      ),
      GoRoute(
        path: AppRoutes.remote,
        name: 'remote',
        pageBuilder: (context, state) =>
            appPage(context, state, const RemoteScreen()),
      ),
      GoRoute(
        path: AppRoutes.settings,
        name: 'settings',
        pageBuilder: (context, state) =>
            appPage(context, state, const SettingsScreen()),
      ),
    ],
  );

  // Token rejected from any screen (BR-9): stop polling, show
  // Q12, and make /pairing the stack root so back does not return to Remote.
  // Old pairing data is not deleted.
  ref.listen<ConnectionState>(connectionControllerProvider, (previous, next) {
    if (next.phase != ConnectionPhase.tokenRejected) return;
    if (previous?.phase == ConnectionPhase.tokenRejected) return;
    ref.read(connectionControllerProvider.notifier).stop();
    ref.read(pairingFlowProvider.notifier).showExpired();
    router.go(AppRoutes.pairing);
  });

  ref.onDispose(() {
    router.dispose();
    refresh.dispose();
  });
  return router;
});
