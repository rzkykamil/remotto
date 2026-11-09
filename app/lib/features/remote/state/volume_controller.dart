import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:remotto/core/connection/connection_providers.dart';
import 'package:remotto/core/connection/connection_state.dart';
import 'package:remotto/core/haptics/r_haptics.dart';
import 'package:remotto/core/network/agent_status.dart';
import 'package:remotto/core/network/api_failure.dart';
import 'package:remotto/core/strings/remote_strings.dart';
import 'package:remotto/core/theme/tokens.g.dart';
import 'package:remotto/core/toast/toast_controller.dart';
import 'package:remotto/features/remote/data/volume_repository.dart';
import 'package:remotto/features/remote/state/volume_providers.dart';
import 'package:remotto/features/remote/state/volume_sender.dart';

/// State of the volume panel (SCR-010, C04, C05).
final class VolumeState {
  const VolumeState({
    this.level = 0,
    this.muted = false,
    this.dragging = false,
    this.confirmed,
  });

  /// Shown level. Optimistic while a command runs or the finger moves.
  final int level;

  /// Shown mute state. A drag sets it to false locally (BR-15).
  final bool muted;

  /// Slider gesture in progress.
  final bool dragging;

  /// Last value the laptop confirmed (or the last synced status). Null until
  /// the first status with a volume arrives.
  final VolumeStatus? confirmed;

  /// False until a volume value is known (the "—" state in the panel).
  bool get known => confirmed != null;

  VolumeState copyWith({
    int? level,
    bool? muted,
    bool? dragging,
    VolumeStatus? confirmed,
  }) {
    return VolumeState(
      level: level ?? this.level,
      muted: muted ?? this.muted,
      dragging: dragging ?? this.dragging,
      confirmed: confirmed ?? this.confirmed,
    );
  }
}

/// Button commands that can be in flight.
enum _Button { up, down, mute }

/// Volume commands and sync (docs/technical-spec.md §6, BR-14, BR-15, BR-16).
///
/// - Slider: [VolumeSender] sends one request at a time (BR-14).
/// - −/+: optimistic ±5, no automatic retry (not idempotent).
/// - Mute: optimistic, one silent retry.
/// - Polling updates the panel only while idle (no drag, no request in flight).
///   A status that arrives while held is applied once idle.
/// - A failure rolls back to [VolumeState.confirmed] and shows a toast with
///   a retry action. A 401 goes to the pairing flow without a toast.
///
/// Non-autoDispose: the level survives screen changes.
final class VolumeController extends Notifier<VolumeState> {
  late VolumeRepository _repository;
  late RHaptics _haptics;
  late VolumeSender _sender;

  /// Button commands in flight.
  final Set<_Button> _busy = {};

  /// Newest status volume received while not idle.
  VolumeStatus? _held;

  /// Error of the last slider request, read by [_onSliderFailed].
  Object? _lastSendError;

  /// Bumped when the connection is lost while a command is pending. A reply
  /// from an older epoch is ignored: it must not overwrite the value shown
  /// after the cancel.
  int _epoch = 0;

  @override
  VolumeState build() {
    _repository = ref.read(volumeRepositoryProvider);
    _haptics = ref.read(hapticsProvider);
    _sender = VolumeSender(
      scheduler: ref.read(pollSchedulerProvider),
      send: _sendLevel,
      onFailed: _onSliderFailed,
      onIdle: _syncIfIdle,
    );
    ref.onDispose(_sender.dispose);
    ref.listen(connectionControllerProvider, (prev, next) {
      if (_lostConnection(next.phase) && _hasWork) _abortPending();
      // A phase change keeps the previous status object. Only a new poll
      // carries a newer volume, so the old one must not overwrite a reply.
      if (identical(prev?.status, next.status)) return;
      final volume = next.status?.volume;
      if (volume == null) return;
      _held = volume;
      _syncIfIdle();
    });

    final initial = ref.read(connectionControllerProvider).status?.volume;
    if (initial == null) return const VolumeState();
    _sender.setConfirmed(initial.muted ? null : initial.level);
    return VolumeState(
      level: initial.level,
      muted: initial.muted,
      confirmed: initial,
    );
  }

  // Slider gesture -----------------------------------------------------------

  /// Gesture start. A tap is [dragStart] followed by [dragEnd].
  void dragStart(int level) {
    if (!state.known) return;
    state = state.copyWith(dragging: true, level: level, muted: false);
  }

  void dragUpdate(int level) {
    if (!state.dragging) return;
    final from = state.level;
    if (level == from) return;
    state = state.copyWith(level: level);
    _touchHaptics(from, level);
    _sender.submit(level);
  }

  void dragEnd(int level) {
    if (!state.dragging) return;
    state = state.copyWith(dragging: false, level: level);
    _sender.finish(level);
    _syncIfIdle();
  }

  /// Gesture cancelled by the slider (it got disabled mid-drag). The slider
  /// returns to the confirmed value.
  void dragCancel() {
    if (!state.dragging) return;
    _abortPending();
    _syncIfIdle();
  }

  // −/+ ---------------------------------------------------------------------

  void up() => _step(RComponent.volumeSliderButtonStep);

  void down() => _step(-RComponent.volumeSliderButtonStep);

  Future<void> _step(int delta) async {
    if (!state.known || state.dragging || _sender.busy || _busy.isNotEmpty) {
      return;
    }
    final target = (state.level + delta).clamp(0, 100);
    if (target == state.level) {
      _haptics.limit();
      return;
    }

    final button = delta > 0 ? _Button.up : _Button.down;
    final epoch = _epoch;
    _busy.add(button);
    state = state.copyWith(level: target, muted: false);
    VolumeStatus? reply;
    Object? error;
    try {
      reply = await (delta > 0 ? _repository.up() : _repository.down()).timeout(
        RMotion.commandTimeout,
      );
    } catch (e) {
      error = e;
    }
    _busy.remove(button);
    if (!ref.mounted) return;
    if (epoch != _epoch) {
      // Cancelled by a lost connection: the reply is ignored, no toast.
      _syncIfIdle();
      return;
    }

    if (reply != null) {
      _setConfirmed(reply);
      _syncIfIdle();
      return;
    }
    _rollback();
    _syncIfIdle();
    _reportFailure(
      _toFailure(error!),
      text: RemoteStrings.toastCommandFailed,
      retry: () => _step(delta),
    );
  }

  // Mute ---------------------------------------------------------------------

  /// Flips mute. One silent retry on failure.
  Future<void> toggleMute() async {
    if (!state.known || state.dragging || _busy.contains(_Button.mute)) {
      return;
    }
    final target = !state.muted;
    final epoch = _epoch;
    _busy.add(_Button.mute);
    state = state.copyWith(muted: target);
    VolumeStatus? reply;
    Object? error;
    try {
      reply = await _setMutedWithRetry(target, epoch);
    } catch (e) {
      error = e;
    }
    _busy.remove(_Button.mute);
    if (!ref.mounted) return;
    if (epoch != _epoch) {
      // Cancelled by a lost connection: the reply is ignored, no toast.
      _syncIfIdle();
      return;
    }

    if (reply != null) {
      _setConfirmed(reply);
      _syncIfIdle();
      return;
    }
    _rollback();
    _syncIfIdle();
    _reportFailure(
      _toFailure(error!),
      text: RemoteStrings.toastCommandFailed,
      retry: toggleMute,
    );
  }

  /// One retry, skipped when the command was cancelled meanwhile.
  Future<VolumeStatus> _setMutedWithRetry(bool target, int epoch) async {
    try {
      return await _repository.setMuted(target).timeout(RMotion.commandTimeout);
    } on UnauthorizedFailure {
      rethrow;
    } catch (_) {
      if (epoch != _epoch) rethrow;
      return _repository.setMuted(target).timeout(RMotion.commandTimeout);
    }
  }

  // Slider request path --------------------------------------------------------

  /// The sender's send. Records the error so [_onSliderFailed] can tell a 401 apart.
  /// A reply that arrives after a cancel is not applied.
  Future<void> _sendLevel(int level) async {
    _lastSendError = null;
    final epoch = _epoch;
    try {
      final reply = await _repository.setLevel(level);
      if (!ref.mounted || epoch != _epoch) return;
      _setConfirmed(reply);
    } catch (error) {
      _lastSendError = error;
      rethrow;
    }
  }

  void _onSliderFailed(int level) {
    final error = _lastSendError ?? const TimeoutFailure();
    _lastSendError = null;
    if (!ref.mounted) return;
    // The gesture ends on failure (the value is rolled back to confirmed).
    state = state.copyWith(dragging: false);
    _rollback();
    _syncIfIdle();
    _reportFailure(
      _toFailure(error),
      text: RemoteStrings.toastVolumeFailed(state.confirmed?.level ?? 0),
      retry: () => _retrySlider(level),
    );
  }

  void _retrySlider(int level) {
    if (!ref.mounted) return;
    state = state.copyWith(level: level, muted: false);
    _sender.finish(level);
  }

  // Sync and state helpers -------------------------------------------------------

  /// Idle means no drag, no slider request, and no button command.
  bool get _idle => !state.dragging && !_sender.busy && _busy.isEmpty;

  /// A drag, a queued level, or a command in flight.
  bool get _hasWork => state.dragging || _sender.busy || _busy.isNotEmpty;

  /// Offline, powered off, or token rejected: the laptop cannot take commands.
  static bool _lostConnection(ConnectionPhase phase) =>
      phase == ConnectionPhase.offline ||
      phase == ConnectionPhase.poweredOff ||
      phase == ConnectionPhase.tokenRejected;

  /// Ends the drag, drops the queued level, and shows the confirmed value. A
  /// request already sent is not cut; its reply is ignored (epoch and sender
  /// generation). No toast: the cancel is silent.
  void _abortPending() {
    _epoch++;
    _sender.cancelPending();
    state = state.copyWith(dragging: false);
    _rollback();
  }

  /// Stores [status] as confirmed. A reply is newer than any status held
  /// before it, so the held status is dropped.
  void _setConfirmed(VolumeStatus status) {
    _held = null;
    state = state.copyWith(confirmed: status);
    _sender.setConfirmed(status.muted ? null : status.level);
  }

  /// Applies the held status or the confirmed value to the panel when idle.
  void _syncIfIdle() {
    if (!_idle) return;
    final held = _held;
    if (held != null) {
      _held = null;
      _setConfirmed(held);
    }
    final confirmed = state.confirmed;
    if (confirmed == null) return;
    if (state.level == confirmed.level && state.muted == confirmed.muted) {
      return;
    }
    state = state.copyWith(level: confirmed.level, muted: confirmed.muted);
  }

  /// Shows the confirmed value again. Used after a failed command.
  void _rollback() {
    final confirmed = state.confirmed;
    if (confirmed == null) return;
    state = state.copyWith(level: confirmed.level, muted: confirmed.muted);
  }

  /// Haptics for a slider change from [from] to [to].
  void _touchHaptics(int from, int to) {
    if (to == 0 || to == 100) {
      _haptics.limit();
      return;
    }
    const step = RComponent.volumeSliderHapticDetent;
    final crossed = to > from
        ? to ~/ step > from ~/ step
        : from ~/ step > to ~/ step;
    if (crossed) _haptics.detent();
  }

  /// One failure path for every command: haptic, then 401 or toast with retry.
  void _reportFailure(
    ApiFailure failure, {
    required String text,
    required void Function() retry,
  }) {
    _haptics.failure();
    if (failure is UnauthorizedFailure) {
      ref.read(connectionControllerProvider.notifier).reportUnauthorized();
      return;
    }
    final toasts = ref.read(toastControllerProvider.notifier);
    // The toast does not close itself on action, so the retry closes it.
    late final ToastMessage message;
    message = ToastMessage(
      text: text,
      variant: ToastVariant.error,
      actionLabel: RemoteStrings.toastRetry,
      onAction: () {
        toasts.dismiss(message);
        retry();
      },
    );
    toasts.show(message);
  }

  ApiFailure _toFailure(Object error) {
    if (error is ApiFailure) return error;
    if (error is TimeoutException) return const TimeoutFailure();
    return const ServerFailure();
  }
}
