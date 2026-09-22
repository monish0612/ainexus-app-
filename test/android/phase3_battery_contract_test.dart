import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Locks Phase 3 battery / background-work contracts against the live files.
void main() {
  late String overlayController;
  late String a11yService;
  late String rephraseXml;
  late String tlog;
  late String overlayApp;
  late String watchScheduler;
  late String expenseWidget;
  late String savedSearch;
  late String expenseRepo;
  late String apiClient;

  setUpAll(() {
    overlayController = File(
      'android/app/src/main/kotlin/app/ainexus/ai_nexus/bubble/OverlayController.kt',
    ).readAsStringSync();
    a11yService = File(
      'android/app/src/main/kotlin/app/ainexus/ai_nexus/bubble/RephraseAccessibilityService.kt',
    ).readAsStringSync();
    rephraseXml =
        File('android/app/src/main/res/xml/rephrase_service.xml').readAsStringSync();
    tlog = File('lib/core/services/telegram_logger.dart').readAsStringSync();
    overlayApp = File('lib/bubble/overlay/overlay_app.dart').readAsStringSync();
    watchScheduler =
        File('lib/data/services/price_watch/watch_scheduler.dart')
            .readAsStringSync();
    expenseWidget =
        File('android/app/src/main/res/xml/widget_expense_info.xml')
            .readAsStringSync();
    savedSearch =
        File('lib/core/services/saved_search_store.dart').readAsStringSync();
    expenseRepo =
        File('lib/data/repositories/expense_repository.dart').readAsStringSync();
    apiClient = File('lib/core/network/api_client.dart').readAsStringSync();
  });

  group('3A overlay engine', () {
    test('does not warm the engine while the bubble is disabled', () {
      expect(overlayController, contains('BubblePrefs.isEnabled(context)'));
      expect(overlayController, contains('IDLE_DESTROY_MS = 120_000L'));
      expect(overlayController, contains('appIsPaused()'));
      expect(overlayController, contains('appIsResumed()'));
    });

    test('accessibility connect no longer warms the overlay engine', () {
      expect(a11yService, isNot(contains('controller.warm()')));
      expect(a11yService, contains('ensureBridge()'));
    });
  });

  group('3B accessibility cost', () {
    test('keeps WINDOWS_CHANGED and raises notificationTimeout', () {
      expect(rephraseXml, contains('typeWindowsChanged'));
      expect(rephraseXml, contains('android:notificationTimeout="500"'));
      expect(a11yService, contains('WINDOWS_CACHE_MS = 250L'));
      expect(a11yService, contains('WindowGate.eventGatesOpen'));
    });
  });

  group('3C saved search poll', () {
    test('foreground interval is 120s with 600s backoff ceiling', () {
      expect(
        savedSearch,
        contains('const kSavedSearchForegroundSync = Duration(seconds: 120)'),
      );
      expect(
        savedSearch,
        contains('const kSavedSearchForegroundSyncMax = Duration(seconds: 600)'),
      );
      expect(savedSearch, contains('_stopTimers()'));
      expect(
        savedSearch,
        contains('GET /api/v1/saved-searches has no `since`'),
      );
    });
  });

  group('3D telegram logging', () {
    test('token and chat id come from dart-define with remote off by default', () {
      expect(
        tlog,
        contains("bool.fromEnvironment('TLOG_REMOTE', defaultValue: false)"),
      );
      expect(
        tlog,
        contains("String.fromEnvironment('TLOG_BOT_TOKEN')"),
      );
      expect(
        tlog,
        contains("String.fromEnvironment('TLOG_CHAT_ID')"),
      );
      expect(
        RegExp(r'\d{8,}:[A-Za-z0-9_-]{30,}').hasMatch(tlog),
        isFalse,
      );
    });

    test('overlay and WorkManager isolates never enable remote TLog', () {
      expect(overlayApp, contains('TLog.init(allowRemote: false)'));
      expect(watchScheduler, contains('TLog.init(allowRemote: false)'));
    });

    test('HTTP request/response debug logs are gated', () {
      expect(apiClient, contains('kDebugMode || TLog.remoteEnabled'));
    });
  });

  group('3E secondary battery', () {
    test('expense widget is not on a 30-minute OS poll', () {
      expect(expenseWidget, contains('android:updatePeriodMillis="0"'));
      expect(expenseRepo, contains('subtract(const Duration(hours: 36))'));
    });

    test('price-watch WorkManager waits for battery-not-low', () {
      expect(watchScheduler, contains('requiresBatteryNotLow: true'));
      expect(
        watchScheduler,
        contains('const kWatchFrequency = Duration(minutes: 15)'),
      );
    });
  });
}
