import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../platform/platform_capabilities.dart';
import 'telegram_logger.dart';

/// Manages a real Android foreground service during cloud transfers.
///
/// While a transfer is active the app holds a CPU wake-lock **and** a
/// Wi-Fi lock via [flutter_foreground_task], which prevents Android Doze
/// from killing the network connection when the screen is off.
///
/// Progress is shown as the foreground service's notification text.
/// On completion / failure the service is stopped and a normal
/// notification is posted via [flutter_local_notifications].
class TransferNotification {
  TransferNotification._();
  static final instance = TransferNotification._();

  static const _channelId = 'nexus_cloud_transfer';
  static const _channelName = 'Cloud Transfers';
  static const _channelDesc =
      'Upload and download progress for Google Drive files';
  static const _completionNotifId = 9301;
  static const _accent = ui.Color(0xFF0D59F2);
  static const _serviceId = 930;

  bool _serviceRunning = false;
  bool _initialized = false;
  FlutterLocalNotificationsPlugin? _fln;

  void _ensureInit() {
    if (!PlatformCapabilities.canUseForegroundTask) return;
    if (_initialized) return;
    _initialized = true;

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: '${_channelId}_fg',
        channelName: '$_channelName Service',
        channelDescription: 'Keeps file transfers alive in background',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        playSound: false,
        enableVibration: false,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: true,
        eventAction: ForegroundTaskEventAction.nothing(),
      ),
    );
  }

  Future<FlutterLocalNotificationsPlugin> _ensureFln() async {
    if (_fln != null) return _fln!;
    _fln = FlutterLocalNotificationsPlugin();
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _fln!.initialize(const InitializationSettings(android: android));
    return _fln!;
  }

  /// Start the foreground service. Call once when a transfer begins.
  Future<void> startForeground({
    required String title,
    String body = 'Preparing…',
  }) async {
    if (!PlatformCapabilities.canUseForegroundTask) return;
    _ensureInit();
    if (_serviceRunning) {
      await FlutterForegroundTask.updateService(
        notificationTitle: title,
        notificationText: body,
      );
      return;
    }

    try {
      final result = await FlutterForegroundTask.startService(
        serviceId: _serviceId,
        notificationTitle: title,
        notificationText: body,
        callback: _transferServiceCallback,
      );
      _serviceRunning = result is ServiceRequestSuccess;
      if (_serviceRunning) {
        TLog.d('TransferNotif', 'Foreground service started');
      } else {
        TLog.w('TransferNotif', 'Foreground service start returned: $result');
      }
    } catch (e) {
      TLog.w('TransferNotif', 'startForeground failed: $e');
    }
  }

  DateTime _lastUpdate = DateTime(2000);

  /// Update the ongoing foreground notification with progress text.
  /// Throttled to max 2 updates/sec to avoid notification spam.
  Future<void> show({
    required String title,
    required String body,
    required int pct,
    bool force = false,
  }) async {
    if (!PlatformCapabilities.canUseForegroundTask) return;
    final now = DateTime.now();
    if (!force && now.difference(_lastUpdate).inMilliseconds < 500) return;
    _lastUpdate = now;

    if (!_serviceRunning) {
      await startForeground(title: title, body: '$body · $pct%');
      return;
    }

    try {
      await FlutterForegroundTask.updateService(
        notificationTitle: title,
        notificationText: '$body · $pct%',
      );
    } catch (e) {
      TLog.w('TransferNotif', 'show update failed: $e');
    }
  }

  /// Stop the foreground service and show a completion notification.
  Future<void> complete({
    required String title,
    required String body,
  }) async {
    if (!PlatformCapabilities.canUseForegroundTask) return;
    await _stopService();

    try {
      final fln = await _ensureFln();
      const details = AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDesc,
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        autoCancel: true,
        category: AndroidNotificationCategory.status,
        color: _accent,
      );
      await fln.show(
        _completionNotifId,
        title,
        body,
        const NotificationDetails(android: details),
        payload: 'cloud_tab',
      );
    } catch (e) {
      TLog.w('TransferNotif', 'complete notification failed: $e');
    }
  }

  /// Stop the foreground service and show a failure notification.
  Future<void> fail({
    required String title,
    required String body,
  }) async {
    if (!PlatformCapabilities.canUseForegroundTask) return;
    await _stopService();

    try {
      final fln = await _ensureFln();
      const details = AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDesc,
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        autoCancel: true,
        category: AndroidNotificationCategory.error,
        color: _accent,
      );
      await fln.show(
        _completionNotifId,
        title,
        body,
        const NotificationDetails(android: details),
        payload: 'cloud_tab',
      );
    } catch (e) {
      TLog.w('TransferNotif', 'fail notification failed: $e');
    }
  }

  /// Stop the foreground service (e.g. on user cancel).
  Future<void> cancel() async {
    if (!PlatformCapabilities.canUseForegroundTask) return;
    await _stopService();
  }

  Future<void> _stopService() async {
    if (!_serviceRunning) return;
    try {
      await FlutterForegroundTask.stopService();
      _serviceRunning = false;
      TLog.d('TransferNotif', 'Foreground service stopped');
    } catch (e) {
      _serviceRunning = false;
      TLog.w('TransferNotif', 'stopService failed: $e');
    }
  }
}

@pragma('vm:entry-point')
void _transferServiceCallback() {
  FlutterForegroundTask.setTaskHandler(_TransferTaskHandler());
}

class _TransferTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}
