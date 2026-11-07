import 'package:flutter/material.dart';

import '../core/theme/theme_extensions.dart';
import '../core/theme/tokens.g.dart';
import 'glass_key.dart';
import 'glass_panel.dart';
import 'light_backdrop.dart';
import 'link_button.dart';
import 'r_icon.dart';
import 'r_icons_data.dart';

/// Widths below this value use the compact margin (360 dp). The reference
/// artboard is 412 dp.
const double _compactWidth = 400;

/// Back button icon (17-22 dp, `design/components.md` C02).
const double _backIconSize = 20;

/// Width of the divider line between tip rows.
const double _dividerWidth = 1;

/// Pairing screen scaffold (`design/components.md` C15).
///
/// Layout from the top: optional back button, [leading] (mark or 80 icon),
/// [kicker], [title], [body], optional [content], numbered [tips] in a
/// glass group, then the accent primary action and the secondary link stuck to
/// the bottom. The middle area can scroll when text is enlarged, while the actions
/// stay visible.
///
/// The title uses a Semantics header and gets initial focus. There is no
/// [Scaffold] or AppBar: the background is from [LightBackdrop].
final class PairingScaffold extends StatelessWidget {
  const PairingScaffold({
    super.key,
    required this.title,
    required this.primaryLabel,
    this.onPrimary,
    this.onBack,
    this.backLabel,
    this.leading,
    this.kicker,
    this.body,
    this.content,
    this.tips = const [],
    this.secondaryLabel,
    this.onSecondary,
  }) : assert(
         onBack == null || backLabel != null,
         'backLabel is required when onBack is set.',
       );

  /// Screen title (`titleXl`), read out as a header.
  final String title;

  /// Primary action label. Also used as the Semantics label.
  final String primaryLabel;

  /// Null makes the primary action disabled.
  final VoidCallback? onPrimary;

  /// Null hides the back button.
  final VoidCallback? onBack;

  /// Semantics label of the back button, required when [onBack] is set.
  final String? backLabel;

  /// Mark or 80 dp icon above the text. Its layout is set by the caller.
  final Widget? leading;

  /// Small mono text above the title (`caption`). Uppercase comes from the caller.
  final String? kicker;

  /// Explanation below the title (`body`, secondary color).
  final String? body;

  /// Free content between body and tips, e.g. form fields.
  final Widget? content;

  /// Numbered steps, shown in one glass group.
  final List<String> tips;

  /// Secondary link below the primary action. Null hides it.
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final gutter = width < _compactWidth
        ? RSize.screenMarginCompact
        : RSize.screenMargin;

    return LightBackdrop(
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: gutter),
          child: Column(
            children: [
              _topBar(context),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight,
                        ),
                        child: IntrinsicHeight(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: _sections(context),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              _actions(context),
            ],
          ),
        ),
      ),
    );
  }

  /// The top row always has its height, so the title does not jump when the back
  /// button appears or disappears between steps.
  Widget _topBar(BuildContext context) {
    final back = onBack;
    return SizedBox(
      height: RSize.touchMin,
      child: back == null
          ? null
          : Align(
              alignment: Alignment.centerLeft,
              child: GlassKey(
                semanticsLabel: backLabel!,
                onPressed: back,
                variant: GlassKeyVariant.chip,
                size: GlassKeySize.touch,
                icon: RIcon(
                  RIcons.back,
                  size: _backIconSize,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
    );
  }

  List<Widget> _sections(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final secondary = Theme.of(context).colorScheme.onSurfaceVariant;

    return [
      if (leading != null) ...[leading!, const SizedBox(height: RSpace.s5)],
      if (kicker != null) ...[
        Text(kicker!, style: textTheme.labelSmall?.copyWith(color: secondary)),
        const SizedBox(height: RSpace.s2),
      ],
      Semantics(
        header: true,
        child: Focus(
          autofocus: true,
          child: Text(title, style: textTheme.headlineSmall),
        ),
      ),
      if (body != null) ...[
        const SizedBox(height: RSpace.s2),
        Text(body!, style: textTheme.bodyLarge?.copyWith(color: secondary)),
      ],
      if (content != null) ...[const SizedBox(height: RSpace.s5), content!],
      if (tips.isNotEmpty) ...[
        const SizedBox(height: RSpace.s5),
        _TipsGroup(tips: tips),
      ],
    ];
  }

  Widget _actions(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: RSpace.s4, bottom: RSpace.s8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          GlassKey(
            semanticsLabel: primaryLabel,
            label: primaryLabel,
            onPressed: onPrimary,
            variant: GlassKeyVariant.accent,
            size: GlassKeySize.action,
          ),
          if (secondaryLabel != null)
            RLinkButton(
              label: secondaryLabel!,
              semanticsLabel: secondaryLabel!,
              onPressed: onSecondary,
            ),
        ],
      ),
    );
  }
}

/// Glass group containing numbered steps (`design/components.md` C15, Q10).
final class _TipsGroup extends StatelessWidget {
  const _TipsGroup({required this.tips});

  final List<String> tips;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final divider = context.glass.lowlight;
    final numberStyle = textTheme.labelSmall?.copyWith(
      color: context.accent.text,
      fontWeight: FontWeight.w600,
    );

    return GlassPanel(
      padding: const EdgeInsets.symmetric(
        horizontal: RSpace.s4,
        vertical: RSpace.s2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < tips.length; i++)
            DecoratedBox(
              decoration: BoxDecoration(
                border: i == 0
                    ? null
                    : Border(
                        top: BorderSide(color: divider, width: _dividerWidth),
                      ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: RSpace.s3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${i + 1}', style: numberStyle),
                    const SizedBox(width: RSpace.s3),
                    Expanded(child: Text(tips[i], style: textTheme.bodyLarge)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
