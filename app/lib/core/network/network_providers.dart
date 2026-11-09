import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/io_client.dart';

import '../../features/pairing/data/http_pairing_repository.dart';
import '../../features/pairing/data/pairing_repository.dart';
import '../connection/http_status_repository.dart';
import '../connection/status_repository.dart';
import '../storage/storage_providers.dart';
import '../theme/r_behavior.dart';
import 'agent_http_client.dart';

/// Shared HTTP client for the agent. Closed when the provider scope is disposed.
/// Tests override this with an `AgentHttpClient` built on `MockClient`.
final agentHttpClientProvider = Provider<AgentHttpClient>((ref) {
  final client = IOClient(
    HttpClient()..connectionTimeout = RBehavior.stepTimeout,
  );
  ref.onDispose(client.close);
  return AgentHttpClient(client);
});

/// Source of the pairing test (HTTP to the agent).
final pairingRepositoryProvider = Provider<PairingRepository>(
  (ref) => HttpPairingRepository(ref.watch(agentHttpClientProvider)),
);

/// Source of `GET /status` (HTTP to the paired laptop).
final statusRepositoryProvider = Provider<StatusRepository>(
  (ref) => HttpStatusRepository(
    ref.watch(agentHttpClientProvider),
    () => ref.read(pairingProvider),
  ),
);
