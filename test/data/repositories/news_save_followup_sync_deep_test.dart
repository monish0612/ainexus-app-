// Deep, end-to-end integration tests for the News save / unsave / delete and
// follow-up-chat persistence + cross-device-sync pipeline.
//
// These run the REAL [NewsRepository] and REAL [ArticleFollowUpStore] against a
// REAL in-memory Drift database, with a controllable fake [ApiClient] standing
// in for the backend. Nothing here is mocked at the repository boundary — the
// assertions exercise the exact local-first write paths, server reconciliation,
// stale-pruning, id-stability and chat lifecycle the production app uses.
//
// What this proves for a single-user / multi-device setup:
//   • Save / unsave is local-first and survives a backend outage (offline).
//   • The server's authoritative isSaved/isRead is reconciled back locally.
//   • A saved article is NEVER pruned by the stale sweep (durability).
//   • Re-syncing the same article id updates one row (no dupes, stable id).
//   • Follow-up chats persist in the DB, reload after a "restart", and are
//     keyed purely by articleId (switching Article<->AI Summary can't break it).
//   • Deleting / un-saving an article clears ONLY that article's chat.

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_nexus/core/network/api_client.dart';
import 'package:ai_nexus/core/network/api_endpoints.dart';
import 'package:ai_nexus/core/services/news_nuke_service.dart';
import 'package:ai_nexus/core/services/nuke_report.dart';
import 'package:ai_nexus/data/local/database/app_database.dart' as db;
import 'package:ai_nexus/data/repositories/news_repository.dart';
import 'package:ai_nexus/presentation/screens/news/article_followup_sheet.dart';

/// A fully controllable stand-in for [ApiClient]. Records every call and lets
/// each test decide the response body (or force a network failure).
class _FakeApi extends ApiClient {
  _FakeApi();

  final List<String> calls = <String>[];

  /// Methods (`GET`/`POST`/`PUT`/`DELETE`) that should throw a connection error
  /// to simulate the backend being unreachable (offline).
  final Set<String> failMethods = <String>{};

  /// Per-test router: returns the response `data` for a given method+path.
  Object? Function(String method, String path, Object? data)? handler;

  int get saveCalls => calls.where((c) => c.contains('/save')).length;
  int get chatDeleteCalls => calls
      .where((c) =>
          c.startsWith('DELETE') &&
          c.contains('/article-chats/') &&
          !c.endsWith('/summary'))
      .length;

  Response<T> _resp<T>(String path, Object? data) => Response<T>(
        requestOptions: RequestOptions(path: path),
        data: data as T?,
        statusCode: 200,
      );

  Object? _route(String method, String path, Object? data) {
    if (failMethods.contains(method)) {
      throw DioException(
        requestOptions: RequestOptions(path: path),
        type: DioExceptionType.connectionError,
        message: 'fake offline',
      );
    }
    final routed = handler?.call(method, path, data);
    if (routed != null) return routed;
    // Safe defaults so unawaited background syncs never explode the test.
    if (path.contains('/article-chats')) {
      return <String, dynamic>{'messages': <dynamic>[]};
    }
    return <String, dynamic>{};
  }

  @override
  Future<Response<T>> get<T>(String path,
      {Map<String, dynamic>? queryParameters, CancelToken? cancelToken}) async {
    calls.add('GET $path');
    return _resp<T>(path, _route('GET', path, null));
  }

  @override
  Future<Response<T>> post<T>(String path,
      {Object? data, Options? options, CancelToken? cancelToken}) async {
    calls.add('POST $path');
    return _resp<T>(path, _route('POST', path, data));
  }

  @override
  Future<Response<T>> put<T>(String path, {Object? data}) async {
    calls.add('PUT $path');
    return _resp<T>(path, _route('PUT', path, data));
  }

  @override
  Future<Response<T>> delete<T>(String path) async {
    calls.add('DELETE $path');
    return _resp<T>(path, _route('DELETE', path, null));
  }
}

Map<String, dynamic> _articleJson(
  String id, {
  bool isSaved = false,
  bool isRead = false,
  String category = 'Technology',
  String title = 'Article',
  String published = '2026-06-25T10:00:00Z',
}) {
  return <String, dynamic>{
    'id': id,
    'title': title,
    'excerpt': 'excerpt-$id',
    'source': 'Source',
    'category': category,
    'imageUrl': '',
    'readTime': 2,
    'date': '2026-06-25',
    'isSaved': isSaved,
    'isRead': isRead,
    'summaryMarkdown': 'Full body for $id',
    'originalUrl': 'https://example.com/$id',
    'publishedAt': published,
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late db.AppDatabase database;
  late _FakeApi api;
  late NewsRepository repo;
  final store = ArticleFollowUpStore.instance;

  setUp(() {
    database = db.AppDatabase.forTesting(NativeDatabase.memory());
    api = _FakeApi();
    repo = NewsRepository(database, api);
    // Wire the singleton chat store to THIS test's DB + API so the
    // sync<->chat-clear integration path uses the in-memory database.
    store.init(database, api);
  });

  tearDown(() async {
    store.clearAll();
    await database.close();
  });

  Future<db.NewsArticle?> row(String id) =>
      (database.select(database.newsArticles)..where((t) => t.id.equals(id)))
          .getSingleOrNull();

  Future<int> chatCount(String articleId) async {
    final rows = await (database.select(database.articleChatMessages)
          ..where((t) => t.articleId.equals(articleId)))
        .get();
    return rows.length;
  }

  Future<void> seedArticles(List<Map<String, dynamic>> articles) async {
    api.handler = (m, p, d) {
      if (m == 'GET' && p == ApiEndpoints.news) {
        return <String, dynamic>{'articles': articles};
      }
      return null;
    };
    await repo.syncNews();
  }

  Future<void> insertChat(String articleId, String id, String text) {
    return database.into(database.articleChatMessages).insert(
          db.ArticleChatMessagesCompanion.insert(
            id: id,
            articleId: articleId,
            role: 'user',
            msgText: text,
            createdAt: DateTime.now().toIso8601String(),
          ),
        );
  }

  group('Save / unsave — local-first + server reconcile', () {
    test('save flips local immediately and reconciles server response', () async {
      await seedArticles([_articleJson('news-1')]);
      expect((await row('news-1'))!.isSaved, isFalse);

      // Server echoes the authoritative saved=true article on /save.
      api.handler = (m, p, d) {
        if (p == ApiEndpoints.articleSave('news-1')) {
          return <String, dynamic>{
            'article': _articleJson('news-1', isSaved: true),
          };
        }
        return null;
      };

      await repo.toggleSaved('news-1');

      expect((await row('news-1'))!.isSaved, isTrue);
      expect(api.saveCalls, 1, reason: 'save must hit the backend for sync');
    });

    test('save is KEPT locally even when backend is offline', () async {
      await seedArticles([_articleJson('news-1')]);

      api.failMethods.add('POST'); // backend unreachable

      // Must not throw — local-first write is the source of truth offline.
      await repo.toggleSaved('news-1');

      expect((await row('news-1'))!.isSaved, isTrue,
          reason: 'local toggle is retained despite API failure');
    });

    test('unsave flips back to false', () async {
      await seedArticles([_articleJson('news-1', isSaved: true)]);
      expect((await row('news-1'))!.isSaved, isTrue);

      api.handler = (m, p, d) {
        if (p == ApiEndpoints.articleSave('news-1')) {
          return <String, dynamic>{
            'article': _articleJson('news-1', isSaved: false),
          };
        }
        return null;
      };

      await repo.toggleSaved('news-1');
      expect((await row('news-1'))!.isSaved, isFalse);
    });
  });

  group('Durability across re-sync (cross-device safety)', () {
    test('saved article is NOT pruned when it drops off the server feed',
        () async {
      await seedArticles([_articleJson('news-1')]);
      await repo.toggleSaved('news-1'); // now saved locally
      expect((await row('news-1'))!.isSaved, isTrue);

      // Next sync: server only returns a DIFFERENT, fresh article.
      await seedArticles([_articleJson('news-2')]);

      expect(await row('news-1'), isNotNull,
          reason: 'saved articles survive the stale sweep');
      expect((await row('news-1'))!.isSaved, isTrue);
      expect(await row('news-2'), isNotNull);
    });

    test('unsaved + unread stale article IS pruned and its chat cleared',
        () async {
      await seedArticles([_articleJson('news-1')]);
      await insertChat('news-1', 'c1', 'question?');
      expect(await chatCount('news-1'), 1);

      // news-1 disappears from the server; news-2 takes its place.
      await seedArticles([_articleJson('news-2')]);

      expect(await row('news-1'), isNull, reason: 'stale unsaved row pruned');
      expect(await chatCount('news-1'), 0,
          reason: 'pruning an article also clears its follow-up chat');
    });

    test('re-syncing the same id updates one row (stable id, no duplicates)',
        () async {
      await seedArticles([_articleJson('news-1', title: 'V1')]);
      await repo.toggleSaved('news-1');

      // Same id re-sent with an updated title and server-side saved=true.
      await seedArticles([
        _articleJson('news-1', title: 'V2 updated', isSaved: true),
      ]);

      final rows = await (database.select(database.newsArticles)
            ..where((t) => t.id.equals('news-1')))
          .get();
      expect(rows.length, 1, reason: 'no duplicate rows for a stable id');
      expect(rows.single.title, 'V2 updated');
      expect(rows.single.isSaved, isTrue, reason: 'server saved state honoured');
    });

    test('syncNews returns the count of genuinely new articles only', () async {
      final first = await () async {
        api.handler = (m, p, d) => m == 'GET' && p == ApiEndpoints.news
            ? <String, dynamic>{'articles': [_articleJson('news-1')]}
            : null;
        return repo.syncNews();
      }();
      expect(first, 1);

      api.handler = (m, p, d) => m == 'GET' && p == ApiEndpoints.news
          ? <String, dynamic>{
              'articles': [_articleJson('news-1'), _articleJson('news-2')],
            }
          : null;
      final second = await repo.syncNews();
      expect(second, 1, reason: 'only news-2 is new');
    });
  });

  group('Follow-up chat — persistence, reload, clear', () {
    test('persisted chats reload from the DB after a cold start', () async {
      await seedArticles([_articleJson('news-1')]);
      await insertChat('news-1', 'c1', 'first');
      await insertChat('news-1', 'c2', 'second');

      // A fresh store/cache (cold start) must hydrate from the DB.
      store.clearAll();
      store.init(database, api);

      final loaded = await store.load('news-1');
      expect(loaded.length, 2, reason: 'both messages restored from DB');
      expect(store.getCached('news-1').length, 2);
    });

    test('clear() removes only this article\'s chat + issues server delete',
        () async {
      await seedArticles([_articleJson('news-1'), _articleJson('news-2')]);
      await insertChat('news-1', 'a1', 'q1');
      await insertChat('news-2', 'b1', 'q2');

      await store.clear('news-1');

      expect(await chatCount('news-1'), 0, reason: 'target chat removed');
      expect(await chatCount('news-2'), 1,
          reason: 'chat is keyed by articleId — siblings untouched');
      expect(api.chatDeleteCalls, 1,
          reason: 'server is told to delete the chat for cross-device sync');
    });

    test('clearing a saved article does not affect the saved article row',
        () async {
      // Saving from either the Article or AI-Summary view targets the same id;
      // un-saving clears the chat but only flips the one row.
      await seedArticles([_articleJson('news-1', isSaved: true)]);
      await insertChat('news-1', 'a1', 'q1');

      await store.clear('news-1');

      expect(await chatCount('news-1'), 0);
      expect(await row('news-1'), isNotNull,
          reason: 'clearing chat never deletes the article row itself');
    });
  });

  group('Mark read / delete — keep only saved + unread', () {
    test('reading an UNSAVED article deletes it locally even when offline',
        () async {
      await seedArticles([_articleJson('news-1')]);
      // Both the legacy /read POST and the new DELETE are unreachable.
      api.failMethods.addAll({'POST', 'DELETE'});

      await repo.markRead('news-1');

      expect(await row('news-1'), isNull,
          reason:
              'a read + unsaved article is consumed and removed from the DB');
    });

    test('reading a SAVED article keeps the row and just flags it read',
        () async {
      await seedArticles([_articleJson('news-1', isSaved: true)]);

      await repo.markRead('news-1');

      final r = await row('news-1');
      expect(r, isNotNull,
          reason: 'saved articles are never deleted by reading them');
      expect(r!.isRead, isTrue);
      expect(r.isSaved, isTrue);
    });

    test('deleteArticle removes the row + clears its chat (offline-safe)',
        () async {
      await seedArticles([_articleJson('news-1')]);
      await insertChat('news-1', 'c1', 'q?');
      expect(await chatCount('news-1'), 1);
      api.failMethods.add('DELETE');

      await repo.deleteArticle('news-1');

      expect(await row('news-1'), isNull);
      expect(await chatCount('news-1'), 0,
          reason: 'deleting an article also wipes its follow-up chat');
    });

    test('deleteArticle hits the server DELETE for cross-device/web removal',
        () async {
      await seedArticles([_articleJson('news-1')]);

      await repo.deleteArticle('news-1');

      expect(
        api.calls.any((c) => c == 'DELETE ${ApiEndpoints.article('news-1')}'),
        isTrue,
        reason: 'server is told to delete + tombstone the article',
      );
    });

    test('markManyRead deletes the unsaved ids but preserves saved ones',
        () async {
      await seedArticles([
        _articleJson('news-1'),
        _articleJson('news-2', isSaved: true),
        _articleJson('news-3'),
      ]);

      final deleted = await repo.markManyRead(['news-1', 'news-2', 'news-3']);

      expect(deleted, 2, reason: 'only the two unsaved rows are removed');
      expect(await row('news-1'), isNull);
      expect(await row('news-3'), isNull);
      expect(await row('news-2'), isNotNull,
          reason: 'saved article survives a bulk clear');
    });
  });

  group('News nuke — wipe EVERYTHING including saved', () {
    test('clearAllNews deletes every row (saved + read + unread) + chats',
        () async {
      await seedArticles([
        _articleJson('news-1'),
        _articleJson('news-2', isSaved: true),
        _articleJson('news-3', isRead: true),
      ]);
      await insertChat('news-2', 'c1', 'q?');
      expect(await chatCount('news-2'), 1);

      final result = await repo.clearAllNews();

      expect(result.removed, 3);
      expect(result.serverOk, isTrue);
      expect(await row('news-1'), isNull);
      expect(await row('news-2'), isNull,
          reason: 'the saved article is ALSO nuked');
      expect(await row('news-3'), isNull);
      expect(await chatCount('news-2'), 0,
          reason: 'follow-up chat of the saved article is wiped too');
      expect(
        api.calls.any((c) => c == 'POST ${ApiEndpoints.newsNuke}'),
        isTrue,
        reason: 'server is told to wipe all news',
      );
    });

    test('clearAllNews keeps the local wipe even when the server is offline',
        () async {
      await seedArticles([_articleJson('news-1', isSaved: true)]);
      api.failMethods.add('POST');

      final result = await repo.clearAllNews();

      expect(result.removed, 1);
      expect(result.serverOk, isFalse,
          reason: 'server failure is reported, but the local wipe stands');
      expect(await row('news-1'), isNull);
    });

    test('NewsNukeService emits a news-scope report with the cleared count',
        () async {
      await seedArticles([
        _articleJson('a'),
        _articleJson('b', isSaved: true),
      ]);
      final service = NewsNukeService(repo);

      final report = await service.nuke();

      expect(report.scope, NukeScope.news);
      expect(report.totalCleared, 2);
      expect(report.fullySynced, isTrue);
      expect(report.lines.single.label, 'News');
      expect(await row('a'), isNull);
      expect(await row('b'), isNull);
    });
  });
}
