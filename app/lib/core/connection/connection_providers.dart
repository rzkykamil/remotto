import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/storage_providers.dart';
import '../theme/r_behavior.dart';
import 'connection_controller.dart';
import 'connection_state.dart';

/// Connection status machine for SCR-010. Non-autoDispose.
final connectionControllerProvider =
    NotifierProvider<ConnectionController, ConnectionState>(
      ConnectionController.new,
    );

/// Last power command, persisted in preferences (data-design §5, FR-4.8a).
/// Null when none, when the stored value is broken, or when it is older than
/// [RBehavior.lastPowerCommandTtl].
final lastPowerCommandProvider =
    NotifierProvider<LastPowerCommandNotifier, LastPowerCommand?>(
      LastPowerCommandNotifier.new,
    );

final class LastPowerCommandNotifier extends Notifier<LastPowerCommand?> {
  @override
  LastPowerCommand? build() {
    final prefs = ref.read(appPreferencesProvider);
    final saved = prefs.readLastPowerCommand();
    if (saved == null) return null;

    // Phone clock, compared only with the phone clock (data-design §5).
    final elapsed = ref
        .read(connectionClockProvider)()
        .difference(saved.sentAt);
    // A future sentAt (clock was moved back) is treated as invalid.
    if (elapsed.isNegative || elapsed > RBehavior.lastPowerCommandTtl) {
      unawaited(prefs.clearLastPowerCommand());
      return null;
    }
    return saved;
  }

  void record(LastPowerCommand command) {
    state = command;
    unawaited(ref.read(appPreferencesProvider).writeLastPowerCommand(command));
  }

  void clear() {
    state = null;
    unawaited(ref.read(appPreferencesProvider).clearLastPowerCommand());
  }
}

/// Polling timer scheduler. Replaced by a fake in tests.
final pollSchedulerProvider = Provider<PollScheduler>(
  (ref) => const TimerPollScheduler(),
);

/// Phone clock for comparing `sentAt` (phone clock, data-design §5).
final connectionClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);
