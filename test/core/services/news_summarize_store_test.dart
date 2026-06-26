// Hermetic tests for NewsSummarizeStore — the "Summarize my For You pile"
// background batch engine. Runs the REAL store + REAL in-memory Drift-backed
// NewsRepository with a fake batch service (no network). The foreground
// service + notification side effects no-op/throw-and-swallow under the test
// binding, so they don't affect these assertions.

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_nexus/core/network/api_client.dart';
import 'package:ai_nexus/core/services/news_summarize_store.dart';
import 'package:ai_nexus/data/local/database/app_database.dart' as db;
import 'package:ai_nexus/data/repositories/news_repository.dart';
import 'package:ai_nexus/data/services/news_summarize_service.dart';
import 'package:ai_nexus/domain/entities/news_entities.dart';

class _FakeSummarizeService extends NewsSummarizeService {
  _FakeSummarizeService() : super(ApiClient());

  int calls = 0;
  int articlesSeen = 0;
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
    articlesSeen += articles.length;
    if (onCall != null) return onCall!(articles, i);
    return {for (final a in articles) a.id: 'summary for ${a.id}'};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final store = NewsSummarizeStore.instance;
  late db.AppDatabase database;
  late NewsRepository repo;
  late _FakeSummarizeService service;
  var seq = 0;

  setUp(() {
    database = db.AppDatabase.forTesting(NativeDatabase.memory());
    repo = NewsRepository(database, ApiClient());
    service = _FakeSummarizeService();
  });

  tearDown(() async {
    await database.close();
  });

  Future<void> seedRow(String id) => database.into(database.newsArticles).insert(
        db.NewsArticlesCompanion.insert(
          id: id,
          title: 'Title $id',
          excerpt: 'Excerpt',
          source: 'Source',
          category: 'AI News',
          imageUrl: '',
          readTime: 3,
          date: '2026-06-25',
          blocksJson: '{}',
        ),
      );

  Article article(String id, {String? summaryShort}) => Article(
        id: id,
        title: 'Title $id',
        excerpt: 'Excerpt',
        source: 'Source',
        category: 'AI News',
        imageUrl: '',
        readTime: 3,
        date: '2026-06-25',
        blocks: const [],
        summaryShort: summaryShort,
        isFullContent: true,
      );

  List<Article> freshArticles(int n) {
    final base = seq;
    seq += n;
    return [for (var i = 0; i < n; i++) article('news-batch-${base + i}')];
  }

  /// Resolves when every article reaches a terminal (ready/error) state.
  Future<void> settledAll(List<String> ids) {
    final c = Completer<void>();
    void check() {
      final allDone = ids.every((id) {
        final s = store.statusOf(id);
        return s.status == SummaryStatus.ready ||
            s.status == SummaryStatus.error;
      });
      if (allDone && !c.isCompleted) c.complete();
    }

    store.addListener(check);
    check();
    return c.future
        .timeout(const Duration(seconds: 8))
        .whenComplete(() => store.removeListener(check));
  }

  test('all-cached pile short-circuits with zero AI calls', () async {
    final arts = [
      for (final a in freshArticles(3))
        a.copyWith(summaryShort: 'cached ${a.id}'),
    ];
    store.start(articles: arts, service: service, repository: repo);

    expect(service.calls, 0, reason: 'cached articles never hit the model');
    expect(store.hasActiveSession, isFalse);
    for (final a in arts) {
      expect(store.statusOf(a.id).status, SummaryStatus.ready);
    }
  });

  test('pending pile is batched, summarized, and persisted to the DB',
      () async {
    final arts = freshArticles(3);
    for (final a in arts) {
      await seedRow(a.id);
    }

    store.start(
      articles: arts,
      service: service,
      repository: repo,
      liteModel: 'gemini-2.5-flash-lite',
    );
    await settledAll(arts.map((a) => a.id).toList());

    for (final a in arts) {
      expect(store.statusOf(a.id).status, SummaryStatus.ready);
      final row = await (database.select(database.newsArticles)
            ..where((t) => t.id.equals(a.id)))
          .getSingleOrNull();
      expect(row?.summaryShort, 'summary for ${a.id}',
          reason: 'each summary is cached locally so re-open is instant');
    }
    expect(service.articlesSeen, 3);

    final p = store.progress;
    expect(p.total, 3);
    expect(p.ready, 3);
    expect(p.errored, 0);
  });

  test('large pile (25) is chunked at kBatchSize and all complete', () async {
    final arts = freshArticles(25);
    for (final a in arts) {
      await seedRow(a.id);
    }

    store.start(articles: arts, service: service, repository: repo);
    await settledAll(arts.map((a) => a.id).toList());

    // 25 articles / 10 per batch = 3 batches (10 + 10 + 5).
    expect(service.calls, 3, reason: 'chunked at kBatchSize=10');
    expect(store.progress.ready, 25);
  });

  test('a batch that errors marks those articles errored without crashing',
      () async {
    final arts = freshArticles(2);
    for (final a in arts) {
      await seedRow(a.id);
    }
    service.onCall = (articles, i) async => throw DioException(
          requestOptions: RequestOptions(path: '/summarize'),
          type: DioExceptionType.badResponse,
          response: Response(
            requestOptions: RequestOptions(path: '/summarize'),
            statusCode: 400,
          ),
        );

    store.start(articles: arts, service: service, repository: repo);
    await settledAll(arts.map((a) => a.id).toList());

    for (final a in arts) {
      expect(store.statusOf(a.id).status, SummaryStatus.error);
    }
    expect(store.progress.errored, 2);
  });
}
