// Edge cases for NewsController.ensureFresh / quiet RSS refresh:
// throttle, in-flight coalesce, empty refresh must not wipe, failed
// background POST must keep the painted feed.

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_nexus/core/auth/app_token_store.dart';
import 'package:ai_nexus/core/network/api_client.dart';
import 'package:ai_nexus/data/local/database/app_database.dart';
import 'package:ai_nexus/data/repositories/news_repository.dart';
import 'package:ai_nexus/presentation/screens/news/news_controller.dart';

class _FakeNewsApi extends ApiClient {
  _FakeNewsApi(this.articles);

  List<Map<String, dynamic>> articles;
  int gets = 0;
  int posts = 0;
  Duration postDelay = Duration.zero;
  bool postEmpty = false;
  bool postThrows = false;

  Response<T> _ok<T>(String path, Object? data) => Response<T>(
        requestOptions: RequestOptions(path: path),
        data: data as T?,
        statusCode: 200,
      );

  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
  }) async {
    gets++;
    return _ok<T>(path, <String, dynamic>{'articles': articles});
  }

  @override
  Future<Response<T>> post<T>(
    String path, {
    Object? data,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    posts++;
    if (postDelay > Duration.zero) {
      await Future<void>.delayed(postDelay);
    }
    if (postThrows) {
      throw DioException(
        requestOptions: RequestOptions(path: path),
        type: DioExceptionType.connectionTimeout,
      );
    }
    final body = postEmpty
        ? <String, dynamic>{'articles': <Map<String, dynamic>>[]}
        : <String, dynamic>{'articles': articles};
    return _ok<T>(path, body);
  }
}

Map<String, dynamic> _json(String id, {required String category}) {
  return <String, dynamic>{
    'id': id,
    'title': 'TITLE-$id',
    'excerpt': 'excerpt',
    'source': 'Source',
    'category': category,
    'imageUrl': '',
    'readTime': 2,
    'date': '2026-09-14',
    'isSaved': false,
    'isRead': false,
    'summaryMarkdown': 'Body $id',
    'originalUrl': 'https://example.com/$id',
    'publishedAt': '2026-09-14T08:00:00Z',
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late _FakeNewsApi api;
  late NewsRepository repo;

  final seed = <Map<String, dynamic>>[
    _json('fin-1', category: 'Finance'),
    _json('ai-1', category: 'AI News'),
    _json('mov-1', category: 'Movies'),
    _json('gen-1', category: 'General'),
  ];

  setUp(() {
    NewsController.authGateTimeout = Duration.zero;
    NewsController.syncRetryDelays = const <Duration>[Duration.zero];
    NewsController.autoRemoteRefresh = true;
    NewsController.minAutoRefreshInterval = Duration.zero;
    NewsController.minForcedRefreshInterval = Duration.zero;
    AppTokenStore.instance.resetStartupGate();
    AppTokenStore.instance.markStartupReady();
    database = AppDatabase.forTesting(NativeDatabase.memory());
    api = _FakeNewsApi(List<Map<String, dynamic>>.from(seed));
    repo = NewsRepository(database, api);
  });

  tearDown(() async {
    NewsController.debugResetPolicy();
    AppTokenStore.instance.resetStartupGate();
    await database.close();
  });

  test('ensureFresh(force) coalesces overlapping RSS refreshes into one POST',
      () async {
    api.postDelay = const Duration(milliseconds: 80);
    final controller = NewsController(repo);
    addTearDown(controller.dispose);
    await controller.bootstrap();
    api.posts = 0;

    await Future.wait<void>([
      controller.ensureFresh(force: true),
      controller.ensureFresh(force: true),
      controller.ensureFresh(force: true),
    ]);

    expect(api.posts, 1, reason: 'tab-spam must not stampede /news/refresh');
  });

  test('forced refresh throttle skips a second POST inside the quiet window',
      () async {
    NewsController.minForcedRefreshInterval = const Duration(seconds: 30);
    final controller = NewsController(repo);
    addTearDown(controller.dispose);
    await controller.bootstrap();
    for (var i = 0; i < 40; i++) {
      if (api.posts > 0) break;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(api.posts, greaterThan(0));
    final afterBoot = api.posts;

    await controller.ensureFresh(force: true);
    expect(api.posts, afterBoot, reason: 'quiet window after last RSS');
  });

  test('empty RSS payload does not wipe local unread articles', () async {
    final controller = NewsController(repo);
    addTearDown(controller.dispose);
    await controller.bootstrap();
    expect(controller.state.valueOrNull, isNotEmpty);

    api.postEmpty = true;
    NewsController.minForcedRefreshInterval = Duration.zero;
    await controller.ensureFresh(force: true);

    final ids = (controller.state.valueOrNull ?? const []).map((a) => a.id);
    expect(ids, containsAll(['fin-1', 'ai-1', 'mov-1', 'gen-1']));
  });

  test('failed background refresh keeps the painted feed (not an error)',
      () async {
    final controller = NewsController(repo);
    addTearDown(controller.dispose);
    await controller.bootstrap();
    expect(controller.state.hasError, isFalse);
    expect(controller.state.valueOrNull, isNotEmpty);

    api.postThrows = true;
    NewsController.minForcedRefreshInterval = Duration.zero;
    await controller.ensureFresh(force: true);

    expect(controller.state.hasError, isFalse);
    expect(controller.state.valueOrNull, isNotEmpty);
  });

  test('autoRemoteRefresh=false never POSTs even when force is true', () async {
    NewsController.autoRemoteRefresh = false;
    final controller = NewsController(repo);
    addTearDown(controller.dispose);
    await controller.bootstrap();
    await controller.ensureFresh(force: true);
    expect(api.posts, 0);
    expect(controller.state.valueOrNull, isNotEmpty);
  });

  test('manual refresh() POSTs even when autoRemoteRefresh is off', () async {
    NewsController.autoRemoteRefresh = false;
    final controller = NewsController(repo);
    addTearDown(controller.dispose);
    await controller.bootstrap();
    expect(api.posts, 0);

    final newCount = await controller.refresh();
    expect(api.posts, 1);
    expect(newCount, 0);
    expect(controller.state.valueOrNull, isNotEmpty);
  });

  test('latest articles from RSS refresh appear without pull-to-refresh',
      () async {
    final controller = NewsController(repo);
    addTearDown(controller.dispose);
    await controller.bootstrap();

    api.articles = [
      ...seed,
      _json('fresh-1', category: 'AI News'),
    ];
    NewsController.minForcedRefreshInterval = Duration.zero;
    await controller.ensureFresh(force: true);

    expect(
      (controller.state.valueOrNull ?? const []).map((a) => a.id),
      contains('fresh-1'),
    );
  });
}
