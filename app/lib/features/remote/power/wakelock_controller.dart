import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Keeps the screen awake while the countdown is on screen (C13). Tests
/// override [wakelockControllerProvider] with a fake.
abstract interface class WakelockController {
  Future<void> enable();
  Future<void> disable();
}

/// Default implementation on top of `wakelock_plus`.
///
/// Errors are swallowed: a platform that cannot hold the screen awake must
/// not stop the countdown. The laptop still gets the schedule either way.
final class WakelockPlusController implements WakelockController {
  const WakelockPlusController();

  @override
  Future<void> enable() => _guard(WakelockPlus.enable);

  @override
  Future<void> disable() => _guard(WakelockPlus.disable);

  static Future<void> _guard(Future<void> Function() call) async {
    try {
      await call();
    } catch (_) {
      // See the class comment: the countdown continues without the wakelock.
    }
  }
}

final wakelockControllerProvider = Provider<WakelockController>(
  (ref) => const WakelockPlusController(),
);
