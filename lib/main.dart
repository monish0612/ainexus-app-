import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'bubble/overlay/overlay_app.dart';
import 'core/auth/app_token_store.dart';
import 'core/auth/auth_service.dart';
import 'core/di/injection.dart';
import 'core/platform/platform_capabilities.dart';
import 'core/router/app_router.dart';
import 'core/network/api_client.dart';
import 'core/services/expense_widget_service.dart';
import 'core/services/hold_to_speak_service.dart';
import 'core/services/background_task_coordinator.dart';
import 'core/services/news_summarize_store.dart';
import 'core/services/notification_service.dart';
import 'core/services/notification_tap.dart';
import 'core/services/telegram_logger.dart';
import 'data/services/narration_api.dart';
import 'data/services/narration_audio_handler.dart';
import 'data/services/narration_completion_store.dart';
import 'data/services/narration_download_store.dart';
import 'presentation/screens/settings/settings_controller.dart';

/// Entry point for the floating rephrase bubble's own Flutter engine, launched
/// by RephraseAccessibilityService. Declared here so native can use the plain
/// two-argument DartEntrypoint("overlayMain").
@pragma('vm:entry-point')
void overlayMain() {
  runBubbleOverlay();
}

void main() async {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      GoogleFonts.config.allowRuntimeFetching = false;
      LicenseRegistry.addLicense(() async* {
        for (final name in const [
          'OFL-PlusJakartaSans.txt',
          'OFL-JetBrainsMono.txt',
          'OFL-Lora.txt',
          'OFL-DMSans.txt',
        ]) {
          final license =
              await rootBundle.loadString('google_fonts/$name');
          yield LicenseEntryWithLineBreaks(const ['google_fonts'], license);
        }
      });
      TLog.init();

      FlutterError.onError = (details) {
        FlutterError.presentError(details);
        TLog.fatal(
          'FlutterError',
          details.exceptionAsString(),
          error: details.exception,
          st: details.stack,
        );
      };

      PlatformDispatcher.instance.onError = (error, stack) {
        TLog.fatal('PlatformDispatcher', 'Unhandled platform error',
            error: error, st: stack);
        return true;
      };

      if (!kDebugMode) {
        ErrorWidget.builder = (details) {
          return ColoredBox(
            color: Colors.black,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Something went wrong.\nPlease restart the app.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
            ),
          );
        };
      }

      await initializeDateFormatting('en_IN')
          .timeout(const Duration(seconds: 2), onTimeout: () {});

      SharedPreferences sharedPreferences;
      try {
        sharedPreferences = await SharedPreferences.getInstance()
            .timeout(const Duration(seconds: 3));
      } on TimeoutException {
        TLog.w('Init', 'SharedPreferences slow — retrying');
        sharedPreferences = await SharedPreferences.getInstance();
      }
      TLog.d('Init', 'SharedPreferences loaded');

      // SystemChrome system-UI calls are no-ops on web but we still skip
      // them to avoid noise in browser logs.
      if (PlatformCapabilities.isMobile) {
        unawaited(SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
        ]));
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      }

      // EncryptedSharedPreferences can stall on some OEMs after a process
      // kill. Cap the wait so the native splash cannot freeze forever;
      // authState still updates the router if init finishes late.
      try {
        await AuthService.instance.init().timeout(const Duration(seconds: 3));
      } catch (e) {
        TLog.w('Init', 'Auth init slow or failed, continuing to first frame: $e');
      }
      initializeRouter();
      // Initialise the shared AI-background foreground-task subsystem
      // early so any long-running AI feature (news summarize, online
      // search, URL summarize, follow-up Q&A, expense OCR + smart-parse)
      // can promote itself to a foreground service the first time it
      // needs to. Safe to call before the engine renders;
      // FlutterForegroundTask.init just stashes options.
      BackgroundTaskCoordinator.instance.init();
      unawaited(NarrationCompletionStore.instance.load(sharedPreferences));
      unawaited(NarrationDownloadStore.instance.hydrate(prefs: sharedPreferences));
      TLog.d('Init', 'Auth + Router + ForegroundTask ready');

      runApp(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(sharedPreferences),
            settingsProvider.overrideWith(
              (ref) => SettingsController(
                sharedPreferences,
                ref.watch(userPreferencesServiceProvider),
              ),
            ),
          ],
          child: const NexusAiApp(),
        ),
      );

      TLog.i('Init', 'App launched successfully');
      unawaited(_afterFirstFrame());
    },
    (error, stack) {
      TLog.fatal('Zone', 'Uncaught error', error: error, st: stack);
    },
  );
}

Future<void> _afterFirstFrame() async {
  final painted = Completer<void>();
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!painted.isCompleted) painted.complete();
  });
  try {
    await painted.future.timeout(const Duration(seconds: 2));
  } on TimeoutException {
    TLog.w('Init', 'first frame callback lagged — continuing deferred work');
  }

  try {
    await AppTokenStore.instance.load().timeout(const Duration(seconds: 3));
  } catch (e) {
    TLog.w('Init', 'token store load slow or failed: $e');
  }
  AppTokenStore.instance.refresher = AuthService.instance.refreshAppToken;
  try {
    await AuthService.instance
        .ensureAppToken()
        .timeout(const Duration(seconds: 8));
  } catch (e) {
    TLog.w('Init', 'ensureAppToken slow or failed: $e');
  }
  AppTokenStore.instance.markStartupReady();
  unawaited(ExpenseWidgetService.instance.refreshOnAppStart());
  unawaited(_initNotifications());

  // Speech + AudioService bind Google/media services. Doing that during
  // splash racing AudioServiceActivity is what froze the launch icon until
  // a force-stop. Warm them only after the UI is on screen.
  await Future<void>.delayed(const Duration(milliseconds: 1800));
  unawaited(HoldToSpeakController.warmUp());
  if (PlatformCapabilities.canUseAudioService) {
    unawaited(initNarrationAudio(NarrationApi(ApiClient())));
  }
}

Future<void> _initNotifications() async {
  try {
    await NotificationService.instance.initialize(
      onTap: (payload) {
        if (payload == null) return;
        if (payload == NewsSummarizeStore.kReopenPayload) {
          // Mark the intent BEFORE the broadcast so the News screen sees
          // the flag the very first time it rebuilds, even if the stream
          // event lost the race to the screen mounting.
          NewsSummarizeStore.instance.requestReaderReopen();
          publishNotificationRoute(payload);
        } else if (isRoutableNotificationPayload(payload)) {
          publishNotificationRoute(payload);
        }
      },
    );
    await NotificationService.instance.scheduleAll();
    TLog.i('Init', 'Notifications scheduled (expense + news)');
  } catch (e, st) {
    TLog.w('Init', 'Notification setup failed: $e', error: e, st: st);
  }
}
