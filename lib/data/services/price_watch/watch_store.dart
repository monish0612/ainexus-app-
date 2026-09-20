import 'price_models.dart';
import 'store_url.dart';

class WatchDuplicateException implements Exception {
  WatchDuplicateException(
    this.canonicalUrl, {
    this.existingId,
    this.identityKey,
  });

  final String canonicalUrl;
  final String? existingId;
  final String? identityKey;

  @override
  String toString() => 'Already watching this product';
}

/// Persistence port. Named so it does not collide with the [WatchStore] enum.
abstract class WatchStorePort {
  Stream<List<WatchItem>> watchItems();
  Stream<int> unreadAlertCount();
  Stream<List<WatchPricePoint>> historyStream(String productId);
  Stream<List<WatchAlert>> alerts();

  Future<WatchItem?> getById(String id);
  Future<WatchItem?> getByIdentity(String identityKey);
  Future<List<WatchItem>> allActive();
  Future<List<WatchItem>> dueItems({DateTime? now});

  Future<WatchItem> insert({
    required CanonicalWatchUrl canon,
    required String name,
    required String imageUrl,
    required double price,
    required String source,
    required int score,
    String? availability,
    int intervalMinutes = 60,
  });

  Future<void> updateItem(WatchItem item);
  Future<void> applyIntervalToAll(int minutes);
  Future<void> deleteItem(String id);
  Future<WatchItem> upgradeIdentity(WatchItem item, CanonicalWatchUrl canon);

  Future<void> acceptPrice(
    WatchItem item, {
    required double price,
    required String source,
    required int score,
    String? availability,
  });

  Future<void> parkPending(
    WatchItem item, {
    required double price,
    required String? error,
  });

  Future<void> markFailure(
    WatchItem item,
    String error, {
    bool clearPending = false,
  });

  Future<List<WatchPricePoint>> history(
    String productId, {
    DateTime? from,
    int? limit,
  });

  Future<void> addAlert(WatchAlert alert);
  Future<void> markAlertsRead();
}
