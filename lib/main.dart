import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/auth/auth_service.dart';
import 'core/di/injection.dart';
import 'core/platform/platform_capabilities.dart';
import 'core/router/app_router.dart';
import 'core/services/expense_widget_service.dart';
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
      initializeRouter();
      TLog.d('Init', 'Auth + Router ready');

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
        if (payload == 'expense_tab' ||
            payload == 'news_tab' ||
            payload == 'tutor_tab') {
          notificationPayloadStream.add(payload!);
        }
      },
    );
    await NotificationService.instance.scheduleAll();
    TLog.i('Init', 'Notifications scheduled (expense + news)');
  } catch (e, st) {
    TLog.w('Init', 'Notification setup failed: $e', error: e, st: st);
  }
}
