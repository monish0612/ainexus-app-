import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../platform/platform_capabilities.dart';
import 'telegram_logger.dart';

/// Foreground-service plumbing shared by every long-running AI task
/// (news summarize, online search, URL summarize, follow-up Q&A, expense
/// OCR + smart-parse, etc).
///
/// ## Why a single shared service
/// `flutter_foreground_task` only allows ONE foreground service per
/// process. Every long-running AI feature in the app needs the same
/// "don't let Doze kill my HTTP socket" guarantee, so we share a single
/// service whose lifetime is owned by [BackgroundTaskCoordinator].
///
/// ## What this file is for
/// - Declares the `@pragma('vm:entry-point')` callback the OS uses to
///   re-enter the Dart isolate when the service starts.
/// - Provides [initBackgroundForegroundTask] which configures the
///   notification channel + foreground-task options once at app startup.
///
/// We deliberately do NOT move the actual AI work into the task handler's
/// isolate — that runs in a separate engine without our Riverpod
/// container, repository, or in-memory state. The handler is intentionally
/// inert; all work continues to run in the main isolate, which keeps
/// running because the OS sees the foreground service.

/// Notification channel used by the shared foreground service. We keep a
/// stable, generic id so Android's user-visible channel listing reads
/// "Background AI Tasks" rather than feature-specific names.
const String _kAiBgChannelId = 'nexus_ai_background';
const String _kAiBgChannelName = 'Background AI Tasks';
const String _kAiBgChannelDesc =
    'Keeps AI tasks (search, summarize, follow-up Q&A, OCR) running while '
    'the app is in the background or the screen is off.';

@pragma('vm:entry-point')
void aiBackgroundStartCallback() {
  FlutterForegroundTask.setTaskHandler(_AiBackgroundNoopHandler());
}

/// Backwards-compat alias for the legacy News-summarize callback name.
/// Kept so any cached `Intent`/`Service` start state pointing at the old
/// entry-point continues to resolve to a working handler instead of
/// crashing the process.
@pragma('vm:entry-point')
void newsSummarizeStartCallback() {
  aiBackgroundStartCallback();
}

/// Inert task handler — its sole purpose is to satisfy the
/// foreground-service contract. All actual AI work happens back in the
/// main isolate where the various stores live.
class _AiBackgroundNoopHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    if (kDebugMode) {
      // ignore: avoid_print
      print('[AIBgService] started by ${starter.name}');
    }
  }

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    if (kDebugMode) {
      // ignore: avoid_print
      print('[AIBgService] destroyed (timeout=$isTimeout)');
    }
  }
}

/// Configures the foreground-task subsystem. Must be called once at app
/// startup before any feature can promote itself to a foreground service.
///
/// Safe to call repeatedly; [FlutterForegroundTask.init] just stores the
/// options. No-ops on platforms that do not support the foreground
/// service (web, future iOS / desktop builds).
void initBackgroundForegroundTask() {
  if (!PlatformCapabilities.canUseForegroundTask) return;
  try {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: _kAiBgChannelId,
        channelName: _kAiBgChannelName,
        channelDescription: _kAiBgChannelDesc,
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
        // so CPU + network stay alive while we crunch through tasks.
        allowWakeLock: true,
        allowWifiLock: true,
        // If the user kills the app from recents, also stop us. We do not
        // want a phantom service ticking after the user has clearly
        // walked away from the app.
        stopWithTask: true,
      ),
    );
    TLog.d('BgFgTask', 'foreground-task subsystem initialised');
  } catch (e, st) {
    TLog.w('BgFgTask', 'foreground-task init failed: $e', error: e, st: st);
  }
}

/// Backwards-compat alias for the legacy initializer name. Older callers
/// (or out-of-tree integrations) that referenced
/// `initNewsSummarizeForegroundTask()` continue to work.
void initNewsSummarizeForegroundTask() => initBackgroundForegroundTask();
