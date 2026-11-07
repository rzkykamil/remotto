import 'dart:async';

import '../../../core/connection/connection_controller.dart';
import '../../../core/network/api_failure.dart';
import '../../../core/theme/tokens.g.dart';

/// Sends slider levels to the agent, one request at a time (BR-14).
///
/// Rules:
/// - At most one [send] runs at a time.
/// - [submit] keeps only the latest level. It is sent at once when no request
///   is running and [throttle] has passed since the last send started,
///   otherwise it waits for the throttle timer.
/// - [finish] always sends the final level after the running request, without
///   throttle. It is skipped when the level equals the last successful send.
/// - A failure (timeout or [ApiFailure] other than [UnauthorizedFailure]) is
///   retried once silently. A second failure calls [onFailed] once and drops
///   the pending level. [UnauthorizedFailure] is not retried.
/// - [onIdle] is called once after everything settles, following at least one
///   send.
///
/// Pure logic: timing goes through [PollScheduler], so tests need no real time.
final class VolumeSender {
  VolumeSender({
    required this.scheduler,
    required this.send,
    required this.onFailed,
    required this.onIdle,
    this.throttle = RMotion.sendThrottle,
    this.timeout = RMotion.commandTimeout,
  });

  final PollScheduler scheduler;
  final Future<void> Function(int level) send;
  final void Function(int level) onFailed;
  final void Function() onIdle;

  /// Minimum gap between the starts of two sends.
  final Duration throttle;

  /// Upper bound for one request attempt.
  final Duration timeout;

  int? _pending;
  bool _final = false;
  bool _inFlight = false;
  bool _cooling = false;
  bool _idleOwed = false;
  bool _disposed = false;

  /// Bumped by [cancelPending]. A run started under an older generation has
  /// its result discarded.
  int _generation = 0;
  int? _lastSucceeded;
  ScheduledJob? _cooldownJob;

  /// True while a request runs or a level waits to be sent.
  bool get busy => _inFlight || _pending != null;

  /// Tells the sender which level the laptop already has, so [finish] skips a
  /// send of that same level. Pass null when unknown or muted: a level command
  /// also unmutes (BR-15), so it must still be sent.
  void setConfirmed(int? level) {
    _lastSucceeded = level;
  }

  /// Queues [level] as the newest value to send (drag update).
  void submit(int level) {
    if (_disposed) return;
    _pending = level;
    _flush();
  }

  /// Queues [level] as the final value (drag end or tap).
  void finish(int level) {
    if (_disposed) return;
    _pending = level;
    _final = true;
    _flush();
  }

  /// Drops the queued level. A request already running is not stopped, but its
  /// result is ignored: no retry, no [onFailed], and [setConfirmed] is not
  /// advanced by it.
  void cancelPending() {
    if (_disposed) return;
    _pending = null;
    _final = false;
    _generation++;
    _checkIdle();
  }

  void dispose() {
    _disposed = true;
    _pending = null;
    _final = false;
    _cooldownJob?.cancel();
    _cooldownJob = null;
  }

  void _flush() {
    if (_disposed) return;
    final level = _pending;
    if (_inFlight || level == null) {
      _checkIdle();
      return;
    }
    if (_final) {
      _pending = null;
      _final = false;
      if (level == _lastSucceeded) {
        _checkIdle();
        return;
      }
      _start(level);
      return;
    }
    if (_cooling) return;
    _pending = null;
    _start(level);
  }

  void _start(int level) {
    _inFlight = true;
    _idleOwed = true;
    _startCooldown();
    unawaited(_run(level));
  }

  void _startCooldown() {
    _cooldownJob?.cancel();
    _cooling = true;
    _cooldownJob = scheduler.after(throttle, () {
      _cooling = false;
      _cooldownJob = null;
      _flush();
    });
  }

  Future<void> _run(int level) async {
    final generation = _generation;
    var retried = false;
    while (true) {
      try {
        await send(level).timeout(timeout);
        if (_disposed) return;
        if (generation != _generation) {
          _discard();
          return;
        }
        _lastSucceeded = level;
        _inFlight = false;
        _flush();
        return;
      } on UnauthorizedFailure {
        if (_disposed) return;
        if (generation != _generation) {
          _discard();
          return;
        }
        _fail(level);
        return;
      } catch (_) {
        if (_disposed) return;
        if (generation != _generation) {
          _discard();
          return;
        }
        if (retried) {
          _fail(level);
          return;
        }
        retried = true;
      }
    }
  }

  /// Ends a run whose result was cancelled: no retry, no [onFailed].
  void _discard() {
    _inFlight = false;
    _flush();
  }

  void _fail(int level) {
    if (_disposed) return;
    _inFlight = false;
    _pending = null;
    _final = false;
    onFailed(level);
    _checkIdle();
  }

  void _checkIdle() {
    if (_disposed || _inFlight || _pending != null || !_idleOwed) return;
    _idleOwed = false;
    onIdle();
  }
}
