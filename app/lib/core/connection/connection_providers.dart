import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'connection_controller.dart';
import 'connection_state.dart';

/// Connection status machine for SCR-010. Non-autoDispose.
final connectionControllerProvider =
    NotifierProvider<ConnectionController, ConnectionState>(
      ConnectionController.new,
    );

/// Last power command. Default null (none). Filled by the power feature (M4).
final lastPowerCommandProvider =
    NotifierProvider<LastPowerCommandNotifier, LastPowerCommand?>(
      LastPowerCommandNotifier.new,
    );

final class LastPowerCommandNotifier extends Notifier<LastPowerCommand?> {
  @override
  LastPowerCommand? build() => null;

  void record(LastPowerCommand command) => state = command;

  void clear() => state = null;
}

/// Polling timer scheduler. Replaced by a fake in tests.
final pollSchedulerProvider = Provider<PollScheduler>(
  (ref) => const TimerPollScheduler(),
);

/// Phone clock for comparing `sentAt` (phone clock, data-design §5).
final connectionClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);
