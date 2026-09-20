import 'package:ai_nexus/data/local/database/app_database.dart' as db;
import 'package:ai_nexus/data/services/price_watch/price_models.dart';
import 'package:ai_nexus/data/services/price_watch/store_url.dart';
import 'package:ai_nexus/data/services/price_watch/watch_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late db.AppDatabase database;
  late WatchRepository repo;

  setUp(() {
    database = db.AppDatabase.forTesting(NativeDatabase.memory());
    repo = WatchRepository(database);
  });

  tearDown(() async {
    await database.close();
  });

  CanonicalWatchUrl amazon() => canonicalizeWatchUrl(
        'https://www.amazon.in/dp/B0CXXXXXXX',
      )!;

  test('insert then duplicate URL is rejected', () async {
    await repo.insert(
      canon: amazon(),
      name: 'Sony',
      imageUrl: '',
      price: 1299,
      source: 'test',
      score: 90,
    );
    expect(
      () => repo.insert(
        canon: amazon(),
        name: 'Sony',
        imageUrl: '',
        price: 1299,
        source: 'test',
        score: 90,
      ),
      throwsA(isA<WatchDuplicateException>()),
    );
  });

  test('not due until interval elapses', () async {
    final item = await repo.insert(
      canon: amazon(),
      name: 'Sony',
      imageUrl: '',
      price: 1299,
      source: 'test',
      score: 90,
      intervalMinutes: 60,
    );
    expect(await repo.dueItems(), isEmpty);
    await repo.updateItem(
      item.copyWith(lastChecked: DateTime.now().subtract(const Duration(hours: 2))),
    );
    expect(await repo.dueItems(), hasLength(1));
  });

  test('pending item is due after confirm delay', () async {
    final item = await repo.insert(
      canon: amazon(),
      name: 'Sony',
      imageUrl: '',
      price: 1299,
      source: 'test',
      score: 90,
    );
    await repo.parkPending(item, price: 700, error: null);
    expect(await repo.dueItems(), isEmpty);
    final due = await repo.dueItems(
      now: DateTime.now().add(const Duration(minutes: 11)),
    );
    expect(due, hasLength(1));
    expect(due.single.pendingPrice, 700);
  });

  test('acceptPrice writes history and clears pending', () async {
    final item = await repo.insert(
      canon: amazon(),
      name: 'Sony',
      imageUrl: '',
      price: 1299,
      source: 'test',
      score: 90,
    );
    await repo.parkPending(item, price: 700, error: null);
    await repo.acceptPrice(
      item,
      price: 1199,
      source: 'test',
      score: 91,
    );
    final fresh = await repo.getById(item.id);
    expect(fresh!.currentPrice, 1199);
    expect(fresh.pendingPrice, isNull);
    expect(fresh.consecutiveFailures, 0);
    final hist = await repo.history(item.id);
    expect(hist.length, 2);
  });

  test('paused item is never due', () async {
    final item = await repo.insert(
      canon: amazon(),
      name: 'Sony',
      imageUrl: '',
      price: 1299,
      source: 'test',
      score: 90,
      intervalMinutes: 15,
    );
    await repo.updateItem(
      item.copyWith(
        isPaused: true,
        lastChecked: DateTime.now().subtract(const Duration(hours: 5)),
      ),
    );
    expect(await repo.dueItems(), isEmpty);
    expect(await repo.allActive(), isEmpty);
  });

  test('failed item is due after retry delay, not immediately', () async {
    final item = await repo.insert(
      canon: amazon(),
      name: 'Sony',
      imageUrl: '',
      price: 1299,
      source: 'test',
      score: 90,
    );
    await repo.markFailure(item, 'timeout');
    expect(await repo.dueItems(), isEmpty);
    final soon = await repo.dueItems(
      now: DateTime.now().add(const Duration(minutes: 6)),
    );
    expect(soon, hasLength(1));
  });

  test('applyIntervalToAll updates every row', () async {
    await repo.insert(
      canon: amazon(),
      name: 'Sony',
      imageUrl: '',
      price: 1299,
      source: 'test',
      score: 90,
      intervalMinutes: 60,
    );
    await repo.insert(
      canon: canonicalizeWatchUrl('https://www.amazon.in/dp/B09ABCDEFG')!,
      name: 'Other',
      imageUrl: '',
      price: 500,
      source: 'test',
      score: 90,
      intervalMinutes: 180,
    );
    await repo.applyIntervalToAll(15);
    final all = await repo.watchItems().first;
    expect(all.every((p) => p.checkIntervalMinutes == 15), isTrue);
  });

  test('delete removes history and alerts', () async {
    final item = await repo.insert(
      canon: amazon(),
      name: 'Sony',
      imageUrl: '',
      price: 1299,
      source: 'test',
      score: 90,
    );
    await repo.addAlert(
      WatchAlert(
        id: 'a1',
        productId: item.id,
        productName: 'Sony',
        oldPrice: 1299,
        newPrice: 1199,
        reason: 'dropped',
        createdAt: DateTime.now(),
      ),
    );
    await repo.deleteItem(item.id);
    expect(await repo.getById(item.id), isNull);
    expect(await repo.history(item.id), isEmpty);
    expect(await repo.alerts().first, isEmpty);
  });

  test('same SKU different URLs collide on identityKey', () async {
    await repo.insert(
      canon: canonicalizeWatchUrl(
        'https://www.ajio.com/navy-shirt/p/441137043003',
      )!,
      name: 'Shirt',
      imageUrl: '',
      price: 599,
      source: 'test',
      score: 90,
    );
    expect(
      () => repo.insert(
        canon: canonicalizeWatchUrl(
          'https://www.ajio.com/other-slug/p/441137043003?utm=1',
        )!,
        name: 'Shirt 2',
        imageUrl: '',
        price: 599,
        source: 'test',
        score: 90,
      ),
      throwsA(isA<WatchDuplicateException>()),
    );
  });

  test('insert stores identityKey', () async {
    final item = await repo.insert(
      canon: amazon(),
      name: 'Sony',
      imageUrl: '',
      price: 1299,
      source: 'test',
      score: 90,
    );
    expect(item.identityKey, 'amazon:B0CXXXXXXX');
    expect(item.rev, 1);
  });
}
