import 'package:flutter/material.dart';

import '../core/theme/theme_extensions.dart';
import '../core/theme/tokens.g.dart';
import 'r_icon.dart';
import 'r_icons_data.dart';

/// Field stroke width when focused or in error (`accent.text`).
const double _emphasisLineWidth = 2;

/// Error message icon (C17, Q07).
const double _errorIconSize = 16;

/// Glass text field (`design/components.md` C17).
///
/// Layout: label 14 on top, 56 dp field `RRadius.sm` with mono text,
/// optional right action ([trailing]), then an error message with icon. No
/// Material decoration: no border or fill from `InputDecoration`.
///
/// States: empty, focus (`accent.text` stroke), filled, error (stroke, icon,
/// `accent.text` message), and disabled ([enabled] false). Validation is done by
/// the caller via [errorText]; [onFocusLost] is called when the field is left.
///
/// Semantics: label and [errorText] are read together as one field
/// label. The visible label and error message are hidden from semantics
/// so they are not read twice.
final class GlassTextField extends StatefulWidget {
  const GlassTextField({
    super.key,
    required this.label,
    this.controller,
    this.focusNode,
    this.hintText,
    this.errorText,
    this.enabled = true,
    this.keyboardType,
    this.textInputAction,
    this.autocorrect = true,
    this.enableSuggestions = true,
    this.obscureText = false,
    this.onChanged,
    this.onSubmitted,
    this.onFocusLost,
    this.trailing,
  });

  final String label;
  final TextEditingController? controller;

  /// Null makes the field use its own [FocusNode].
  final FocusNode? focusNode;
  final String? hintText;

  /// Error message. Null means no error.
  final String? errorText;
  final bool enabled;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;

  /// The token does not use autocorrect and word suggestions.
  final bool autocorrect;
  final bool enableSuggestions;
  final bool obscureText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  /// Called when focus moves out of the field (validate on leave).
  final VoidCallback? onFocusLost;

  /// Right action inside the field, e.g. the show-token button (48 dp).
  final Widget? trailing;

  @override
  State<GlassTextField> createState() => _GlassTextFieldState();
}

final class _GlassTextFieldState extends State<GlassTextField> {
  FocusNode? _ownNode;
  bool _focused = false;

  FocusNode get _node => widget.focusNode ?? (_ownNode ??= FocusNode());

  @override
  void initState() {
    super.initState();
    _node.addListener(_handleFocusChange);
    _focused = _node.hasFocus;
  }

  @override
  void didUpdateWidget(GlassTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      final previous = oldWidget.focusNode ?? _ownNode;
      previous?.removeListener(_handleFocusChange);
      _node.addListener(_handleFocusChange);
      _focused = _node.hasFocus;
    }
  }

  @override
  void dispose() {
    _node.removeListener(_handleFocusChange);
    _ownNode?.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    final hasFocus = _node.hasFocus;
    if (hasFocus != _focused) {
      setState(() => _focused = hasFocus);
      if (!hasFocus) widget.onFocusLost?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final glass = context.glass;
    final accent = context.accent;
    final control = context.control;
    final textTheme = Theme.of(context).textTheme;
    final enabled = widget.enabled;
    final error = widget.errorText;
    final hasError = error != null;

    final Color lineColor;
    final double lineWidth;
    if (hasError || (_focused && enabled)) {
      lineColor = accent.text;
      lineWidth = _emphasisLineWidth;
    } else {
      lineColor = glass.edge;
      lineWidth = RComponent.glassPanelEdgeWidth;
    }

    final textColor = enabled ? scheme.onSurface : control.fgDisabled;
    final bodyStyle = (textTheme.bodyLarge ?? const TextStyle()).copyWith(
      fontFamily: RFont.mono,
      color: textColor,
    );
    final hintStyle = bodyStyle.copyWith(
      color: enabled ? scheme.onSurfaceVariant : control.fgDisabled,
    );
    final semanticLabel = hasError ? '${widget.label}. $error' : widget.label;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExcludeSemantics(
          child: Text(
            widget.label,
            style: (textTheme.labelLarge ?? const TextStyle()).copyWith(
              color: textColor,
            ),
          ),
        ),
        const SizedBox(height: RSpace.s2),
        Container(
          height: RSize.control,
          decoration: BoxDecoration(
            color: enabled ? glass.chip : glass.chipDisabled,
            borderRadius: BorderRadius.circular(RRadius.sm),
            border: Border.all(color: lineColor, width: lineWidth),
          ),
          padding: EdgeInsets.only(
            left: RSpace.s4,
            right: widget.trailing == null ? RSpace.s4 : RSpace.s1,
          ),
          child: Row(
            children: [
              Expanded(
                child: MergeSemantics(
                  child: Semantics(
                    label: semanticLabel,
                    textField: true,
                    enabled: enabled,
                    // TextField needs a Material ancestor. Transparent so
                    // no Material decoration shows.
                    child: Material(
                      type: MaterialType.transparency,
                      child: TextField(
                        controller: widget.controller,
                        focusNode: _node,
                        enabled: enabled,
                        keyboardType: widget.keyboardType,
                        textInputAction: widget.textInputAction,
                        autocorrect: widget.autocorrect,
                        enableSuggestions: widget.enableSuggestions,
                        obscureText: widget.obscureText,
                        textCapitalization: TextCapitalization.none,
                        cursorColor: accent.text,
                        style: bodyStyle,
                        onChanged: widget.onChanged,
                        onSubmitted: widget.onSubmitted,
                        decoration: InputDecoration.collapsed(
                          hintText: widget.hintText,
                          hintStyle: hintStyle,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              ?widget.trailing,
            ],
          ),
        ),
        if (hasError)
          Padding(
            padding: const EdgeInsets.only(top: RSpace.s2),
            child: ExcludeSemantics(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  RIcon(
                    RIcons.alertCircle,
                    size: _errorIconSize,
                    color: accent.text,
                  ),
                  const SizedBox(width: RSpace.s2),
                  Expanded(
                    child: Text(
                      error,
                      style: (textTheme.labelLarge ?? const TextStyle())
                          .copyWith(color: accent.text),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
