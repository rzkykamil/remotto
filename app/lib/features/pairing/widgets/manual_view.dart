import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/strings/pairing_strings.dart';
import '../../../core/theme/tokens.g.dart';
import '../../../ui/glass_key.dart';
import '../../../ui/glass_text_field.dart';
import '../../../ui/pairing_scaffold.dart';
import '../../../ui/r_icon.dart';
import '../../../ui/r_icons_data.dart';
import '../domain/manual_input_validator.dart';
import '../domain/pairing_target.dart';
import '../state/pairing_flow_controller.dart';

/// Sample value that passes validation, used to check a single field
/// with [validateManualInput]. Only the reason from the field being checked
/// is used; reasons from other fields are ignored.
const _probeAddress = '192.168.1.1';
const _probeToken =
    '0000000000000000000000000000000000000000000000000000000000000000';

/// Q06 and Q07: manual form for address and token (SCR-002).
///
/// Validates each field when it is left; submit is only enabled when both
/// fields are filled. Error reasons are mapped to copy in [PairingStrings].
final class ManualView extends ConsumerStatefulWidget {
  const ManualView({super.key});

  @override
  ConsumerState<ManualView> createState() => _ManualViewState();
}

final class _ManualViewState extends ConsumerState<ManualView> {
  late final TextEditingController _address;
  late final TextEditingController _token;
  final _addressFocus = FocusNode();
  final _tokenFocus = FocusNode();

  String? _addressError;
  String? _tokenError;
  bool _tokenVisible = false;

  @override
  void initState() {
    super.initState();
    final flow = ref.read(pairingFlowProvider);
    _address = TextEditingController(text: flow.manualAddress);
    _token = TextEditingController(text: flow.manualToken);
  }

  @override
  void dispose() {
    _address.dispose();
    _token.dispose();
    _addressFocus.dispose();
    _tokenFocus.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _address.text.trim().isNotEmpty && _token.text.trim().isNotEmpty;

  /// Address error for text [raw]. Empty gets no error when the field is
  /// left; submit is already disabled when empty.
  String? _checkAddress(String raw) {
    if (raw.trim().isEmpty) return null;
    final result = validateManualInput(address: raw, token: _probeToken);
    return switch (result) {
      PairingInvalid() => PairingStrings.addressFormatError,
      PairingValid() => null,
    };
  }

  String? _checkToken(String raw) {
    if (raw.trim().isEmpty) return null;
    final result = validateManualInput(address: _probeAddress, token: raw);
    return switch (result) {
      PairingInvalid(:final reason)
          when reason == PairingInvalidReason.invalidToken =>
        PairingStrings.tokenFormatError,
      _ => null,
    };
  }

  void _onAddressBlur() {
    setState(() => _addressError = _checkAddress(_address.text));
  }

  void _onTokenBlur() {
    setState(() => _tokenError = _checkToken(_token.text));
  }

  void _submit() {
    final addressError = _checkAddress(_address.text);
    final tokenError = _checkToken(_token.text);
    setState(() {
      _addressError = addressError;
      _tokenError = tokenError;
    });
    if (addressError != null || tokenError != null) return;
    unawaited(
      ref
          .read(pairingFlowProvider.notifier)
          .submitManual(address: _address.text, token: _token.text),
    );
  }

  void _toggleTokenVisible() {
    setState(() => _tokenVisible = !_tokenVisible);
  }

  @override
  Widget build(BuildContext context) {
    final addressField = GlassTextField(
      label: PairingStrings.addressLabel,
      controller: _address,
      focusNode: _addressFocus,
      hintText: PairingStrings.addressExample,
      errorText: _addressError,
      keyboardType: TextInputType.url,
      textInputAction: TextInputAction.next,
      autocorrect: false,
      enableSuggestions: false,
      onChanged: (_) => setState(() {}),
      onSubmitted: (_) => _tokenFocus.requestFocus(),
      onFocusLost: _onAddressBlur,
    );

    final tokenField = GlassTextField(
      label: PairingStrings.tokenLabel,
      controller: _token,
      focusNode: _tokenFocus,
      hintText: PairingStrings.tokenPlaceholder,
      errorText: _tokenError,
      autocorrect: false,
      enableSuggestions: false,
      obscureText: !_tokenVisible,
      textInputAction: TextInputAction.done,
      onChanged: (_) => setState(() {}),
      onSubmitted: (_) => _submit(),
      onFocusLost: _onTokenBlur,
      trailing: GlassKey(
        semanticsLabel: _tokenVisible
            ? PairingStrings.tokenHide
            : PairingStrings.tokenShow,
        onPressed: _toggleTokenVisible,
        variant: GlassKeyVariant.ghost,
        size: GlassKeySize.touch,
        icon: RIcon(
          RIcons.eye,
          size: _eyeIconSize,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );

    return PairingScaffold(
      title: PairingStrings.manualTitle,
      body: PairingStrings.manualBody,
      onBack: () => ref.read(pairingFlowProvider.notifier).handleBack(),
      backLabel: PairingStrings.back,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          addressField,
          const SizedBox(height: RSpace.s5),
          tokenField,
        ],
      ),
      primaryLabel: PairingStrings.connect,
      onPrimary: _canSubmit ? _submit : null,
    );
  }
}

/// Eye icon inside the right action of the token field (20 dp, `design/components.md`).
const double _eyeIconSize = 20;
