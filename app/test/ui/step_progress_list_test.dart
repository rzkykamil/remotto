import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:remotto/core/haptics/r_haptics.dart';
import 'package:remotto/core/storage/app_preferences.dart';
import 'package:remotto/core/storage/storage_providers.dart';
import 'package:remotto/ui/r_icon.dart';
import 'package:remotto/ui/r_icons_data.dart';
import 'package:remotto/ui/step_progress_list.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes.dart';
import '../support/test_app.dart';

const _steps = [
  StepProgressItem(label: 'Laptop ketemu', state: StepProgressState.done),
  StepProgressItem(label: 'Cek token', state: StepProgressState.active),
  StepProgressItem(label: 'Simpan sambungan', state: StepProgressState.todo),
];

Future<List<Override>> _overrides() async {
  SharedPreferences.setMockInitialValues({
    AppPreferences.keyHapticEnabled: true,
  });
  final prefs = await SharedPreferences.getInstance();
  return [
    hapticSinkProvider.overrideWithValue(RecordingHapticSink()),
    sharedPreferencesProvider.overrideWithValue(prefs),
  ];
}

void main() {
  testWidgets('shows every step label and the done check icon', (tester) async {
    await pumpApp(
      tester,
      const StepProgressList(steps: _steps),
      overrides: await _overrides(),
    );

    expect(find.text('Laptop ketemu'), findsOneWidget);
    expect(find.text('Cek token'), findsOneWidget);
    expect(find.text('Simpan sambungan'), findsOneWidget);
    final icons = tester.widgetList<RIcon>(find.byType(RIcon)).toList();
    expect(icons.where((i) => i.data == RIcons.check), hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('active ring animates in normal motion', (tester) async {
    await pumpApp(
      tester,
      const StepProgressList(steps: _steps),
      overrides: await _overrides(),
    );

    expect(tester.hasRunningAnimations, isTrue);
  });

  testWidgets('active ring stays still with reduced motion', (tester) async {
    await pumpApp(
      tester,
      const StepProgressList(steps: _steps),
      overrides: await _overrides(),
      disableAnimations: true,
    );

    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('group is a live region and each row has a label', (
    tester,
  ) async {
    await pumpApp(
      tester,
      const StepProgressList(steps: _steps),
      overrides: await _overrides(),
    );

    final group = tester.getSemantics(find.byType(StepProgressList));
    expect(group.flagsCollection.isLiveRegion, isTrue);
    expect(find.text('Cek token'), findsOneWidget);
    expect(find.text('Simpan sambungan'), findsOneWidget);
  });

  testWidgets('renders in dark theme without overflow', (tester) async {
    await pumpApp(
      tester,
      const StepProgressList(steps: _steps),
      overrides: await _overrides(),
      dark: true,
    );

    expect(find.text('Cek token'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders in light theme with done, active and todo rows', (
    tester,
  ) async {
    await pumpApp(
      tester,
      const StepProgressList(steps: _steps),
      overrides: await _overrides(),
    );

    expect(find.text('Laptop ketemu'), findsOneWidget);
    expect(find.text('Cek token'), findsOneWidget);
    expect(find.text('Simpan sambungan'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
