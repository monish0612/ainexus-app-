import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../platform/platform_capabilities.dart';
import 'telegram_logger.dart';

/// Foreground-service plumbing for the News > For You "Summarize" feature.
///
/// Why this exists at all:
///   The summarize session is a series of HTTP calls fired from the main
///   isolate by [NewsSummarizeStore]. On Android, once the user backgrounds
///   the app or locks the screen, the OS can put the process into App Standby
///   / Doze within seconds — at which point in-flight sockets stall and the
///   summarize pipeline silently dies until the user returns. That violates
///   the "production grade, runs even with the screen off" requirement.
///
/// The fix is the standard Android pattern: promote the work to a foreground
/// service (an ongoing notification that tells the OS "this user-visible job
/// is running, do not throttle me"). With the service active, the existing
/// summarize logic in the main isolate keeps running normally even when the
/// app is minimised, the screen is off, or the phone is locked.
///
/// We deliberately do NOT move the summarize logic into the task handler's
/// isolate. The handler runs in a separate engine without our Riverpod
/// container, repository, or in-memory state — running it there would mean
/// reimplementing the entire session orchestrator with cross-isolate IPC.
/// Instead we use the service as a "process keep-alive" only: the handler
/// is intentionally inert and just exists because Android requires one.

@pragma('vm:entry-point')
void newsSummarizeStartCallback() {
  FlutterForegroundTask.setTaskHandler(_NewsSummarizeNoopHandler());
}

/// Inert task handler — its sole purpose is to satisfy the foreground-service
/// contract. All actual work happens back in the main isolate where
/// [NewsSummarizeStore] lives.
class _NewsSummarizeNoopHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    if (kDebugMode) {
      // ignore: avoid_print
      print('[NewsSummarizeFG] service started by ${starter.name}');
    }
  }

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    if (kDebugMode) {
      // ignore: avoid_print
      print('[NewsSummarizeFG] service destroyed (timeout=$isTimeout)');
    }
  }
}

/// Configures the foreground-task subsystem. Must be called once at app
/// startup before any session can promote itself to a foreground service.
///
/// Safe to call repeatedly; [FlutterForegroundTask.init] just stores the
/// options. No-ops on platforms that do not support the foreground service
/// (web, future iOS / desktop builds).
void initNewsSummarizeForegroundTask() {
  if (!PlatformCapabilities.canUseForegroundTask) return;
  try {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'nexus_news_summarize',
        channelName: 'News Summarizer',
        channelDescription:
            'Keeps the summarize task running while the app is in the background',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
        showBadge: false,
        playSound: false,
        enableVibration: false,
        visibility: NotificationVisibility.VISIBILITY_PUBLIC,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        // The whole point of this service is that the OS does not put us
        // into Doze mid-batch — give the OS the explicit wakelock contract
        // so CPU + network stay alive while we crunch through the pile.
        allowWakeLock: true,
        allowWifiLock: true,
        // If the user kills the app from recents, also stop us. We do not
        // want a phantom service ticking after the user has clearly walked
        // away from the app.
        stopWithTask: true,
      ),
    );
    TLog.d('NewsSummarize', 'foreground-task subsystem initialised');
  } catch (e, st) {
    TLog.w('NewsSummarize', 'foreground-task init failed: $e',
        error: e, st: st);
  }
}
