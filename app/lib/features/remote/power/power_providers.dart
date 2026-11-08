import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:remotto/features/remote/data/power_repository.dart';
import 'package:remotto/features/remote/power/power_flow_controller.dart';
import 'package:remotto/features/remote/power/power_flow_state.dart';

/// Source of the power commands. No default: the HTTP implementation is wired
/// in the integration phase, and tests override it with a fake.
final powerRepositoryProvider = Provider<PowerRepository>(
  (ref) => throw UnimplementedError('override powerRepositoryProvider'),
);

/// State and commands of the power flow. Non-autoDispose: the countdown
/// survives screen changes.
final powerFlowControllerProvider =
    NotifierProvider<PowerFlowController, PowerFlowState>(
      PowerFlowController.new,
    );
