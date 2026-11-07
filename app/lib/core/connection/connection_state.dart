import '../network/agent_status.dart';

/// Connection machine phase (technical-spec §5).
enum ConnectionPhase {
  /// Just opened, no successful poll yet.
  connecting,

  /// Last poll succeeded, or failed once.
  online,

  /// 2 consecutive failed polls (BR-8).
  offline,

  /// Status succeeded again after offline. Returns to online after 2 seconds.
  back,

  /// Offline with the last power command less than 10 minutes ago (P15).
  poweredOff,

  /// 401 from the agent. App goes back to pairing (Q12, BR-9).
  tokenRejected,
}

/// Last power command from the phone (data-design §5). `sentAt` uses the phone clock.
final class LastPowerCommand {
  const LastPowerCommand({required this.action, required this.sentAt});

  /// `sleep`, `restart`, or `shutdown`.
  final String action;
  final DateTime sentAt;

  @override
  bool operator ==(Object other) =>
      other is LastPowerCommand &&
      other.action == action &&
      other.sentAt == sentAt;

  @override
  int get hashCode => Object.hash(action, sentAt);

  @override
  String toString() => 'LastPowerCommand(action: $action, sentAt: $sentAt)';
}

/// Connection state read by the UI (SCR-010).
final class ConnectionState {
  const ConnectionState({required this.phase, this.status});

  final ConnectionPhase phase;

  /// Last status read successfully. A null volume in the response does not
  /// erase the previous value. Null if never succeeded.
  final AgentStatus? status;

  /// Laptop uptime from the last status. Null if never succeeded.
  Duration? get uptime {
    final current = status;
    return current == null ? null : Duration(seconds: current.uptimeSeconds);
  }

  @override
  bool operator ==(Object other) =>
      other is ConnectionState &&
      other.phase == phase &&
      other.status == status;

  @override
  int get hashCode => Object.hash(phase, status);

  @override
  String toString() => 'ConnectionState(phase: $phase, status: $status)';
}
