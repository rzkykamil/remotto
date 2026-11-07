import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:remotto/core/theme/app_theme.dart';

/// Membungkus [child] dengan tema app, ProviderScope, dan MediaQuery uji.
Future<void> pumpApp(
  WidgetTester tester,
  Widget child, {
  bool dark = false,
  List<Override> overrides = const [],
  bool disableAnimations = false,
  bool highContrast = false,
  Size size = const Size(412, 892),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        builder: (context, widget) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: disableAnimations,
            highContrast: highContrast,
          ),
          child: widget!,
        ),
        home: Scaffold(body: Center(child: child)),
      ),
    ),
  );
}
