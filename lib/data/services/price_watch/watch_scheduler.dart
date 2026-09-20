import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../../../core/platform/platform_capabilities.dart';
import '../../../core/services/telegram_logger.dart';
import '../../local/database/app_database.dart';
import 'watch_engine.dart';
import 'watch_http_fetcher.dart';
import 'watch_notifier.dart';
import 'watch_prefs.dart';
import 'watch_repository.dart';

const kWatchTask = 'priceWatchCheck';
const kWatchUniqueId = 'app.ainexus.price_watch';

/// Android WorkManager floor. Must stay ≥ 15m — never poll faster.
const kWatchFrequency = Duration(minutes: 15);

/// Runs inside the WorkManager isolate. Opens its own DB connection.
Future<void> runWatchBackgroundCheck() async {
  if (!PlatformCapabilities.canUseWorkmanager) return;
  TLog.init();
  final prefs = await SharedPreferences.getInstance();
  final watchPrefs = WatchPrefs(prefs);
  if (!watchPrefs.enabled) return;

  final db = AppDatabase.background();
  try {
    final repo = WatchRepository(db);
    final engine = WatchEngine(repo, WatchHttpFetcher(), watchPrefs);
    final results = await engine.checkDue();
    if (results.isEmpty) return;

    final fln = FlutterLocalNotificationsPlugin();
    const android = AndroidInitializationSettings('ic_notification');
    await fln.initialize(const InitializationSettings(android: android));
    final notifier = WatchNotifier(fln, watchPrefs);
    await notifier.ensureChannel();

    for (final r in results) {
      if (!r.ok || r.pending || r.reasons.isEmpty || r.price == null) continue;
      final item = await repo.getById(r.itemId);
      if (item == null) continue;
      await notifier.showChange(
        item: item,
        oldPrice: r.oldPrice ?? item.currentPrice,
        newPrice: r.price!,
        reasons: r.reasons,
      );
    }
    TLog.i('Watch', 'Background sweep ${results.length} item(s)');
  } catch (e, st) {
    TLog.e('Watch', 'Background sweep crashed', error: e, st: st);
  } finally {
    await db.close();
  }
}

Future<void> scheduleWatchChecks({bool replace = false}) async {
  if (!PlatformCapabilities.canUseWorkmanager) return;
  await Workmanager().registerPeriodicTask(
    kWatchUniqueId,
    kWatchTask,
    frequency: kWatchFrequency,
    existingWorkPolicy:
        replace ? ExistingWorkPolicy.replace : ExistingWorkPolicy.keep,
    constraints: Constraints(networkType: NetworkType.connected),
  );
}

Future<void> cancelWatchChecks() async {
  if (!PlatformCapabilities.canUseWorkmanager) return;
  await Workmanager().cancelByUniqueName(kWatchUniqueId);
}
