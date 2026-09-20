import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/injection.dart';
import '../../../core/network/api_client.dart';
import '../../../core/services/notification_service.dart';
import '../../../data/services/price_watch/history_series.dart';
import '../../../data/services/price_watch/price_models.dart';
import '../../../data/services/price_watch/watch_engine.dart';
import '../../../data/services/price_watch/watch_facade.dart';
import '../../../data/services/price_watch/watch_http_fetcher.dart';
import '../../../data/services/price_watch/watch_llm.dart';
import '../../../data/services/price_watch/watch_notifier.dart';
import '../../../data/services/price_watch/watch_prefs.dart';
import '../../../data/services/price_watch/watch_repository.dart';
import '../../../data/services/price_watch/watch_sync_port.dart';
import '../settings/settings_controller.dart';
import 'watch_navigator.dart';

final watchPrefsProvider = Provider<WatchPrefs>((ref) {
  return WatchPrefs(ref.watch(sharedPreferencesProvider));
});

final watchRepositoryProvider = Provider<WatchRepository>((ref) {
  return WatchRepository(ref.watch(appDatabaseProvider));
});

final watchFetcherProvider = Provider<WatchHttpFetcher>((ref) {
  return WatchHttpFetcher();
});

final watchSyncProvider = Provider<WatchSyncPort>((ref) {
  return const NoopWatchSync();
});

final watchLlmProvider = Provider<WatchLlmPort>((ref) {
  return GeminiWatchLlm(ref.watch(apiClientProvider));
});

final watchEngineProvider = Provider<WatchEngine>((ref) {
  return WatchEngine(
    ref.watch(watchRepositoryProvider),
    ref.watch(watchFetcherProvider),
    ref.watch(watchPrefsProvider),
    sync: ref.watch(watchSyncProvider),
    llm: ref.watch(watchLlmProvider),
    liteModel: () => ref.read(settingsProvider).liteModel,
  );
});

/// Reuse the existing Watch route, then deliver a share URL / notification id.
void openWatch(
  BuildContext context,
  WidgetRef ref, {
  String? seedUrl,
  String? productId,
}) {
  WatchNavigator.open(context);
  if (seedUrl != null && seedUrl.trim().isNotEmpty) {
    ref.read(pendingWatchUrlProvider.notifier).state = seedUrl;
  }
  if (productId != null && productId.trim().isNotEmpty) {
    ref.read(pendingWatchProductIdProvider.notifier).state = productId;
  }
}

final watchFacadeProvider = Provider<WatchFacade>((ref) {
  return WatchFacade(
    engine: ref.watch(watchEngineProvider),
    store: ref.watch(watchRepositoryProvider),
    prefs: ref.watch(watchPrefsProvider),
    sync: ref.watch(watchSyncProvider),
  );
});

final watchNotifierProvider = Provider<WatchNotifier>((ref) {
  return WatchNotifier(
    NotificationService.instance.plugin,
    ref.watch(watchPrefsProvider),
  );
});

final watchItemsProvider = StreamProvider((ref) {
  return ref.watch(watchFacadeProvider).items();
});

final watchUnreadProvider = StreamProvider<int>((ref) {
  return ref.watch(watchFacadeProvider).unreadAlertCount();
});

final watchHistoryProvider =
    StreamProvider.family<List<WatchPricePoint>, String>((ref, productId) {
  return ref.watch(watchFacadeProvider).history(productId);
});

final pendingWatchUrlProvider = StateProvider<String?>((ref) => null);
final pendingWatchProductIdProvider = StateProvider<String?>((ref) => null);

final watchChartRangeProvider =
    StateProvider.family<HistoryRange, String>((ref, productId) {
  return HistoryRange.all;
});
