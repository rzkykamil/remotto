import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'agent_discovery.dart';
import 'endpoint_resolver.dart';
import 'network_change_source.dart';
import 'nsd_agent_discovery.dart';

/// mDNS discovery. Replaced by a fake in tests.
final agentDiscoveryProvider = Provider<AgentDiscovery>(
  (ref) => const NsdAgentDiscovery(),
);

/// Connectivity events. Replaced by a fake in tests.
final networkChangeSourceProvider = Provider<NetworkChangeSource>(
  (ref) => ConnectivityNetworkChangeSource(),
);

/// Rediscovery of the paired laptop's endpoint (D6). Tests override the
/// discovery, HTTP client, clock and storage it reads.
final endpointResolverProvider = Provider<EndpointResolver>(
  (ref) => EndpointResolver(ref),
);
