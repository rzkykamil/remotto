import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotto/core/discovery/discovery_providers.dart';
import 'package:remotto/core/discovery/endpoint_resolver.dart';
import 'package:remotto/core/discovery/network_change_source.dart';
import 'package:remotto/core/discovery/nsd_agent_discovery.dart';

/// Production path evidence: without overrides, the discovery providers use
/// the real implementations (nsd and connectivity_plus), not fakes.
///
/// The test only reads the providers and checks runtime types. `find` and
/// `changes` are never called because they touch mDNS and platform channels.
void main() {
  test('production discovery providers use the real implementations', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(agentDiscoveryProvider), isA<NsdAgentDiscovery>());
    // Creating `Connectivity()` does not call the platform channel; the
    // channel is only used when `changes` or `onLocalNetwork` is accessed,
    // and this test never accesses them.
    expect(
      container.read(networkChangeSourceProvider),
      isA<ConnectivityNetworkChangeSource>(),
    );
    expect(container.read(endpointResolverProvider), isA<EndpointResolver>());
  });
}
