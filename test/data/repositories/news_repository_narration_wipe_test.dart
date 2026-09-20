import 'dart:io';
import 'dart:typed_data';

import 'package:ai_nexus/core/network/api_client.dart';
import 'package:ai_nexus/core/network/api_endpoints.dart';
import 'package:ai_nexus/data/local/database/app_database.dart' as db;
import 'package:ai_nexus/data/repositories/news_repository.dart';
import 'package:ai_nexus/data/services/narration_download_store.dart';
import 'package:ai_nexus/data/services/narration_playback.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeApi extends ApiClient {
  _FakeApi();

  Object? Function(String method, String path, Object? data)? handler;

  Response<T> _resp<T>(String path, Object? data) => Response<T>(
        requestOptions: RequestOptions(path: path),
        data: data as T?,
        statusCode: 200,
      );

  Object? _route(String method, String path, Object? data) {
    return handler?.call(method, path, data) ?? <String, dynamic>{};
  }

  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
  }) async {
    return _resp<T>(path, _route('GET', path, null));
  }

  @override
  Future<Response<T>> post<T>(
    String path, {
    Object? data,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    return _resp<T>(path, _route('POST', path, data));
  }

  @override
  Future<Response<T>> delete<T>(String path) async {
    return _resp<T>(path, _route('DELETE', path, null));
  }
}

Map<String, dynamic> _articleJson(
  String id, {
  bool isSaved = false,
  bool isRead = false,
}) {
  return <String, dynamic>{
    'id': id,
    'title': 'Article $id',
    'excerpt': 'excerpt-$id',
    'source': 'Source',
    'category': 'Technology',
    'imageUrl': '',
    'readTime': 2,
    'date': '2026-06-25',
    'isSaved': isSaved,
    'isRead': isRead,
    'summaryMarkdown': 'Full body for $id',
    'originalUrl': 'https://example.com/$id',
    'publishedAt': '2026-06-25T10:00:00Z',
  };
}

Uint8List _ogg() =>
    Uint8List.fromList(<int>[0x4F, 0x67, 0x67, 0x53, ...List<int>.filled(300, 1)]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late db.AppDatabase database;
  late _FakeApi api;
  late NewsRepository repo;
  late Directory tmp;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    database = db.AppDatabase.forTesting(NativeDatabase.memory());
    api = _FakeApi();
    repo = NewsRepository(database, api);
    tmp = await Directory.systemTemp.createTemp('nar-wipe-');
    NarrationDownloadStore.debugRootOverride = tmp;
    NarrationDownloadStore.debugGetBytes = (url, headers, resume) async {
      return (status: 200, body: _ogg());
    };
    NarrationDownloadStore.instance.resetForTest();
    await NarrationDownloadStore.instance.hydrate();
    resetDroppedNarrationIdsForTest();
  });

  tearDown(() async {
    resetDroppedNarrationIdsForTest();
    NarrationDownloadStore.debugGetBytes = null;
    NarrationDownloadStore.debugRootOverride = null;
    NarrationDownloadStore.instance.resetForTest();
    await database.close();
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });

  Future<void> seed(List<Map<String, dynamic>> articles) async {
    api.handler = (m, p, d) {
      if (m == 'GET' && p == ApiEndpoints.news) {
        return <String, dynamic>{'articles': articles};
      }
      return null;
    };
    await repo.syncNews();
  }

  Future<void> cache(String id) async {
    await NarrationDownloadStore.instance.download(id);
    expect(await NarrationDownloadStore.instance.hasPlayableFile(id), isTrue);
  }

  Future<void> expectWiped(String id) async {
    for (var i = 0; i < 40; i++) {
      final file = NarrationDownloadStore.instance.localFile(id);
      final exists = file != null && await file.exists();
      if (!NarrationDownloadStore.instance.isReady(id) && !exists) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 15));
    }
    fail('local audio for $id was not wiped');
  }

  test('markRead unsaved wipes the local opus and tombstones playback',
      () async {
    await seed([_articleJson('news-1')]);
    await cache('news-1');
    await repo.markRead('news-1');
    await expectWiped('news-1');
    expect(isNarrationIdDropped('news-1'), isTrue);
  });

  test('markRead saved wipes the local opus but keeps the article row',
      () async {
    await seed([_articleJson('news-1', isSaved: true)]);
    await cache('news-1');
    await repo.markRead('news-1');
    await expectWiped('news-1');
    final row = await (database.select(database.newsArticles)
          ..where((t) => t.id.equals('news-1')))
        .getSingleOrNull();
    expect(row, isNotNull);
    expect(row!.isRead, isTrue);
    expect(
      isNarrationIdDropped('news-1'),
      isFalse,
      reason: 'saved mark-read must not tombstone replay from Saved',
    );
  });

  test('deleteArticle wipes local audio', () async {
    await seed([_articleJson('news-1')]);
    await cache('news-1');
    await repo.deleteArticle('news-1');
    await expectWiped('news-1');
    expect(isNarrationIdDropped('news-1'), isTrue);
  });

  test('markManyRead wipes unsaved locals and leaves the saved file', () async {
    await seed([
      _articleJson('news-1'),
      _articleJson('news-2', isSaved: true),
    ]);
    await cache('news-1');
    await cache('news-2');
    await repo.markManyRead(['news-1', 'news-2']);
    await expectWiped('news-1');
    expect(NarrationDownloadStore.instance.isReady('news-2'), isTrue);
    expect(await NarrationDownloadStore.instance.hasPlayableFile('news-2'), isTrue);
  });

  test('clearAllNews / nuke wipes saved and unsaved locals', () async {
    await seed([
      _articleJson('news-1'),
      _articleJson('news-2', isSaved: true),
    ]);
    await cache('news-1');
    await cache('news-2');
    await repo.clearAllNews();
    await expectWiped('news-1');
    await expectWiped('news-2');
  });

  test('stale unsaved sync prune wipes local audio; saved file stays',
      () async {
    await seed([_articleJson('news-1'), _articleJson('news-2', isSaved: true)]);
    await cache('news-1');
    await cache('news-2');
    await seed([_articleJson('news-3')]);
    await expectWiped('news-1');
    expect(NarrationDownloadStore.instance.isReady('news-2'), isTrue);
  });

  test('markRead of a missing id is a no-op', () async {
    await repo.markRead('does-not-exist');
    expect(NarrationDownloadStore.instance.isReady('news-1'), isFalse);
  });
}
