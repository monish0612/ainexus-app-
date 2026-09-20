// NewsController must paint the feed on its own after cold start.
// Pull-to-refresh is a user gesture, not the first-load path.
//
// Regression: GET /news raced the post-first-frame JWT, 401'd, then the
// empty Drift watch replaced loading/error with data([]) — every For You
// chip and Saved looked empty until the user pulled down.

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_nexus/core/auth/app_token_store.dart';
import 'package:ai_nexus/core/di/injection.dart';
import 'package:ai_nexus/core/network/api_client.dart';
import 'package:ai_nexus/data/local/database/app_database.dart';
import 'package:ai_nexus/data/repositories/news_repository.dart';
import 'package:ai_nexus/presentation/screens/news/news_controller.dart';

class _FakeNewsApi extends ApiClient {
  _FakeNewsApi(this.articles, {this.requireToken = false});

  List<Map<String, dynamic>> articles;
  bool requireToken;
  int unauthorizedUntilGet = 0;
  int gets = 0;
  int posts = 0;

  Response<T> _ok<T>(String path, Object? data) => Response<T>(
        requestOptions: RequestOptions(path: path),
        data: data as T?,
        statusCode: 200,
      );

  Never _unauthorized(String path) {
    throw DioException(
      requestOptions: RequestOptions(path: path),
      response: Response<dynamic>(
        requestOptions: RequestOptions(path: path),
        statusCode: 401,
      ),
      type: DioExceptionType.badResponse,
    );
  }

  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
  }) async {
    gets++;
    if (requireToken && !AppTokenStore.instance.hasToken) {
      _unauthorized(path);
    }
    if (unauthorizedUntilGet > 0 && gets <= unauthorizedUntilGet) {
      _unauthorized(path);
    }
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
    return _ok<T>(path, <String, dynamic>{'articles': articles});
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
    'isSaved': id.startsWith('saved'),
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
    _json('saved-1', category: 'Finance'),
  ];

  setUp(() {
    NewsController.authGateTimeout = Duration.zero;
    NewsController.syncRetryDelays = const <Duration>[Duration.zero];
    NewsController.autoRemoteRefresh = false;
    AppTokenStore.instance.resetStartupGate();
    AppTokenStore.instance.refresher = null;
    database = AppDatabase.forTesting(NativeDatabase.memory());
    api = _FakeNewsApi(List<Map<String, dynamic>>.from(seed));
    repo = NewsRepository(database, api);
  });

  tearDown(() async {
    NewsController.debugResetPolicy();
    AppTokenStore.instance.refresher = null;
    AppTokenStore.instance.resetStartupGate();
    await AppTokenStore.instance.clear();
    await database.close();
  });

  test('bootstrap loads the feed without pull-to-refresh', () async {
    final controller = NewsController(repo);
    addTearDown(controller.dispose);

    expect(controller.state.isLoading, isTrue);
    await controller.bootstrap();

    final articles = controller.state.valueOrNull ?? const [];
    expect(controller.state.hasError, isFalse);
    expect(articles.map((a) => a.id), containsAll(['fin-1', 'ai-1', 'mov-1', 'saved-1']));
    expect(api.gets, greaterThan(0));
    expect(api.posts, 0, reason: 'first load is GET /news, not POST /refresh');
  });

  test('autoRemoteRefresh POSTs /news/refresh after the fast GET', () async {
    NewsController.autoRemoteRefresh = true;
    NewsController.minForcedRefreshInterval = Duration.zero;
    NewsController.minAutoRefreshInterval = Duration.zero;
    AppTokenStore.instance.markStartupReady();
    final controller = NewsController(repo);
    addTearDown(controller.dispose);

    await controller.bootstrap();
    for (var i = 0; i < 20; i++) {
      if (api.posts > 0) break;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(api.gets, greaterThan(0));
    expect(api.posts, greaterThan(0),
        reason: 'latest articles must ingest without pull-to-refresh');
  });

  test('empty watch must not paint data([]) while bootstrap is in flight',
      () async {
    api.articles = [];
    final controller = NewsController(repo);
    addTearDown(controller.dispose);

    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(controller.state.isLoading, isTrue);
    expect(controller.state.hasValue, isFalse);
  });

  test('empty snapshot after a populated feed is applied (last delete)',
      () async {
    await repo.syncNews();
    final controller = NewsController(repo);
    addTearDown(controller.dispose);

    for (var i = 0; i < 20; i++) {
      if (controller.state.valueOrNull?.isNotEmpty == true) break;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(controller.state.valueOrNull, isNotEmpty);

    await database.delete(database.newsArticles).go();
    for (var i = 0; i < 20; i++) {
      if (controller.state.hasValue &&
          (controller.state.valueOrNull ?? const []).isEmpty) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    fail('Deleting the last local row did not paint an empty feed');
  });

  test('failed first GET stays an error, not a fake empty feed', () async {
    api.unauthorizedUntilGet = 99;
    final controller = NewsController(repo);
    addTearDown(controller.dispose);

    await controller.bootstrap();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(controller.state.hasError, isTrue);
    expect(controller.state.valueOrNull, isNull);
  });

  test('401 then success retries until the feed appears', () async {
    NewsController.syncRetryDelays = const <Duration>[
      Duration.zero,
      Duration.zero,
      Duration.zero,
    ];
    api.unauthorizedUntilGet = 2;
    final controller = NewsController(repo);
    addTearDown(controller.dispose);

    await controller.bootstrap();

    expect(controller.state.hasError, isFalse);
    expect(controller.state.valueOrNull, isNotEmpty);
    expect(api.gets, 3);
  });

  test('waits for the auth gate so the first GET is not a 401', () async {
    NewsController.authGateTimeout = const Duration(seconds: 3);
    NewsController.syncRetryDelays = const <Duration>[Duration.zero];
    api.requireToken = true;

    final controller = NewsController(repo);
    addTearDown(controller.dispose);

    final boot = controller.bootstrap();
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(controller.state.hasValue, isFalse);
    expect(api.gets, 0, reason: 'must not hit /news before the JWT gate');

    await AppTokenStore.instance.setToken('jwt-news');
    AppTokenStore.instance.refresher = () async => true;
    AppTokenStore.instance.markStartupReady();
    await boot;

    expect(controller.state.valueOrNull, isNotEmpty);
    expect(api.gets, 1);
  });

  test('cached rows paint immediately, even before the network returns',
      () async {
    await repo.syncNews();
    api.gets = 0;
    api.articles = [
      ...seed,
      _json('fin-2', category: 'Finance'),
    ];

    final controller = NewsController(repo);
    addTearDown(controller.dispose);
    final boot = controller.bootstrap();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final cached = controller.state.valueOrNull ?? const [];
    expect(cached.map((a) => a.id), contains('fin-1'));

    await boot;
    expect(
      controller.state.valueOrNull!.map((a) => a.id),
      contains('fin-2'),
    );
  });

  test('provider bootstrap auto-starts without calling refresh()', () async {
    AppTokenStore.instance.markStartupReady();
    final container = ProviderContainer(
      overrides: [
        newsRepositoryProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(container.dispose);

    final first = container.read(newsControllerProvider);
    expect(first.isLoading || first.hasValue, isTrue);

    for (var i = 0; i < 40; i++) {
      final next = container.read(newsControllerProvider);
      if (next.valueOrNull?.isNotEmpty == true) return;
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    fail('newsControllerProvider never received articles without refresh()');
  });
}
