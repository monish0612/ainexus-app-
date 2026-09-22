import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/constants/app_constants.dart';
import 'core/di/injection.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'presentation/providers/profile_photo_provider.dart';
import 'presentation/screens/expense/sms/sms_expense_review_overlay.dart';
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
    // On cold launch, adopt any cross-device nuke that happened while this
    // device was away — wipes local data to match the cloud before any screen
    // renders stale rows (Drift streams refresh the UI automatically).
    unawaited(_syncAfterReset());
  }

  Future<void> _syncAfterReset() async {
    await ref.read(resetSyncServiceProvider).applyRemoteResetIfNeeded();
    if (!mounted) return;
    await ref.read(profilePhotoPathProvider.notifier).syncFromCloud();
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
      // Catch a nuke performed on another device while we were backgrounded.
      unawaited(_syncAfterReset());
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ref.watch(settingsProvider.select((s) => s.isDark));

    final overlay = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness:
          isDark ? Brightness.light : Brightness.dark,
      systemNavigationBarContrastEnforced: false,
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay,
      child: MaterialApp.router(
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
          //
          // The SMS review overlay sits *above* the navigator so Approve /
          // Reject still shows when Settings or another sheet is open.
          return Stack(
            children: [
              WebResponsiveFrame(child: router ?? const SizedBox.shrink()),
              const SmsExpenseReviewHost(),
            ],
          );
        },
      ),
    );
  }
}
