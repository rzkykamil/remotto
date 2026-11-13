import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../discovery/discovery_providers.dart';
import '../discovery/endpoint_resolver.dart';
import '../discovery/network_change_source.dart';
import '../network/agent_status.dart';
import '../network/api_failure.dart';
import '../network/network_providers.dart';
import '../storage/storage_providers.dart';
import '../theme/r_behavior.dart';
import '../theme/tokens.g.dart';
import 'connection_providers.dart';
import 'connection_state.dart';
import 'status_repository.dart';

/// One scheduled job. [cancel] is safe to call repeatedly or after the job finished.
abstract interface class ScheduledJob {
  void cancel();
}

/// Time scheduler. Replaced by a fake in tests so they do not wait on real time.
abstract interface class PollScheduler {
  /// Run [tick] repeatedly every [interval].
  ScheduledJob every(Duration interval, void Function() tick);

  /// Run [callback] once after [delay].
  ScheduledJob after(Duration delay, void Function() callback);
}

/// Real implementation using [Timer] from dart:async.
final class TimerPollScheduler implements PollScheduler {
  const TimerPollScheduler();

  @override
  ScheduledJob every(Duration interval, void Function() tick) =>
      _TimerJob(Timer.periodic(interval, (_) => tick()));

  @override
  ScheduledJob after(Duration delay, void Function() callback) =>
      _TimerJob(Timer(delay, callback));
}

final class _TimerJob implements ScheduledJob {
  _TimerJob(this._timer);

  final Timer _timer;

  @override
  void cancel() => _timer.cancel();
}

/// The poll in flight. [settled] prevents duplicate or stale results.
final class _InFlightPoll {
  final Completer<void> done = Completer<void>();
  bool settled = false;
  ScheduledJob? timeout;
}

/// Connection status machine for SCR-010 (technical-spec §5, BR-8, BR-9, BR-21).
///
/// Non-autoDispose: state survives screen changes. [start] and [stop]
/// are called from SCR-010.
final class ConnectionController extends Notifier<ConnectionState> {
  /// Timeout for a regular poll. Source: `RMotion.commandTimeout` from
  /// `design/tokens.json` (technical-spec §6).
  static const Duration _pollTimeout = RMotion.commandTimeout;

  late StatusRepository _repository;
  late PollScheduler _scheduler;
  late DateTime Function() _now;
  late EndpointResolver _resolver;
  late NetworkChangeSource _networkChanges;

  bool _running = false;
  bool _fast = false;
  int _failures = 0;
  ScheduledJob? _pollJob;
  ScheduledJob? _phaseJob;
  _InFlightPoll? _inFlight;
  StreamSubscription<void>? _networkSub;
  ScheduledJob? _networkDebounce;

  @override
  ConnectionState build() {
    _repository = ref.read(statusRepositoryProvider);
    _scheduler = ref.read(pollSchedulerProvider);
    _now = ref.read(connectionClockProvider);
    _resolver = ref.read(endpointResolverProvider);
    _networkChanges = ref.read(networkChangeSourceProvider);
    ref.onDispose(_halt);
    return const ConnectionState(phase: ConnectionPhase.connecting);
  }

  /// Start polling from SCR-010. The first poll runs immediately with a
  /// 2 second timeout (BR-21). If already running: does nothing.
  void start() {
    if (_running) return;
    _running = true;
    _failures = 0;
    _setPhase(ConnectionPhase.connecting);
    _schedulePoll();
    _subscribeNetwork();
    unawaited(_poll(timeout: RBehavior.resumeWait));
  }

  /// Stop polling, called when SCR-010 closes. The phase is not changed.
  /// Also resets the fast poll so the next start uses the normal interval.
  void stop() {
    _fast = false;
    _halt();
  }

  /// Stop polling while the app is in the background (FR-6.6). Unlike [stop],
  /// the fast poll flag is kept, so [resume] restores the same interval.
  /// The phase is not changed.
  void pause() => _halt();

  /// Poll again after the app returns to the foreground (FR-6.6, BR-21).
  /// Does nothing while the token is rejected; the router handles that state.
  void resume() {
    if (state.phase == ConnectionPhase.tokenRejected) return;
    start();
  }

  /// One manual poll, e.g. the "Coba lagi" button. Waits for the poll in
  /// flight if any. Does not run while the token is rejected.
  Future<void> pollOnce() {
    if (state.phase == ConnectionPhase.tokenRejected) return Future.value();
    return _poll(timeout: _pollTimeout);
  }

  /// Called when another request (e.g. a command) receives 401 (BR-9).
  void reportUnauthorized() => _enterTokenRejected();

  /// Poll every 2 seconds when a restart was sent, 5 seconds otherwise.
  void setFastPoll({required bool enabled}) {
    if (_fast == enabled) return;
    _fast = enabled;
    if (_running) _schedulePoll();
  }

  void _schedulePoll() {
    _pollJob?.cancel();
    final interval = _fast ? RBehavior.fastPoll : RMotion.poll;
    _pollJob = _scheduler.every(
      interval,
      () => unawaited(_poll(timeout: _pollTimeout)),
    );
  }

  /// One poll. If one is already running, return the same future.
  Future<void> _poll({required Duration timeout}) {
    final running = _inFlight;
    if (running != null) return running.done.future;

    final poll = _InFlightPoll();
    _inFlight = poll;
    poll.timeout = _scheduler.after(
      timeout,
      () => _finish(poll, error: const TimeoutFailure()),
    );
    unawaited(
      _repository.fetchStatus().then<void>(
        (status) => _finish(poll, status: status),
        onError: (Object error, StackTrace _) => _finish(poll, error: error),
      ),
    );
    return poll.done.future;
  }

  void _finish(_InFlightPoll poll, {AgentStatus? status, Object? error}) {
    if (poll.settled) return;
    poll.settled = true;
    poll.timeout?.cancel();
    if (identical(_inFlight, poll)) _inFlight = null;

    if (status != null) {
      _onSuccess(status);
    } else {
      _onFailure(error);
    }
    poll.done.complete();
  }

  void _onSuccess(AgentStatus status) {
    _failures = 0;
    _backfillAgentId(status.agentId);
    final previous = state.status;
    // Null volume means Core Audio failed; the last value is kept.
    final merged = AgentStatus(
      name: status.name,
      version: status.version,
      uptimeSeconds: status.uptimeSeconds,
      volume: status.volume ?? previous?.volume,
      pending: status.pending,
      agentId: status.agentId,
    );

    switch (state.phase) {
      case ConnectionPhase.connecting:
      case ConnectionPhase.online:
        _setPhase(ConnectionPhase.online, status: merged);
      case ConnectionPhase.offline:
      case ConnectionPhase.poweredOff:
        _setPhase(ConnectionPhase.back, status: merged);
        ref.read(lastPowerCommandProvider.notifier).clear();
        // Reconnected: back to the normal interval (FR-4.12).
        _fast = false;
        if (_running) _schedulePoll();
        _phaseJob = _scheduler.after(RBehavior.reconnectedPill, () {
          if (state.phase == ConnectionPhase.back) {
            _setPhase(ConnectionPhase.online);
          }
        });
      case ConnectionPhase.back:
        // The 2 second timer is already running; just update the status.
        _emit(ConnectionPhase.back, merged);
      case ConnectionPhase.tokenRejected:
        // Polling stopped when the token was rejected; stale result is ignored.
        break;
    }
  }

  void _onFailure(Object? error) {
    if (error is UnauthorizedFailure) {
      _enterTokenRejected();
      return;
    }
    _failures++;

    switch (state.phase) {
      case ConnectionPhase.connecting:
      case ConnectionPhase.online:
      case ConnectionPhase.back:
        if (_failures >= RComponent.offlineAfterFailures) _goOffline();
      case ConnectionPhase.offline:
      case ConnectionPhase.poweredOff:
      case ConnectionPhase.tokenRejected:
        break;
    }
    _triggerRediscover(force: false);
  }

  /// Saves the agentId of a pairing made before M7 (D2 backfill). The token
  /// already authenticated this answer, so the id is taken once.
  void _backfillAgentId(String? agentId) {
    if (agentId == null) return;
    final pairing = ref.read(pairingProvider);
    if (pairing == null || pairing.agentId != null) return;
    unawaited(ref.read(pairingProvider.notifier).backfillAgentId(agentId));
  }

  /// Rediscovery runs beside the poll, never in front of it (D6). The poll
  /// keeps its own schedule and timeout; the result is handled when it comes.
  void _triggerRediscover({required bool force}) {
    if (!_running || state.phase == ConnectionPhase.tokenRejected) return;
    unawaited(_resolver.rediscover(force: force).then(_onRediscovered));
  }

  void _onRediscovered(RediscoverResult result) {
    switch (result) {
      case RediscoverResult.none:
        break;
      case RediscoverResult.tokenRejected:
        _enterTokenRejected();
      case RediscoverResult.updated:
        // The endpoint is already saved; only poll when still running.
        if (!_running) break;
        _failures = 0;
        unawaited(_poll(timeout: _pollTimeout));
    }
  }

  void _subscribeNetwork() {
    _networkSub ??= _networkChanges.changes.listen((_) => _onNetworkChanged());
  }

  void _unsubscribeNetwork() {
    _networkSub?.cancel();
    _networkSub = null;
    _networkDebounce?.cancel();
    _networkDebounce = null;
  }

  /// Debounced on the poll scheduler so tests can fire it with the fake timer.
  void _onNetworkChanged() {
    _networkDebounce?.cancel();
    _networkDebounce = _scheduler.after(RBehavior.networkChangeDebounce, () {
      _networkDebounce = null;
      unawaited(_handleNetworkChange());
    });
  }

  /// Wi-Fi or Ethernet only (D6 point 5). Forced rediscovery, then a poll
  /// unless the rediscovery already polled or the token was rejected.
  Future<void> _handleNetworkChange() async {
    if (!_running) return;
    if (!await _networkChanges.onLocalNetwork) return;
    if (!_running) return;
    final result = await _resolver.rediscover(force: true);
    _onRediscovered(result);
    if (_running && result == RediscoverResult.none) {
      unawaited(_poll(timeout: _pollTimeout));
    }
  }

  /// Plain offline, or poweredOff when the power command is still recent (P15).
  /// A restart never gives P15: the laptop comes back on its own (FR-4.11).
  void _goOffline() {
    final command = ref.read(lastPowerCommandProvider);
    if (command != null && command.action != 'restart') {
      final elapsed = _now().difference(command.sentAt);
      final clamped = elapsed.isNegative ? Duration.zero : elapsed;
      final remaining = RBehavior.lastPowerCommandTtl - clamped;
      if (remaining > Duration.zero) {
        _setPhase(ConnectionPhase.poweredOff);
        _phaseJob = _scheduler.after(remaining, () {
          if (state.phase == ConnectionPhase.poweredOff) {
            _setPhase(ConnectionPhase.offline);
          }
        });
        return;
      }
    }
    _setPhase(ConnectionPhase.offline);
  }

  void _enterTokenRejected() {
    _halt();
    _setPhase(ConnectionPhase.tokenRejected);
  }

  /// Stops the schedule and cancels the poll in flight.
  void _halt() {
    _running = false;
    _pollJob?.cancel();
    _pollJob = null;
    _phaseJob?.cancel();
    _phaseJob = null;
    _unsubscribeNetwork();
    final running = _inFlight;
    if (running != null) {
      running.settled = true;
      running.timeout?.cancel();
      _inFlight = null;
      running.done.complete();
    }
  }

  /// Changes the phase and cancels the previous phase timer.
  void _setPhase(ConnectionPhase phase, {AgentStatus? status}) {
    _phaseJob?.cancel();
    _phaseJob = null;
    _emit(phase, status);
  }

  void _emit(ConnectionPhase phase, [AgentStatus? status]) {
    state = ConnectionState(phase: phase, status: status ?? state.status);
  }
}
