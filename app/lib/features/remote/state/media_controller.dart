import 'dart:async';

import 'package:flutter/foundation.dart' show VoidCallback;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:remotto/core/connection/connection_controller.dart';
import 'package:remotto/core/connection/connection_providers.dart';
import 'package:remotto/core/haptics/r_haptics.dart';
import 'package:remotto/core/network/api_failure.dart';
import 'package:remotto/core/strings/remote_strings.dart';
import 'package:remotto/core/theme/tokens.g.dart';
import 'package:remotto/core/toast/toast_controller.dart';
import 'package:remotto/features/remote/data/media_repository.dart';
import 'package:remotto/features/remote/state/media_providers.dart';

/// State of the media dock (SCR-010, C03).
final class MediaState {
  const MediaState({
    this.playing = true,
    this.playProcessing = false,
    this.ringVisible = false,
    this.blinkPrev = 0,
    this.blinkNext = 0,
  });

  /// Shown icon: pause when true, play when false. Optimistic while processing.
  final bool playing;

  /// Play/pause command in flight.
  final bool playProcessing;

  /// Processing ring, shown only after the processing hint delay.
  final bool ringVisible;

  /// Tick counters that drive the prev/next blink. Each tap increases one.
  final int blinkPrev;
  final int blinkNext;

  MediaState copyWith({
    bool? playing,
    bool? playProcessing,
    bool? ringVisible,
    int? blinkPrev,
    int? blinkNext,
  }) {
    return MediaState(
      playing: playing ?? this.playing,
      playProcessing: playProcessing ?? this.playProcessing,
      ringVisible: ringVisible ?? this.ringVisible,
      blinkPrev: blinkPrev ?? this.blinkPrev,
      blinkNext: blinkNext ?? this.blinkNext,
    );
  }
}

/// Media commands from the dock (docs/technical-spec.md, media is not retried
/// automatically). Each command is sent once per tap; a failure rolls back the
/// optimistic state and shows a toast with a retry action.
///
/// Non-autoDispose: the play state survives screen changes.
/// The press haptic comes from the key's Pressable on finger down, so this
/// controller only fires the failure haptic.
final class MediaController extends Notifier<MediaState> {
  late MediaRepository _repository;
  late PollScheduler _scheduler;
  late RHaptics _haptics;
  ScheduledJob? _ringJob;

  /// Prev/next/play requests in flight, to ignore repeated taps.
  final Set<MediaAction> _busy = {};

  @override
  MediaState build() {
    _repository = ref.read(mediaRepositoryProvider);
    _scheduler = ref.read(pollSchedulerProvider);
    _haptics = ref.read(hapticsProvider);
    ref.onDispose(_cancelRing);
    return const MediaState();
  }

  /// Play/pause. Flips the icon at once. Ignored while a play command is in flight.
  void togglePlay() {
    if (state.playProcessing) return;
    final before = state.playing;
    _cancelRing();
    state = state.copyWith(
      playing: !before,
      playProcessing: true,
      ringVisible: false,
    );
    _ringJob = _scheduler.after(RMotion.processingHint, () {
      if (state.playProcessing) state = state.copyWith(ringVisible: true);
    });
    unawaited(
      _run(
        MediaAction.playPause,
        retry: togglePlay,
        onFailure: () => state = state.copyWith(playing: before),
        onSettled: () {
          _cancelRing();
          state = state.copyWith(playProcessing: false, ringVisible: false);
        },
      ),
    );
  }

  void prev() => _skip(MediaAction.prev);

  void next() => _skip(MediaAction.next);

  void _skip(MediaAction action) {
    if (_busy.contains(action)) return;
    state = action == MediaAction.prev
        ? state.copyWith(blinkPrev: state.blinkPrev + 1)
        : state.copyWith(blinkNext: state.blinkNext + 1);
    unawaited(_run(action, retry: action == MediaAction.prev ? prev : next));
  }

  /// Sends [action] with the time limit. Failures go to [_onFailure].
  Future<void> _run(
    MediaAction action, {
    required VoidCallback retry,
    VoidCallback? onFailure,
    VoidCallback? onSettled,
  }) async {
    _busy.add(action);
    ApiFailure? failure;
    try {
      await _repository.send(action).timeout(RMotion.commandTimeout);
    } on TimeoutException {
      failure = const TimeoutFailure();
    } on ApiFailure catch (error) {
      failure = error;
    } finally {
      _busy.remove(action);
    }

    // The screen may have closed while the request was in flight.
    if (!ref.mounted) return;
    onSettled?.call();
    if (failure == null) return;
    onFailure?.call();
    _onFailure(failure, retry);
  }

  void _onFailure(ApiFailure failure, VoidCallback retry) {
    _haptics.failure();
    if (failure is UnauthorizedFailure) {
      ref.read(connectionControllerProvider.notifier).reportUnauthorized();
      return;
    }
    final toasts = ref.read(toastControllerProvider.notifier);
    // The toast widget does not close itself on action, so the retry closes it.
    late final ToastMessage message;
    message = ToastMessage(
      text: RemoteStrings.toastCommandFailed,
      variant: ToastVariant.error,
      actionLabel: RemoteStrings.toastRetry,
      onAction: () {
        toasts.dismiss(message);
        retry();
      },
    );
    toasts.show(message);
  }

  void _cancelRing() {
    _ringJob?.cancel();
    _ringJob = null;
  }
}
