import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/auth/app_token_store.dart';
import 'core/auth/auth_service.dart';
import 'core/di/injection.dart';
import 'core/platform/platform_capabilities.dart';
import 'core/router/app_router.dart';
import 'core/services/expense_widget_service.dart';
import 'core/services/hold_to_speak_service.dart';
import 'core/services/news_summarize_fg_task.dart';
import 'core/services/news_summarize_store.dart';
import 'core/services/notification_service.dart';
import 'core/services/telegram_logger.dart';
import 'presentation/screens/settings/settings_controller.dart';

void main() async {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
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

      await initializeDateFormatting('en_IN');

      final sharedPreferences = await SharedPreferences.getInstance();
      TLog.d('Init', 'SharedPreferences loaded');

      // SystemChrome system-UI calls are no-ops on web but we still skip
      // them to avoid noise in browser logs.
      if (PlatformCapabilities.isMobile) {
        await SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
        ]);

        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      }

      await AuthService.instance.init();
      // Wire the server-token store: load any persisted JWT, let the network
      // layer re-mint it on a 401, and back-fill a token for a session that
      // predates token support. All best-effort — never blocks startup.
      await AppTokenStore.instance.load();
      AppTokenStore.instance.refresher = AuthService.instance.refreshAppToken;
      unawaited(AuthService.instance.ensureAppToken());
      initializeRouter();
      // Initialise the shared AI-background foreground-task subsystem
      // early so any long-running AI feature (news summarize, online
      // search, URL summarize, follow-up Q&A, expense OCR + smart-parse)
      // can promote itself to a foreground service the first time it
      // needs to. Safe to call before the engine renders;
      // FlutterForegroundTask.init just stashes options.
      initBackgroundForegroundTask();
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

      unawaited(ExpenseWidgetService.instance.refreshOnAppStart());
      unawaited(_initNotifications());
      // Pre-warm the speech engine so the first hold-to-speak press doesn't
      // pay a 1-2 s cold-start penalty (binding the native recognizer).
      unawaited(HoldToSpeakController.warmUp());
    },
    (error, stack) {
      TLog.fatal('Zone', 'Uncaught error', error: error, st: stack);
    },
  );
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
          notificationPayloadStream.add(payload);
        } else if (payload == 'expense_tab' ||
            payload == 'news_tab' ||
            payload == 'tutor_tab') {
          notificationPayloadStream.add(payload);
        }
      },
    );
    await NotificationService.instance.scheduleAll();
    TLog.i('Init', 'Notifications scheduled (expense + news)');
  } catch (e, st) {
    TLog.w('Init', 'Notification setup failed: $e', error: e, st: st);
  }
}
