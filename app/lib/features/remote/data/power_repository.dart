import '../../../core/network/agent_status.dart';
import '../../../core/network/api_failure.dart';

/// Power commands the agent accepts (`/power` endpoints, docs/api-spec.md).
enum PowerAction {
  sleep('sleep'),
  restart('restart'),
  shutdown('shutdown');

  const PowerAction(this.wire);

  /// Value of `action` in the `Pending` object and the endpoint path segment.
  final String wire;

  /// Returns the action for [wire], or null if the value is not known.
  static PowerAction? fromWire(String wire) {
    for (final action in values) {
      if (action.wire == wire) return action;
    }
    return null;
  }
}

/// Reads `data.cancelled` of `POST /power/cancel`. An unknown value is a
/// contract mismatch and throws [ServerFailure].
PowerAction parseCancelledAction(Map<String, Object?> data) {
  final raw = data['cancelled'];
  final action = raw is String ? PowerAction.fromWire(raw) : null;
  if (action == null) throw const ServerFailure();
  return action;
}

/// Reads `data.pending` of `POST /power/{action}` (202). A null or missing
/// value is a contract mismatch and throws [ServerFailure].
Pending parseScheduledPending(Map<String, Object?> data) {
  final raw = data['pending'];
  if (raw is! Map<String, Object?>) throw const ServerFailure();
  return Pending.fromData(raw);
}

/// Source of the power commands (`/power` endpoints, docs/api-spec.md).
///
/// Failure throws [ApiFailure] (see `api_failure.dart`). The 409 codes
/// `power_pending`, `no_pending_power`, and `power_executing` arrive in
/// [ApiFailure.code].
abstract interface class PowerRepository {
  /// `POST /power/{action}`. Returns the new schedule on 202.
  ///
  /// Not idempotent and never retried automatically: the agent acts on the
  /// laptop after the delay, so a second request could schedule a second
  /// command. The user decides whether to try again.
  Future<Pending> schedule(PowerAction action);

  /// `POST /power/cancel`. Returns the action that was cancelled on 200.
  ///
  /// Only the user may repeat this call. The state layer must not retry it.
  Future<PowerAction> cancel();
}
