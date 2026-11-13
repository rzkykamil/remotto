import 'package:connectivity_plus/connectivity_plus.dart';

/// Source of network change events that may mean the laptop's IP moved.
abstract interface class NetworkChangeSource {
  /// Emits on every connectivity change. Consumers debounce it themselves.
  Stream<void> get changes;

  /// True when the phone is currently on Wi-Fi or Ethernet (D6 point 5).
  Future<bool> get onLocalNetwork;
}

/// True when [results] include Wi-Fi or Ethernet.
bool isLocalNetwork(List<ConnectivityResult> results) =>
    results.contains(ConnectivityResult.wifi) ||
    results.contains(ConnectivityResult.ethernet);

/// [NetworkChangeSource] backed by `connectivity_plus`.
final class ConnectivityNetworkChangeSource implements NetworkChangeSource {
  ConnectivityNetworkChangeSource({Connectivity? connectivity})
    : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  @override
  Stream<void> get changes => _connectivity.onConnectivityChanged.map((_) {});

  @override
  Future<bool> get onLocalNetwork async {
    try {
      return isLocalNetwork(await _connectivity.checkConnectivity());
    } on Object {
      return false;
    }
  }
}
