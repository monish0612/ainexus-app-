import 'package:ai_nexus/data/local/database/app_database.dart' as db;
import 'package:ai_nexus/data/services/price_watch/price_models.dart';
import 'package:ai_nexus/data/services/price_watch/store_url.dart';
import 'package:ai_nexus/data/services/price_watch/watch_engine.dart';
import 'package:ai_nexus/data/services/price_watch/watch_http_fetcher.dart';
import 'package:ai_nexus/data/services/price_watch/watch_llm.dart';
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

  test('addFromUrl stores first scrape', () async {
    final engine = WatchEngine(
      repo,
      _FakeFetcher([
        const ScrapeHit(
          price: 1299,
          source: 'test',
          name: 'Sony',
          score: 90,
          resolvedUrl: 'https://www.amazon.in/dp/B0CXXXXXXX',
        ),
      ]),
      prefs,
    );
    final item = await engine.addFromUrl('https://www.amazon.in/dp/B0CXXXXXXX');
    expect(item.currentPrice, 1299);
    expect(item.name, 'Sony');
  });

  test('35% jump parks then confirm accepts', () async {
    final fetcher = _FakeFetcher([
      const ScrapeHit(price: 1000, source: 't', name: 'X', score: 90),
      const ScrapeHit(price: 600, source: 't', name: 'X', score: 90),
      const ScrapeHit(price: 605, source: 't', name: 'X', score: 90),
    ]);
    final engine = WatchEngine(repo, fetcher, prefs);
    final item = await engine.addFromUrl('https://www.amazon.in/dp/B0CXXXXXXX');
    final parked = await engine.check(item);
    expect(parked.pending, isTrue);
    final parkedItem = await repo.getById(item.id);
    final confirmed = await engine.check(
      parkedItem!,
      kind: WatchCheckKind.confirm,
    );
    expect(confirmed.pending, isFalse);
    expect(confirmed.ok, isTrue);
    expect(confirmed.price, 605);
    final fresh = await repo.getById(item.id);
    expect(fresh!.currentPrice, 605);
    expect(fresh.pendingPrice, isNull);
  });

  test('disabled prefs skip checkDue', () async {
    await prefs.setEnabled(false);
    final engine = WatchEngine(
      repo,
      _FakeFetcher([
        const ScrapeHit(price: 1000, source: 't', name: 'X', score: 90),
      ]),
      prefs,
    );
    await engine.addFromUrl('https://www.amazon.in/dp/B0CXXXXXXX');
    expect(await engine.checkDue(), isEmpty);
  });

  test('adapter miss uses Gemini Flash then Droplert still parks a 35% jump',
      () async {
    final fetcher = _MissThenHitsFetcher([
      const ScrapeHit(price: 2000, source: 't', name: 'Widget', score: 90),
    ]);
    final engine = WatchEngine(
      repo,
      fetcher,
      prefs,
      llm: _FakeLlm(),
      liteModel: () => 'gemini-3.1-flash-lite-preview',
    );
    final item = await engine.addFromUrl('https://www.amazon.in/dp/B0CXXXXXXX');
    expect(item.currentPrice, 499);
    expect(item.name, 'Widget');

    final parked = await engine.check(item);
    expect(parked.pending, isTrue);
    expect(parked.price, 2000);
  });
}

class _MissThenHitsFetcher extends WatchHttpFetcher {
  _MissThenHitsFetcher(this.hits) : super(dio: Dio());

  final List<ScrapeHit> hits;
  int calls = 0;

  @override
  Future<ScrapeHit> scrape(String url, {WatchStore? store}) async {
    if (calls == 0) {
      calls++;
      throw WatchParseMissException(
        'Could not find a live price',
        excerpt: 'title: Widget\ntext: selling price 499',
        finalUrl: url,
      );
    }
    final i = calls - 1;
    calls++;
    if (i >= hits.length) throw WatchScrapeException('no more hits');
    return hits[i];
  }
}

class _FakeLlm implements WatchLlmPort {
  @override
  Future<WatchLlmHit?> extract({
    required String url,
    required String excerpt,
    String? liteModel,
  }) async {
    expect(liteModel, 'gemini-3.1-flash-lite-preview');
    return const WatchLlmHit(
      price: 499,
      name: 'Widget',
      confidence: 0.9,
    );
  }
}
