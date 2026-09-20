import 'package:ai_nexus/data/local/database/app_database.dart' as db;
import 'package:ai_nexus/data/services/price_watch/price_models.dart';
import 'package:ai_nexus/data/services/price_watch/store_url.dart';
import 'package:ai_nexus/data/services/price_watch/watch_engine.dart';
import 'package:ai_nexus/data/services/price_watch/watch_http_fetcher.dart';
import 'package:ai_nexus/data/services/price_watch/watch_policy.dart';
import 'package:ai_nexus/data/services/price_watch/watch_prefs.dart';
import 'package:ai_nexus/data/services/price_watch/watch_repository.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeFetcher extends WatchHttpFetcher {
  _FakeFetcher(this.hits) : super(dio: Dio());

  final List<ScrapeHit> hits;
  int calls = 0;

  @override
  Future<ScrapeHit> scrape(String url, {WatchStore? store}) async {
    if (calls >= hits.length) {
      throw WatchScrapeException('no more hits');
    }
    return hits[calls++];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late db.AppDatabase database;
  late WatchRepository repo;
  late WatchPrefs prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final sp = await SharedPreferences.getInstance();
    prefs = WatchPrefs(sp);
    database = db.AppDatabase.forTesting(NativeDatabase.memory());
    repo = WatchRepository(database);
  });

  tearDown(() async {
    await database.close();
  });

  WatchEngine engine(_FakeFetcher f) => WatchEngine(repo, f, prefs);

  test('small drop is accepted and writes a decrease alert', () async {
    final fetcher = _FakeFetcher([
      const ScrapeHit(price: 1000, source: 't', name: 'X', score: 90),
      const ScrapeHit(price: 900, source: 't', name: 'X', score: 90),
    ]);
    final e = engine(fetcher);
    final item = await e.addFromUrl('https://www.amazon.in/dp/B0CXXXXXXX');
    final r = await e.check(item);
    expect(r.ok, isTrue);
    expect(r.pending, isFalse);
    expect(r.price, 900);
    expect(r.reasons, contains(AlertReason.decrease));
    final fresh = await repo.getById(item.id);
    expect(fresh!.currentPrice, 900);
    expect(fresh.pendingPrice, isNull);
    final alerts = await repo.alerts().first;
    expect(alerts, hasLength(1));
    expect(alerts.single.reason, 'dropped');
  });

  test('confirm disagree keeps previous price and clears pending', () async {
    final fetcher = _FakeFetcher([
      const ScrapeHit(price: 1000, source: 't', name: 'X', score: 90),
      const ScrapeHit(price: 600, source: 't', name: 'X', score: 90),
      const ScrapeHit(price: 900, source: 't', name: 'X', score: 90),
    ]);
    final e = engine(fetcher);
    final item = await e.addFromUrl('https://www.amazon.in/dp/B0CXXXXXXX');
    await e.check(item);
    final parked = await repo.getById(item.id);
    expect(parked!.pendingPrice, 600);
    final r = await e.check(parked, kind: WatchCheckKind.confirm);
    expect(r.ok, isFalse);
    final fresh = await repo.getById(item.id);
    expect(fresh!.currentPrice, 1000);
    expect(fresh.pendingPrice, isNull);
    expect(fresh.consecutiveFailures, 1);
  });

  test('scrape throw marks failure and keeps last price', () async {
    final fetcher = _FakeFetcher([
      const ScrapeHit(price: 1000, source: 't', name: 'X', score: 90),
    ]);
    final e = engine(fetcher);
    final item = await e.addFromUrl('https://www.amazon.in/dp/B0CXXXXXXX');
    final r = await e.check(item);
    expect(r.ok, isFalse);
    final fresh = await repo.getById(item.id);
    expect(fresh!.currentPrice, 1000);
    expect(fresh.consecutiveFailures, 1);
    expect(fresh.lastCheckError, isNotNull);
  });

  test('paused product is not scraped', () async {
    final fetcher = _FakeFetcher([
      const ScrapeHit(price: 1000, source: 't', name: 'X', score: 90),
      const ScrapeHit(price: 800, source: 't', name: 'X', score: 90),
    ]);
    final e = engine(fetcher);
    final item = await e.addFromUrl('https://www.amazon.in/dp/B0CXXXXXXX');
    await repo.updateItem(item.copyWith(isPaused: true));
    final paused = await repo.getById(item.id);
    final r = await e.check(paused!);
    expect(r.ok, isTrue);
    expect(r.price, isNull);
    expect(fetcher.calls, 1);
  });

  test('checkDue force still runs when background watch is disabled', () async {
    await prefs.setEnabled(false);
    final fetcher = _FakeFetcher([
      const ScrapeHit(price: 1000, source: 't', name: 'X', score: 90),
      const ScrapeHit(price: 950, source: 't', name: 'X', score: 90),
    ]);
    final e = engine(fetcher);
    await e.addFromUrl('https://www.amazon.in/dp/B0CXXXXXXX');
    expect(await e.checkDue(), isEmpty);
    final forced = await e.checkDue(force: true);
    expect(forced, hasLength(1));
    expect(forced.single.price, 950);
  });

  test('duplicate addFromUrl is rejected', () async {
    final e = engine(
      _FakeFetcher([
        const ScrapeHit(price: 1000, source: 't', name: 'X', score: 90),
        const ScrapeHit(price: 1000, source: 't', name: 'X', score: 90),
      ]),
    );
    await e.addFromUrl('https://www.amazon.in/dp/B0CXXXXXXX');
    expect(
      () => e.addFromUrl('https://www.amazon.in/dp/B0CXXXXXXX?th=1'),
      throwsA(isA<WatchDuplicateException>()),
    );
  });

  test('same price does not alert', () async {
    final fetcher = _FakeFetcher([
      const ScrapeHit(price: 1000, source: 't', name: 'X', score: 90),
      const ScrapeHit(price: 1000, source: 't', name: 'X', score: 90),
    ]);
    final e = engine(fetcher);
    final item = await e.addFromUrl('https://www.amazon.in/dp/B0CXXXXXXX');
    final r = await e.check(item);
    expect(r.ok, isTrue);
    expect(r.reasons, isEmpty);
    expect(await repo.alerts().first, isEmpty);
  });

  test('target hit is recorded', () async {
    final fetcher = _FakeFetcher([
      const ScrapeHit(price: 1000, source: 't', name: 'X', score: 90),
      const ScrapeHit(price: 800, source: 't', name: 'X', score: 90),
    ]);
    final e = engine(fetcher);
    final item = await e.addFromUrl('https://www.amazon.in/dp/B0CXXXXXXX');
    await repo.updateItem(item.copyWith(targetPrice: 850));
    final armed = await repo.getById(item.id);
    final r = await e.check(armed!);
    expect(r.reasons, containsAll([AlertReason.target, AlertReason.decrease]));
  });

  test('prefs interval clamps to the 15 minute floor', () async {
    await prefs.setIntervalMinutes(5);
    expect(prefs.intervalMinutes, kMinIntervalMinutes);
    await prefs.setIntervalMinutes(60);
    expect(prefs.intervalMinutes, 60);
  });
}
