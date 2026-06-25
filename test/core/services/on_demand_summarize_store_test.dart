// Deep tests for [OnDemandSummarizeStore] — the background-robust engine
// behind the per-article "AI Summarize" button.
//
// These run the REAL store + a REAL in-memory Drift-backed [NewsRepository],
// with a fake [NewsSummarizeService] so we can script success / transient
// failure / hard failure without a network. They prove the production
// guarantees the user asked about:
//   • The result is PERSISTED to the DB on success (survives the modal /
//     app being closed mid-flight).
//   • A cached summary short-circuits with zero AI calls.
//   • Transient errors retry with backoff and eventually succeed.
//   • Hard (non-retryable) errors surface a friendly message after ONE call.
//   • A second tap while a summary is in flight is de-duped.
//   • State + listeners are strictly keyed by articleId (one article's run
//     never bleeds into another's).
//
// The foreground-service + notification side effects are platform plugins
// that no-op/throw-and-swallow under the test binding, so they don't affect
// these assertions (the coordinator wraps every plugin call in try/catch).

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_nexus/core/network/api_client.dart';
import 'package:ai_nexus/core/services/on_demand_summarize_store.dart';
import 'package:ai_nexus/data/local/database/app_database.dart' as db;
import 'package:ai_nexus/data/repositories/news_repository.dart';
import 'package:ai_nexus/data/services/news_summarize_service.dart';
import 'package:ai_nexus/domain/entities/news_entities.dart';

/// Scriptable stand-in for the batch summarize endpoint.
class _FakeSummarizeService extends NewsSummarizeService {
  _FakeSummarizeService() : super(ApiClient());

  int calls = 0;
  String? lastLiteModel;

  /// `(articles, callIndex) -> result`. Throw to simulate failures.
  Future<Map<String, String>> Function(List<Article> articles, int callIndex)?
      onCall;

  @override
  Future<Map<String, String>> summarizeBatch({
    required List<Article> articles,
    String? model,
    String? liteModel,
    CancelToken? cancelToken,
  }) async {
    final i = calls++;
    lastLiteModel = liteModel;
    if (onCall != null) return onCall!(articles, i);
    return {for (final a in articles) a.id: 'summary for ${a.id}'};
  }
}

DioException _dioTimeout() => DioException(
      requestOptions: RequestOptions(path: '/summarize'),
      type: DioExceptionType.receiveTimeout,
    );

DioException _dio400() => DioException(
      requestOptions: RequestOptions(path: '/summarize'),
      type: DioExceptionType.badResponse,
      response: Response(
        requestOptions: RequestOptions(path: '/summarize'),
        statusCode: 400,
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final store = OnDemandSummarizeStore.instance;
  late db.AppDatabase database;
  late NewsRepository repo;
  late _FakeSummarizeService service;
  var idSeq = 0;

  setUp(() {
    database = db.AppDatabase.forTesting(NativeDatabase.memory());
    repo = NewsRepository(database, ApiClient());
    service = _FakeSummarizeService();
    store.init(service, repo);
  });

  tearDown(() async {
    await database.close();
  });

  String freshId() => 'news-ondemand-${idSeq++}';

  Future<void> seedRow(String id, {String? summaryShort}) {
    return database.into(database.newsArticles).insert(
          db.NewsArticlesCompanion.insert(
            id: id,
            title: 'Title $id',
            excerpt: 'Excerpt',
            source: 'Source',
            category: 'Technology',
            imageUrl: '',
            readTime: 3,
            date: '2026-06-25',
            blocksJson: '{}',
          ),
        );
  }

  Article article(String id, {String? summaryShort}) => Article(
        id: id,
        title: 'Title $id',
        excerpt: 'Excerpt',
        source: 'Source',
        category: 'Technology',
        imageUrl: '',
        readTime: 3,
        date: '2026-06-25',
        blocks: const [],
        summaryShort: summaryShort,
        isFullContent: true,
      );

  /// Resolves once [id] reaches a terminal (ready/error) state.
  Future<OnDemandSummaryState> settled(String id) {
    final c = Completer<OnDemandSummaryState>();
    void check() {
      final s = store.stateOf(id);
      if ((s.status == OnDemandStatus.ready ||
              s.status == OnDemandStatus.error) &&
          !c.isCompleted) {
        c.complete(s);
      }
    }

    store.addListener(id, check);
    check(); // catch already-settled (cached path)
    return c.future.timeout(const Duration(seconds: 6)).whenComplete(
          () => store.removeListener(id, check),
        );
  }

  Future<String?> persistedSummary(String id) async {
    final row = await (database.select(database.newsArticles)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    return row?.summaryShort;
  }

  test('success persists the summary to the DB and exposes ready state',
      () async {
    final id = freshId();
    await seedRow(id);

    store.summarize(article: article(id), liteModel: 'gemini-2.5-flash-lite');
    final s = await settled(id);

    expect(s.status, OnDemandStatus.ready);
    expect(s.summary, 'summary for $id');
    expect(await persistedSummary(id), 'summary for $id',
        reason: 'result must survive modal/app close → persisted locally');
    expect(service.lastLiteModel, 'gemini-2.5-flash-lite',
        reason: 'forwards the user-selected Gemini Lite model');
  });

  test('cached summaryShort short-circuits with zero AI calls', () async {
    final id = freshId();
    store.summarize(article: article(id, summaryShort: 'cached body'));
    final s = await settled(id);

    expect(s.status, OnDemandStatus.ready);
    expect(s.summary, 'cached body');
    expect(service.calls, 0, reason: 'cached path must not call the model');
  });

  test('transient errors retry with backoff then succeed', () async {
    final id = freshId();
    await seedRow(id);
    service.onCall = (articles, i) async {
      if (i < 2) throw _dioTimeout();
      return {for (final a in articles) a.id: 'recovered summary'};
    };

    store.summarize(article: article(id));
    final s = await settled(id);

    expect(s.status, OnDemandStatus.ready);
    expect(s.summary, 'recovered summary');
    expect(service.calls, 3, reason: '2 transient failures + 1 success');
    expect(await persistedSummary(id), 'recovered summary');
  });

  test('non-retryable error surfaces a friendly message after one call',
      () async {
    final id = freshId();
    await seedRow(id);
    service.onCall = (articles, i) async => throw _dio400();

    store.summarize(article: article(id));
    final s = await settled(id);

    expect(s.status, OnDemandStatus.error);
    expect(service.calls, 1, reason: '400 is not retryable');
    expect(s.error, contains('retry'));
  });

  test('a second tap while loading is de-duped (one AI call)', () async {
    final id = freshId();
    await seedRow(id);
    final gate = Completer<void>();
    service.onCall = (articles, i) async {
      await gate.future; // hold the first call open
      return {for (final a in articles) a.id: 'summary for $id'};
    };

    store.summarize(article: article(id));
    expect(store.stateOf(id).status, OnDemandStatus.loading);
    // Second tap while in flight — must be ignored.
    store.summarize(article: article(id));

    gate.complete();
    final s = await settled(id);

    expect(s.status, OnDemandStatus.ready);
    expect(service.calls, 1, reason: 'in-flight request must de-dupe');
  });

  test('state + listeners are isolated per articleId', () async {
    final idA = freshId();
    final idB = freshId();
    await seedRow(idA);
    await seedRow(idB);
    service.onCall = (articles, i) async =>
        {for (final a in articles) a.id: 'summary for ${a.id}'};

    var aHits = 0;
    void onA() => aHits++;
    store.addListener(idA, onA);

    store.summarize(article: article(idA));
    store.summarize(article: article(idB));
    final sA = await settled(idA);
    final sB = await settled(idB);
    store.removeListener(idA, onA);

    expect(sA.summary, 'summary for $idA');
    expect(sB.summary, 'summary for $idB');
    expect(store.stateOf(idA).summary, isNot(equals(store.stateOf(idB).summary)));
    expect(aHits, greaterThan(0),
        reason: 'idA listener fires for idA transitions');
  });
}
