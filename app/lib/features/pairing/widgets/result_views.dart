import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/strings/pairing_strings.dart';
import '../../../core/theme/r_behavior.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../core/theme/tokens.g.dart';
import '../../../ui/pairing_scaffold.dart';
import '../../../ui/r_icon.dart';
import '../../../ui/r_icons_data.dart';

/// Icon inside an 80 dp glass circle (Q09-Q12). Icon size 36 dp matches the
/// artboard.
const double _iconSize = RSpace.s8 + RSpace.s1;

/// Q09: connection test succeeded. Laptop name from the agent `/status`. "Mulai pakai"
/// opens Remote (S01). Read out as an announcement.
final class SuccessView extends StatelessWidget {
  const SuccessView({super.key, required this.laptopName});

  final String laptopName;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: PairingStrings.successTitle(laptopName),
      container: true,
      explicitChildNodes: true,
      child: PairingScaffold(
        leading: _IconDisc(icon: RIcons.check, color: context.status.success),
        kicker: PairingStrings.successKicker,
        title: PairingStrings.successTitle(laptopName),
        body: PairingStrings.successBody,
        primaryLabel: PairingStrings.successStart,
        onPrimary: () => context.go('/remote'),
      ),
    );
  }
}

/// Q10: step 1 failed, laptop not found. Concrete tips and two actions.
final class TimeoutView extends StatelessWidget {
  const TimeoutView({
    super.key,
    required this.address,
    required this.onRetry,
    required this.onChangeAddress,
  });

  /// The `host:port` address that was tried.
  final String address;
  final VoidCallback onRetry;
  final VoidCallback onChangeAddress;

  @override
  Widget build(BuildContext context) {
    return PairingScaffold(
      leading: _IconDisc(
        icon: RIcons.wifi,
        color: Theme.of(context).colorScheme.onSurface,
      ),
      title: PairingStrings.timeoutTitle,
      body: PairingStrings.timeoutBody(
        address: address,
        seconds: RBehavior.stepTimeout.inSeconds,
      ),
      tips: const [
        PairingStrings.timeoutTip1,
        PairingStrings.timeoutTip2,
        PairingStrings.timeoutTip3,
      ],
      primaryLabel: PairingStrings.retry,
      onPrimary: onRetry,
      secondaryLabel: PairingStrings.changeAddress,
      onSecondary: onChangeAddress,
    );
  }
}

/// Q11: step 2 failed (401). Primary action is rescan, not retype.
final class RejectedView extends StatelessWidget {
  const RejectedView({
    super.key,
    required this.onRescan,
    required this.onManual,
  });

  final VoidCallback onRescan;
  final VoidCallback onManual;

  @override
  Widget build(BuildContext context) {
    return PairingScaffold(
      leading: _IconDisc(
        icon: RIcons.key,
        color: Theme.of(context).colorScheme.onSurface,
      ),
      title: PairingStrings.rejectedTitle,
      body: PairingStrings.rejectedBody,
      primaryLabel: PairingStrings.rescanQr,
      onPrimary: onRescan,
      secondaryLabel: PairingStrings.manualLink,
      onSecondary: onManual,
    );
  }
}

/// Q12: connection dropped during daily use (401 from Remote). Read out
/// as an announcement. Old connection data is not deleted.
final class ExpiredView extends StatelessWidget {
  const ExpiredView({
    super.key,
    required this.laptopName,
    required this.onRescan,
    required this.onManual,
  });

  final String laptopName;
  final VoidCallback onRescan;
  final VoidCallback onManual;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: PairingStrings.expiredAnnouncement,
      container: true,
      explicitChildNodes: true,
      child: PairingScaffold(
        leading: _IconDisc(
          icon: RIcons.plug,
          color: Theme.of(context).colorScheme.onSurface,
        ),
        kicker: laptopName.toUpperCase(),
        title: PairingStrings.expiredTitle,
        body: PairingStrings.expiredBody,
        primaryLabel: PairingStrings.rescanQr,
        onPrimary: onRescan,
        secondaryLabel: PairingStrings.manualLink,
        onSecondary: onManual,
      ),
    );
  }
}

/// 80 dp glass circle containing an icon (artboard `.block` Q09-Q12).
final class _IconDisc extends StatelessWidget {
  const _IconDisc({required this.icon, required this.color});

  final RIconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final glass = context.glass;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: glass.chip,
        shape: BoxShape.circle,
        border: Border.all(
          color: glass.edge,
          width: RComponent.glassPanelEdgeWidth,
        ),
      ),
      child: SizedBox.square(
        dimension: RSize.media,
        child: Center(
          child: RIcon(icon, size: _iconSize, color: color),
        ),
      ),
    );
  }
}
