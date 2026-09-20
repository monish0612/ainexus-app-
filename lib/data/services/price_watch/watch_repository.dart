import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/services/telegram_logger.dart';
import '../../local/database/app_database.dart' hide WatchAlert;
import 'price_models.dart';
import 'store_url.dart';
import 'watch_policy.dart';
import 'watch_store.dart';

export 'watch_store.dart' show WatchDuplicateException, WatchStorePort;

class WatchRepository implements WatchStorePort {
  WatchRepository(this._db);

  final AppDatabase _db;
  static const _uuid = Uuid();
  static const _tag = 'WatchRepo';

  @override
  Stream<List<WatchItem>> watchItems() {
    return (_db.select(_db.watchProducts)
          ..orderBy([
            (t) => OrderingTerm.desc(t.isPinned),
            (t) => OrderingTerm.desc(t.pinnedAt),
            (t) => OrderingTerm.desc(t.createdAt),
          ]))
        .watch()
        .map((rows) => rows.map(_fromRow).toList());
  }

  @override
  Stream<int> unreadAlertCount() {
    final count = _db.watchAlerts.id.count();
    final q = _db.selectOnly(_db.watchAlerts)
      ..addColumns([count])
      ..where(_db.watchAlerts.isRead.equals(false));
    return q.watchSingle().map((row) => row.read(count) ?? 0);
  }

  @override
  Future<WatchItem?> getById(String id) async {
    final row = await (_db.select(_db.watchProducts)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    return row == null ? null : _fromRow(row);
  }

  @override
  Future<WatchItem?> getByIdentity(String identityKey) async {
    if (identityKey.isEmpty) return null;
    final row = await (_db.select(_db.watchProducts)
          ..where((t) => t.identityKey.equals(identityKey)))
        .getSingleOrNull();
    return row == null ? null : _fromRow(row);
  }

  @override
  Future<List<WatchItem>> allActive() async {
    final rows = await (_db.select(_db.watchProducts)
          ..where((t) => t.isPaused.equals(false)))
        .get();
    return rows.map(_fromRow).toList();
  }

  @override
  Future<List<WatchItem>> dueItems({DateTime? now}) async {
    final rows = await (_db.select(_db.watchProducts)
          ..where((t) => t.isPaused.equals(false)))
        .get();
    final at = now ?? DateTime.now();
    return rows.map(_fromRow).where((p) {
      if (p.checkIntervalMinutes <= 0 && p.pendingPrice == null) return false;
      if (p.pendingPrice != null) {
        if (p.pendingPriceAt == null) return true;
        return at.difference(p.pendingPriceAt!) >= kConfirmDelay;
      }
      if (p.consecutiveFailures > 0 && p.consecutiveFailures <= kMaxRetries) {
        return at.difference(p.lastChecked) >= kRetryDelay;
      }
      if (p.checkIntervalMinutes <= 0) return false;
      return at.difference(p.lastChecked) >=
          Duration(minutes: p.checkIntervalMinutes);
    }).toList();
  }

  @override
  Future<WatchItem> insert({
    required CanonicalWatchUrl canon,
    required String name,
    required String imageUrl,
    required double price,
    required String source,
    required int score,
    String? availability,
    int intervalMinutes = 60,
  }) async {
    final key = canon.identityKey;
    final byKey = await getByIdentity(key);
    if (byKey != null) {
      throw WatchDuplicateException(
        canon.url,
        existingId: byKey.id,
        identityKey: key,
      );
    }
    final existing = await (_db.select(_db.watchProducts)
          ..where((t) => t.canonicalUrl.equals(canon.url)))
        .getSingleOrNull();
    if (existing != null) {
      throw WatchDuplicateException(
        canon.url,
        existingId: existing.id,
        identityKey: existing.identityKey,
      );
    }

    final id = _uuid.v4();
    final now = DateTime.now().toUtc().toIso8601String();
    await _db.into(_db.watchProducts).insert(
          WatchProductsCompanion.insert(
            id: id,
            name: name.isEmpty ? canon.store.label : name,
            url: canon.url,
            canonicalUrl: canon.url,
            store: canon.store.id,
            productId: Value(canon.productId),
            imageUrl: Value(imageUrl),
            currentPrice: price,
            basePrice: price,
            lastChecked: now,
            createdAt: now,
            lastSource: Value(source),
            lastScore: Value(score),
            availability: Value(availability),
            checkIntervalMinutes: Value(intervalMinutes),
            identityKey: Value(key),
            updatedAt: Value(now),
            rev: const Value(1),
          ),
        );
    await _appendHistory(id, price, source);
    TLog.i(_tag, 'Added ${canon.store.id} $id ₹$price key=$key');
    return (await getById(id))!;
  }

  @override
  Future<void> updateItem(WatchItem item) async {
    await (_db.update(_db.watchProducts)..where((t) => t.id.equals(item.id)))
        .write(_toCompanion(item, bumpRev: true));
  }

  @override
  Future<void> applyIntervalToAll(int minutes) async {
    final n = minutes.clamp(kMinIntervalMinutes, kMaxIntervalMinutes);
    final now = DateTime.now().toUtc().toIso8601String();
    await (_db.update(_db.watchProducts)).write(
      WatchProductsCompanion(
        checkIntervalMinutes: Value(n),
        updatedAt: Value(now),
      ),
    );
  }

  @override
  Future<void> deleteItem(String id) async {
    final item = await getById(id);
    await _db.transaction(() async {
      if (item != null && item.resolvedIdentity.isNotEmpty) {
        await _db.into(_db.watchTombstones).insertOnConflictUpdate(
              WatchTombstonesCompanion.insert(
                identityKey: item.resolvedIdentity,
                deletedAt: DateTime.now().toUtc().toIso8601String(),
              ),
            );
      }
      await (_db.delete(_db.watchPriceHistory)
            ..where((t) => t.productId.equals(id)))
          .go();
      await (_db.delete(_db.watchAlerts)..where((t) => t.productId.equals(id)))
          .go();
      await (_db.delete(_db.watchProducts)..where((t) => t.id.equals(id))).go();
    });
    TLog.i(_tag, 'Deleted $id');
  }

  @override
  Future<WatchItem> upgradeIdentity(
    WatchItem item,
    CanonicalWatchUrl canon,
  ) async {
    final key = canon.identityKey;
    if (key.isEmpty || key == item.resolvedIdentity) return item;
    final clash = await getByIdentity(key);
    if (clash != null && clash.id != item.id) return item;
    final now = DateTime.now().toUtc().toIso8601String();
    await (_db.update(_db.watchProducts)..where((t) => t.id.equals(item.id)))
        .write(
      WatchProductsCompanion(
        url: Value(canon.url),
        canonicalUrl: Value(canon.url),
        store: Value(canon.store.id),
        productId: Value(canon.productId),
        identityKey: Value(key),
        updatedAt: Value(now),
        rev: Value(item.rev + 1),
      ),
    );
    return (await getById(item.id)) ?? item;
  }

  @override
  Future<void> acceptPrice(
    WatchItem item, {
    required double price,
    required String source,
    required int score,
    String? availability,
  }) async {
    final now = DateTime.now().toUtc();
    await (_db.update(_db.watchProducts)..where((t) => t.id.equals(item.id)))
        .write(
      WatchProductsCompanion(
        currentPrice: Value(price),
        lastChecked: Value(now.toIso8601String()),
        lastSource: Value(source),
        lastScore: Value(score),
        consecutiveFailures: const Value(0),
        lastCheckError: const Value(null),
        pendingPrice: const Value(null),
        pendingPriceAt: const Value(null),
        availability: Value(availability),
        updatedAt: Value(now.toIso8601String()),
        rev: Value(item.rev + 1),
      ),
    );
    await _appendHistory(item.id, price, source);
  }

  @override
  Future<void> parkPending(
    WatchItem item, {
    required double price,
    required String? error,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await (_db.update(_db.watchProducts)..where((t) => t.id.equals(item.id)))
        .write(
      WatchProductsCompanion(
        pendingPrice: Value(price),
        pendingPriceAt: Value(now),
        lastChecked: Value(now),
        lastCheckError: Value(error),
        updatedAt: Value(now),
        rev: Value(item.rev + 1),
      ),
    );
  }

  @override
  Future<void> markFailure(
    WatchItem item,
    String error, {
    bool clearPending = false,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await (_db.update(_db.watchProducts)..where((t) => t.id.equals(item.id)))
        .write(
      WatchProductsCompanion(
        consecutiveFailures: Value(item.consecutiveFailures + 1),
        lastCheckError: Value(error),
        lastChecked: Value(now),
        pendingPrice: clearPending ? const Value(null) : const Value.absent(),
        pendingPriceAt:
            clearPending ? const Value(null) : const Value.absent(),
        updatedAt: Value(now),
        rev: Value(item.rev + 1),
      ),
    );
  }

  Future<void> _appendHistory(String productId, double price, String source) {
    return _db.into(_db.watchPriceHistory).insert(
          WatchPriceHistoryCompanion.insert(
            id: _uuid.v4(),
            productId: productId,
            price: price,
            checkedAt: DateTime.now().toUtc().toIso8601String(),
            source: Value(source),
          ),
        );
  }

  @override
  Future<List<WatchPricePoint>> history(
    String productId, {
    DateTime? from,
    int? limit,
  }) {
    final q = _db.select(_db.watchPriceHistory)
      ..where((t) => t.productId.equals(productId))
      ..orderBy([(t) => OrderingTerm.desc(t.checkedAt)]);
    if (from != null) {
      q.where((t) => t.checkedAt.isBiggerOrEqualValue(from.toUtc().toIso8601String()));
    }
    if (limit != null) q.limit(limit);
    return q.get().then((rows) => rows.map(_point).toList());
  }

  @override
  Stream<List<WatchPricePoint>> historyStream(String productId) {
    return (_db.select(_db.watchPriceHistory)
          ..where((t) => t.productId.equals(productId))
          ..orderBy([(t) => OrderingTerm.asc(t.checkedAt)]))
        .watch()
        .map((rows) => rows.map(_point).toList());
  }

  WatchPricePoint _point(WatchPriceHistoryData r) {
    return WatchPricePoint(
      id: r.id,
      productId: r.productId,
      price: r.price,
      checkedAt: DateTime.parse(r.checkedAt),
      source: r.source,
    );
  }

  @override
  Future<void> addAlert(WatchAlert alert) {
    return _db.into(_db.watchAlerts).insert(
          WatchAlertsCompanion.insert(
            id: alert.id,
            productId: alert.productId,
            productName: alert.productName,
            imageUrl: Value(alert.imageUrl),
            oldPrice: alert.oldPrice,
            newPrice: alert.newPrice,
            reason: alert.reason,
            createdAt: alert.createdAt.toUtc().toIso8601String(),
          ),
        );
  }

  @override
  Stream<List<WatchAlert>> alerts() {
    return (_db.select(_db.watchAlerts)
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .watch()
        .map(
          (rows) => rows
              .map(
                (r) => WatchAlert(
                  id: r.id,
                  productId: r.productId,
                  productName: r.productName,
                  imageUrl: r.imageUrl,
                  oldPrice: r.oldPrice,
                  newPrice: r.newPrice,
                  reason: r.reason,
                  createdAt: DateTime.parse(r.createdAt),
                  isRead: r.isRead,
                ),
              )
              .toList(),
        );
  }

  @override
  Future<void> markAlertsRead() async {
    await (_db.update(_db.watchAlerts)..where((t) => t.isRead.equals(false)))
        .write(const WatchAlertsCompanion(isRead: Value(true)));
  }

  WatchItem _fromRow(WatchProduct row) {
    final store = WatchStore.fromId(row.store) ?? WatchStore.other;
    return WatchItem(
      id: row.id,
      name: row.name,
      url: row.url,
      canonicalUrl: row.canonicalUrl,
      store: store,
      productId: row.productId,
      identityKey: row.identityKey.isEmpty
          ? watchIdentityKey(store, row.productId, row.canonicalUrl)
          : row.identityKey,
      updatedAt: row.updatedAt == null ? null : DateTime.tryParse(row.updatedAt!),
      rev: row.rev,
      imageUrl: row.imageUrl,
      currentPrice: row.currentPrice,
      basePrice: row.basePrice,
      lastChecked: DateTime.tryParse(row.lastChecked) ?? DateTime.now(),
      createdAt: DateTime.tryParse(row.createdAt) ?? DateTime.now(),
      targetPrice: row.targetPrice,
      notifyOnDecrease: row.notifyOnDecrease,
      notifyOnIncrease: row.notifyOnIncrease,
      notifyOnTarget: row.notifyOnTarget,
      checkIntervalMinutes: row.checkIntervalMinutes,
      isPaused: row.isPaused,
      isPinned: row.isPinned,
      manuallyPaused: row.manuallyPaused,
      pausedAt: row.pausedAt == null ? null : DateTime.tryParse(row.pausedAt!),
      pinnedAt: row.pinnedAt == null ? null : DateTime.tryParse(row.pinnedAt!),
      pendingPrice: row.pendingPrice,
      pendingPriceAt: row.pendingPriceAt == null
          ? null
          : DateTime.tryParse(row.pendingPriceAt!),
      consecutiveFailures: row.consecutiveFailures,
      lastCheckError: row.lastCheckError,
      availability: row.availability,
      currencyCode: row.currencyCode,
      lastSource: row.lastSource,
      lastScore: row.lastScore,
    );
  }

  WatchProductsCompanion _toCompanion(WatchItem item, {bool bumpRev = false}) {
    final now = DateTime.now().toUtc().toIso8601String();
    return WatchProductsCompanion(
      name: Value(item.name),
      url: Value(item.url),
      canonicalUrl: Value(item.canonicalUrl),
      store: Value(item.store.id),
      productId: Value(item.productId),
      identityKey: Value(item.resolvedIdentity),
      imageUrl: Value(item.imageUrl),
      currentPrice: Value(item.currentPrice),
      basePrice: Value(item.basePrice),
      lastChecked: Value(item.lastChecked.toUtc().toIso8601String()),
      targetPrice: Value(item.targetPrice),
      notifyOnDecrease: Value(item.notifyOnDecrease),
      notifyOnIncrease: Value(item.notifyOnIncrease),
      notifyOnTarget: Value(item.notifyOnTarget),
      checkIntervalMinutes: Value(item.checkIntervalMinutes),
      isPaused: Value(item.isPaused),
      isPinned: Value(item.isPinned),
      manuallyPaused: Value(item.manuallyPaused),
      pausedAt: Value(item.pausedAt?.toUtc().toIso8601String()),
      pinnedAt: Value(item.pinnedAt?.toUtc().toIso8601String()),
      pendingPrice: Value(item.pendingPrice),
      pendingPriceAt: Value(item.pendingPriceAt?.toUtc().toIso8601String()),
      consecutiveFailures: Value(item.consecutiveFailures),
      lastCheckError: Value(item.lastCheckError),
      availability: Value(item.availability),
      lastSource: Value(item.lastSource),
      lastScore: Value(item.lastScore),
      updatedAt: Value(now),
      rev: Value(bumpRev ? item.rev + 1 : item.rev),
    );
  }
}
