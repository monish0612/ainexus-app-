import 'package:uuid/uuid.dart';

import '../../../core/services/telegram_logger.dart';
import 'price_models.dart';
import 'store_url.dart';
import 'watch_http_fetcher.dart';
import 'watch_llm.dart';
import 'watch_policy.dart';
import 'watch_prefs.dart';
import 'watch_store.dart';
import 'watch_sync_port.dart';

class WatchCheckResult {
  const WatchCheckResult({
    required this.itemId,
    required this.ok,
    this.price,
    this.oldPrice,
    this.pending = false,
    this.reasons = const [],
    this.error,
  });

  final String itemId;
  final bool ok;
  final double? price;
  final double? oldPrice;
  final bool pending;
  final List<AlertReason> reasons;
  final String? error;
}

/// Orchestrates scrape → policy → persist. UI and WorkManager both call this.
class WatchEngine {
  WatchEngine(
    this._store,
    this._fetcher,
    this._prefs, {
    WatchSyncPort sync = const NoopWatchSync(),
    WatchLlmPort llm = const NoopWatchLlm(),
    String Function()? liteModel,
  })  : _sync = sync,
        _llm = llm,
        _liteModel = liteModel;

  final WatchStorePort _store;
  final WatchHttpFetcher _fetcher;
  final WatchPrefs _prefs;
  final WatchSyncPort _sync;
  final WatchLlmPort _llm;
  final String Function()? _liteModel;
  static const _uuid = Uuid();

  Future<ScrapeHit> scrapeProduct(CanonicalWatchUrl canon) async {
    try {
      return await _fetcher.scrape(canon.url, store: canon.store);
    } on WatchParseMissException catch (e) {
      final hit = await _extractWithLlm(e, fallbackUrl: canon.url);
      if (hit != null) return hit;
      throw WatchScrapeException(e.message);
    }
  }

  Future<ScrapeHit?> _extractWithLlm(
    WatchParseMissException miss, {
    required String fallbackUrl,
  }) async {
    final hit = await _llm.extract(
      url: miss.finalUrl ?? fallbackUrl,
      excerpt: miss.excerpt,
      liteModel: _liteModel?.call(),
    );
    if (hit == null) return null;
    TLog.i(
      'Watch',
      'Gemini extract ₹${hit.price.toStringAsFixed(2)} '
          'conf=${hit.confidence.toStringAsFixed(2)}',
    );
    return hit.toHit().withResolvedUrl(miss.finalUrl ?? fallbackUrl);
  }

  Future<WatchItem> addFromUrl(
    String rawUrl, {
    int? intervalMinutes,
    double? targetPrice,
  }) async {
    var canon = canonicalizeWatchUrl(rawUrl);
    if (canon == null) {
      throw WatchScrapeException(
        'Paste a product page from Amazon, Flipkart, Myntra, Ajio, Nykaa, '
        'or another supported store.',
      );
    }
    final hit = await scrapeProduct(canon);
    canon = preferResolvedCanonical(canon, hit.resolvedUrl);
    return addFromHit(
      canon,
      hit,
      intervalMinutes: intervalMinutes,
      targetPrice: targetPrice,
    );
  }

  Future<WatchItem> addFromHit(
    CanonicalWatchUrl canon,
    ScrapeHit hit, {
    int? intervalMinutes,
    double? targetPrice,
  }) async {
    var item = await _store.insert(
      canon: canon,
      name: hit.name,
      imageUrl: hit.imageUrl,
      price: hit.price,
      source: hit.source,
      score: hit.score,
      availability: hit.availability,
      intervalMinutes: intervalMinutes ?? _prefs.intervalMinutes,
    );
    if (targetPrice != null && targetPrice > 0) {
      await _store.updateItem(item.copyWith(targetPrice: targetPrice));
      item = (await _store.getById(item.id)) ?? item;
    }
    await _sync.enqueueProductUpsert(item);
    return item;
  }

  Future<WatchCheckResult> check(
    WatchItem item, {
    WatchCheckKind kind = WatchCheckKind.periodic,
  }) async {
    if (item.isPaused) {
      return WatchCheckResult(itemId: item.id, ok: true);
    }
    final confirming = item.pendingPrice != null ||
        kind == WatchCheckKind.confirm;
    try {
      final hit = await scrapeProduct(
        CanonicalWatchUrl(
          store: item.store,
          url: item.canonicalUrl,
          productId: item.productId,
        ),
      );
      final upgraded = preferResolvedCanonical(
        CanonicalWatchUrl(
          store: item.store,
          url: item.canonicalUrl,
          productId: item.productId,
        ),
        hit.resolvedUrl,
      );
      if (upgraded.identityKey != item.resolvedIdentity) {
        item = await _store.upgradeIdentity(item, upgraded);
      }
      final decision = decideCheck(
        newPrice: hit.price,
        lastPrice: item.currentPrice,
        score: hit.score,
        confirming: confirming,
        pendingPrice: item.pendingPrice,
      );
      if (decision.failed) {
        await _store.markFailure(
          item,
          confirming
              ? 'Confirm disagreed or empty price'
              : 'Could not confirm price',
          clearPending: confirming,
        );
        return WatchCheckResult(
          itemId: item.id,
          ok: false,
          error: 'Could not confirm price',
        );
      }
      if (decision.pending) {
        await _store.parkPending(item, price: hit.price, error: null);
        TLog.i(
          'Watch',
          'Pending ${item.store.id} ${item.id} ₹${hit.price} '
              'score=${hit.score}',
        );
        return WatchCheckResult(
          itemId: item.id,
          ok: true,
          price: hit.price,
          pending: true,
        );
      }
      final newPrice = decision.price!;
      final oldPrice = item.currentPrice;
      final reasons = decideAlerts(
        product: item,
        oldPrice: oldPrice,
        newPrice: newPrice,
        globalDecrease: _prefs.notifyDecrease,
        globalIncrease: _prefs.notifyIncrease,
        globalTarget: _prefs.notifyTarget,
      );
      await _store.acceptPrice(
        item,
        price: newPrice,
        source: hit.source,
        score: hit.score,
        availability: hit.availability,
      );
      await _sync.enqueueProductUpsert(item);
      if (reasons.isNotEmpty && newPrice != oldPrice) {
        await _store.addAlert(
          WatchAlert(
            id: _uuid.v4(),
            productId: item.id,
            productName: item.name,
            imageUrl: item.imageUrl,
            oldPrice: oldPrice,
            newPrice: newPrice,
            reason: alertReasonLabel(reasons.first),
            createdAt: DateTime.now(),
          ),
        );
      }
      TLog.i(
        'Watch',
        'OK ${item.store.id} ${item.id} '
            '₹${oldPrice.toStringAsFixed(2)}→₹${newPrice.toStringAsFixed(2)} '
            '${hit.source}',
      );
      return WatchCheckResult(
        itemId: item.id,
        ok: true,
        price: newPrice,
        oldPrice: oldPrice,
        reasons: reasons,
      );
    } catch (e) {
      await _store.markFailure(item, e.toString());
      TLog.w('Watch', 'Check failed ${item.id}: $e', error: e);
      return WatchCheckResult(itemId: item.id, ok: false, error: e.toString());
    }
  }

  Future<List<WatchCheckResult>> checkDue({bool force = false}) async {
    if (!_prefs.enabled && !force) return const [];
    final due = force ? await _store.allActive() : await _store.dueItems();
    final out = <WatchCheckResult>[];
    for (var i = 0; i < due.length; i++) {
      final item = due[i];
      final kind = item.pendingPrice != null
          ? WatchCheckKind.confirm
          : (item.consecutiveFailures > 0
              ? WatchCheckKind.retry
              : WatchCheckKind.periodic);
      out.add(await check(item, kind: kind));
      if (i != due.length - 1) {
        await Future<void>.delayed(const Duration(milliseconds: 1200));
      }
    }
    return out;
  }
}
