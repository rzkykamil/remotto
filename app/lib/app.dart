import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/strings/strings.dart';
import 'core/storage/storage_providers.dart';
import 'core/theme/app_theme.dart';
import 'ui/light_backdrop.dart';
import 'ui/toast_host.dart';

/// Akar app: router, tema terang/gelap, dan latar cahaya bersama.
class RemottoApp extends ConsumerWidget {
  const RemottoApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      routerConfig: ref.watch(routerProvider),
      title: AppStrings.appName,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ref.watch(themeModeProvider),
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        // Status bar dan navigation bar transparan; ikon mengikuti tema.
        final dark = Theme.of(context).brightness == Brightness.dark;
        final iconBrightness = dark ? Brightness.light : Brightness.dark;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: iconBrightness,
            systemNavigationBarColor: Colors.transparent,
            systemNavigationBarIconBrightness: iconBrightness,
          ),
          child: LightBackdrop(child: ToastHost(child: child!)),
        );
      },
    );
  }
}
