import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/constants/app_constants.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'presentation/screens/settings/settings_controller.dart';
import 'presentation/widgets/web_responsive_frame.dart';

class NexusAiApp extends ConsumerStatefulWidget {
  const NexusAiApp({super.key});

  @override
  ConsumerState<NexusAiApp> createState() => _NexusAiAppState();
}

class _NexusAiAppState extends ConsumerState<NexusAiApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(settingsProvider.notifier).resyncFromServer();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ref.watch(settingsProvider.select((s) => s.isDark));

    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness:
            isDark ? Brightness.light : Brightness.dark,
        systemNavigationBarContrastEnforced: false,
      ),
    );

    return MaterialApp.router(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.whiteTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
      routerConfig: appRouter,
      builder: (context, router) {
        // Wraps the entire navigated tree. On Android and on narrow web
        // viewports it returns [router] unchanged. On wide web viewports
        // it centres the existing mobile UI inside a phone-width column
        // with a tasteful backdrop, giving the app a polished look on
        // desktop without rewriting any of the existing screens.
        return WebResponsiveFrame(child: router ?? const SizedBox.shrink());
      },
    );
  }
}
