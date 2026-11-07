import 'package:flutter/material.dart';

import '../../../core/strings/pairing_strings.dart';
import '../../../core/theme/tokens.g.dart';
import '../../../ui/glass_key.dart';
import '../../../ui/light_backdrop.dart';
import '../../../ui/step_progress_list.dart';

/// Q08: three-step connection test (SCR-003). Real steps, not an empty
/// spinner. [activeStep] is 0-based: earlier steps are done, later ones not yet.
/// Cancel returns to the origin screen.
final class TestingView extends StatelessWidget {
  const TestingView({
    super.key,
    required this.address,
    required this.activeStep,
    required this.onCancel,
  });

  /// The `host:port` address being tested.
  final String address;

  final int activeStep;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final secondary = Theme.of(context).colorScheme.onSurfaceVariant;

    return LightBackdrop(
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: RSize.screenMargin),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        address,
                        style: textTheme.labelSmall?.copyWith(
                          color: secondary,
                          fontFamily: RFont.mono,
                        ),
                      ),
                      const SizedBox(height: RSpace.s2),
                      Semantics(
                        header: true,
                        child: Text(
                          PairingStrings.testingTitle,
                          style: textTheme.headlineSmall,
                        ),
                      ),
                      const SizedBox(height: RSpace.s6),
                      StepProgressList(steps: _steps()),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: RSpace.s8),
                child: GlassKey(
                  semanticsLabel: PairingStrings.cancel,
                  label: PairingStrings.cancel,
                  onPressed: onCancel,
                  variant: GlassKeyVariant.chip,
                  size: GlassKeySize.control,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<StepProgressItem> _steps() {
    const labels = [
      PairingStrings.testStepFound,
      PairingStrings.testStepToken,
      PairingStrings.testStepSave,
    ];
    return [
      for (var i = 0; i < labels.length; i++)
        StepProgressItem(
          label: labels[i],
          state: i < activeStep
              ? StepProgressState.done
              : i == activeStep
              ? StepProgressState.active
              : StepProgressState.todo,
        ),
    ];
  }
}
