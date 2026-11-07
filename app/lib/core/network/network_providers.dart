import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/pairing/data/mock_pairing_repository.dart';
import '../../features/pairing/data/pairing_repository.dart';
import '../connection/mock_status_repository.dart';
import '../connection/status_repository.dart';

/// Source of the pairing test. Defaults to mock until the HTTP implementation exists (Integration phase).
final pairingRepositoryProvider = Provider<PairingRepository>(
  (ref) => const MockPairingRepository(),
);

/// Source of `GET /status`. Defaults to mock: the laptop is always online.
final statusRepositoryProvider = Provider<StatusRepository>(
  (ref) => MockStatusRepository([
    mockStatusOk(),
  ], delay: const Duration(milliseconds: 300)),
);
