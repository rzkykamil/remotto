import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:remotto/core/network/network_providers.dart';
import 'package:remotto/core/storage/storage_providers.dart';
import 'package:remotto/features/remote/data/http_power_repository.dart';
import 'package:remotto/features/remote/data/power_repository.dart';
import 'package:remotto/features/remote/power/power_flow_controller.dart';
import 'package:remotto/features/remote/power/power_flow_state.dart';

/// Source of the power commands (`/power` endpoints on the paired laptop).
/// Tests override it with a fake.
final powerRepositoryProvider = Provider<PowerRepository>(
  (ref) => HttpPowerRepository(
    ref.watch(agentHttpClientProvider),
    () => ref.read(pairingProvider),
  ),
);

/// State and commands of the power flow. Non-autoDispose: the countdown
/// survives screen changes.
final powerFlowControllerProvider =
    NotifierProvider<PowerFlowController, PowerFlowState>(
      PowerFlowController.new,
    );
