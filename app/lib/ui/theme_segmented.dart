import 'package:flutter/material.dart';

import '../core/strings/settings_strings.dart';
import '../core/theme/reduced_motion.dart';
import '../core/theme/theme_extensions.dart';
import '../core/theme/tokens.g.dart';
import 'r_icon.dart';
import 'r_icons_data.dart';

/// Hairline of the active segment's edge (C01: 1 dp).
const double _edgeWidth = 1;

/// Focus ring width, drawn outside the segment like `Pressable`.
const double _focusWidth = 2;

/// Check icon before the label of the active segment (artboard: 16 dp).
const double _checkSize = RSpace.s4;

/// Crossfade of the active segment (`design/components.md` C20: 200 ms).
/// Same value as [RMotion.toast]; no dedicated token exists yet.
const Duration _crossfade = RMotion.toast;

/// Theme choice: three equal capsule segments, Terang / Gelap / Sistem
/// (`design/components.md` C20, artboard R01/R02).
///
/// Pure widget: [value] and [onChanged] come from the caller, and the widget
/// does not read any provider. Tapping the active segment does nothing.
/// A null [onChanged] disables every segment.
///
/// The active segment is marked by its fill, edge, semibold weight and a
/// check icon, so the state does not depend on colour alone. Labels may wrap
/// to two lines at large text scale; the three columns stay equal width.
///
/// Semantics: a container labelled "Tema", each segment is a checked item in
/// a mutually exclusive group (radio behaviour).
final class ThemeSegmented extends StatelessWidget {
  const ThemeSegmented({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final ThemeMode value;

  /// Null disables the control.
  final ValueChanged<ThemeMode>? onChanged;

  static const _options = <(ThemeMode, String)>[
    (ThemeMode.light, SettingsStrings.themeLight),
    (ThemeMode.dark, SettingsStrings.themeDark),
    (ThemeMode.system, SettingsStrings.themeSystem),
  ];

  @override
  Widget build(BuildContext context) {
    final reduced = ReducedMotion.of(context).enabled;

    final segments = <Widget>[];
    for (var i = 0; i < _options.length; i++) {
      final (mode, label) = _options[i];
      if (i > 0) {
        segments.add(const SizedBox(width: RSpace.s1));
      }
      segments.add(
        Expanded(
          child: _Segment(
            label: label,
            active: mode == value,
            enabled: onChanged != null,
            reduced: reduced,
            onSelected: () {
              if (mode != value) {
                onChanged?.call(mode);
              }
            },
          ),
        ),
      );
    }

    return Semantics(
      container: true,
      label: SettingsStrings.themeLabel,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.control.segTrack,
          borderRadius: BorderRadius.circular(RRadius.full),
        ),
        child: Padding(
          padding: const EdgeInsets.all(RSpace.s1),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: segments,
          ),
        ),
      ),
    );
  }
}

final class _Segment extends StatefulWidget {
  const _Segment({
    required this.label,
    required this.active,
    required this.enabled,
    required this.reduced,
    required this.onSelected,
  });

  final String label;
  final bool active;
  final bool enabled;
  final bool reduced;
  final VoidCallback onSelected;

  @override
  State<_Segment> createState() => _SegmentState();
}

final class _SegmentState extends State<_Segment> {
  bool _focused = false;

  void _activate() {
    if (widget.enabled) {
      widget.onSelected();
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled;
    final active = widget.active;
    final baseStyle =
        Theme.of(context).textTheme.labelLarge ?? const TextStyle();
    final textColor = enabled ? baseStyle.color : context.control.fgDisabled;

    final textStyle = baseStyle.copyWith(
      color: textColor,
      fontWeight: active ? FontWeight.w600 : FontWeight.w400,
    );

    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: active,
      selected: active,
      enabled: enabled,
      label: widget.label,
      onTap: enabled && !active ? _activate : null,
      excludeSemantics: true,
      child: FocusableActionDetector(
        enabled: enabled,
        onShowFocusHighlight: (value) {
          if (_focused != value) {
            setState(() => _focused = value);
          }
        },
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<Intent>(
            onInvoke: (_) {
              _activate();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? _activate : null,
          child: AnimatedContainer(
            duration: widget.reduced ? Duration.zero : _crossfade,
            curve: Curves.easeOut,
            constraints: const BoxConstraints(minHeight: RSize.touchMin),
            padding: const EdgeInsets.symmetric(horizontal: RSpace.s2),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active ? context.control.segOn : Colors.transparent,
              borderRadius: BorderRadius.circular(RRadius.full),
              border: Border.all(
                color: active ? context.glass.edge : Colors.transparent,
                width: _edgeWidth,
              ),
            ),
            foregroundDecoration: _focused
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(RRadius.full),
                    border: Border.all(
                      color: context.accent.text,
                      width: _focusWidth,
                    ),
                  )
                : null,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (active) ...[
                  RIcon(
                    RIcons.check,
                    size: _checkSize,
                    color: textColor ?? baseStyle.color ?? Colors.black,
                    strokeWidth: 2.5,
                  ),
                  const SizedBox(width: RSpace.s1),
                ],
                Flexible(
                  child: Text(
                    widget.label,
                    textAlign: TextAlign.center,
                    style: textStyle,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
