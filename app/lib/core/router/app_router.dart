import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/pairing/pairing_screen.dart';
import '../../features/remote/remote_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../storage/pairing_data.dart';
import '../storage/storage_providers.dart';
import 'route_transitions.dart';

abstract final class AppRoutes {
  /// Tidak punya layar; hanya redirect ke `/remote` atau `/pairing`.
  static const home = '/';
  static const pairing = '/pairing';
  static const remote = '/remote';
  static const settings = '/settings';
}

/// Redirect murni berdasarkan ada tidaknya data pairing.
///
/// `/pairing` tetap boleh dibuka saat data ada (pairing ulang R04 dan
/// pemulihan Q12 mempertahankan/menghapus data lalu membuka `/pairing`).
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

/// Memberi tahu GoRouter setiap kali [pairingProvider] berubah.
final class _PairingRefresh extends ChangeNotifier {
  void poke() => notifyListeners();
}

/// Akar stack adalah `/remote` (back sistem keluar app). Pengaturan dibuka
/// lewat `push` dari Remote, sehingga back kembali ke Remote. `/pairing`
/// juga akar; langkah mundur internal pairing ada di M1.
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
      // Tidak pernah tampil: redirect global selalu mengalihkan `/`.
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

  ref.onDispose(() {
    router.dispose();
    refresh.dispose();
  });
  return router;
});
