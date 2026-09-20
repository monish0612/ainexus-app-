import 'price_models.dart';

/// Outbox for a later cloud replica. [NoopWatchSync] is the default.
abstract class WatchSyncPort {
  Future<void> enqueueProductUpsert(WatchItem item);
  Future<void> enqueuePointInsert(WatchPricePoint point);
  Future<void> enqueueTombstone(String identityKey, DateTime deletedAt);
  Future<void> pull();
  Future<void> push();
}

class NoopWatchSync implements WatchSyncPort {
  const NoopWatchSync();

  @override
  Future<void> enqueueProductUpsert(WatchItem item) async {}

  @override
  Future<void> enqueuePointInsert(WatchPricePoint point) async {}

  @override
  Future<void> enqueueTombstone(String identityKey, DateTime deletedAt) async {}

  @override
  Future<void> pull() async {}

  @override
  Future<void> push() async {}
}
