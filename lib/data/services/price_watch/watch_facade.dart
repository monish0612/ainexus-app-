import 'price_models.dart';
import 'store_url.dart';
import 'watch_engine.dart';
import 'watch_http_fetcher.dart';
import 'watch_prefs.dart';
import 'watch_store.dart';
import 'watch_sync_port.dart';

class WatchPreview {
  const WatchPreview({required this.canon, required this.hit});

  final CanonicalWatchUrl canon;
  final ScrapeHit hit;
}

/// Thin API for screens. Widgets talk to this, not Dio or Drift.
class WatchFacade {
  WatchFacade({
    required WatchEngine engine,
    required WatchStorePort store,
    required WatchPrefs prefs,
    WatchSyncPort sync = const NoopWatchSync(),
  })  : _engine = engine,
        _store = store,
        _prefs = prefs,
        _sync = sync;

  final WatchEngine _engine;
  final WatchStorePort _store;
  final WatchPrefs _prefs;
  final WatchSyncPort _sync;

  Stream<List<WatchItem>> items() => _store.watchItems();
  Stream<int> unreadAlertCount() => _store.unreadAlertCount();
  Stream<List<WatchPricePoint>> history(String productId) =>
      _store.historyStream(productId);
  Stream<List<WatchAlert>> alerts() => _store.alerts();

  Future<WatchPreview> preview(String rawUrl) async {
    var canon = canonicalizeWatchUrl(rawUrl);
    if (canon == null) {
      throw WatchScrapeException(
        'Need a product page — search, category and restaurant menus will not work.',
      );
    }
    final hit = await _engine.scrapeProduct(canon);
    canon = preferResolvedCanonical(canon, hit.resolvedUrl);
    return WatchPreview(canon: canon, hit: hit);
  }

  Future<WatchItem> addFromUrl(String rawUrl, {double? targetPrice}) {
    return _engine.addFromUrl(rawUrl, targetPrice: targetPrice);
  }

  Future<WatchItem> addFromPreview(
    WatchPreview preview, {
    double? targetPrice,
  }) {
    return _engine.addFromHit(
      preview.canon,
      preview.hit,
      intervalMinutes: _prefs.intervalMinutes,
      targetPrice: targetPrice,
    );
  }

  Future<WatchCheckResult> checkNow(WatchItem item) {
    return _engine.check(item, kind: WatchCheckKind.manual);
  }

  Future<List<WatchCheckResult>> checkDue({bool force = false}) {
    return _engine.checkDue(force: force);
  }

  Future<void> delete(String id) async {
    final item = await _store.getById(id);
    await _store.deleteItem(id);
    if (item != null) {
      await _sync.enqueueTombstone(
        item.resolvedIdentity,
        DateTime.now().toUtc(),
      );
    }
  }

  Future<void> setPaused(WatchItem item, bool paused) {
    return _store.updateItem(
      item.copyWith(
        isPaused: paused,
        manuallyPaused: paused,
        pausedAt: paused ? DateTime.now() : null,
        clearPausedAt: !paused,
      ),
    );
  }

  Future<void> setTarget(WatchItem item, double? target) {
    return _store.updateItem(
      item.copyWith(targetPrice: target, clearTarget: target == null),
    );
  }

  Future<void> markAlertsRead() => _store.markAlertsRead();

  Future<void> applyIntervalToAll(int minutes) =>
      _store.applyIntervalToAll(minutes);
}
