import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../../core/platform/platform_capabilities.dart';
import '../../../core/services/telegram_logger.dart';
import 'price_models.dart';
import 'price_parse.dart';
import 'watch_policy.dart';
import 'watch_prefs.dart';

const kWatchChannelId = 'nexus_price_alerts';
const kWatchChannelName = 'Price Watch';
const kWatchChannelDesc = 'Alerts when a watched product drops or hits target';
const kWatchNotifBase = 9400;
const kWatchPayloadPrefix = 'watch:';

class WatchNotifier {
  WatchNotifier(this._fln, this._prefs);

  final FlutterLocalNotificationsPlugin _fln;
  final WatchPrefs _prefs;

  static const channel = AndroidNotificationChannel(
    kWatchChannelId,
    kWatchChannelName,
    description: kWatchChannelDesc,
    importance: Importance.high,
  );

  Future<void> ensureChannel() async {
    if (!PlatformCapabilities.canUseNotifications) return;
    final android = _fln.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(channel);
  }

  Future<void> showChange({
    required WatchItem item,
    required double oldPrice,
    required double newPrice,
    required List<AlertReason> reasons,
  }) async {
    if (!PlatformCapabilities.canUseNotifications) return;
    if (reasons.isEmpty) return;
    if (inQuietHours(
      DateTime.now(),
      enabled: _prefs.quietHours,
      start: _prefs.quietStart,
      end: _prefs.quietEnd,
    )) {
      TLog.d('Watch', 'Quiet hours — tray skipped for ${item.id}');
      return;
    }
    final reason = alertReasonLabel(reasons.first);
    final title = '${item.store.label} · $reason';
    final body =
        '${item.name}\n${formatInr(oldPrice)} → ${formatInr(newPrice)}';
    final id = kWatchNotifBase + (item.id.hashCode.abs() % 500);
    await _fln.show(
      id,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          kWatchChannelId,
          kWatchChannelName,
          channelDescription: kWatchChannelDesc,
          importance: Importance.high,
          priority: Priority.high,
          icon: 'ic_notification',
          color: const Color(0xFF0D59F2),
          styleInformation: BigTextStyleInformation(body, contentTitle: title),
        ),
      ),
      payload: '$kWatchPayloadPrefix${item.id}',
    );
  }
}
