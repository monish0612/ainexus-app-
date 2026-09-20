// Deep widget pass over the redesigned News tab:
// light + dark, cramped 360px rail, Saved bookmark, no pager, Movies
// stays on All, follow-up entry via Saved is a separate route.

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ai_nexus/core/auth/app_token_store.dart';
import 'package:ai_nexus/core/di/injection.dart';
import 'package:ai_nexus/core/network/api_client.dart';
import 'package:ai_nexus/core/theme/app_colors.dart';
import 'package:ai_nexus/data/local/database/app_database.dart';
import 'package:ai_nexus/data/repositories/news_repository.dart';
import 'package:ai_nexus/presentation/screens/news/news_controller.dart';
import 'package:ai_nexus/presentation/screens/news/news_feed_filters.dart';
import 'package:ai_nexus/presentation/screens/news/news_saved_page.dart';
import 'package:ai_nexus/presentation/screens/news/news_screen.dart';
import 'package:ai_nexus/presentation/widgets/news_action_fab.dart';
import 'package:ai_nexus/presentation/widgets/swipe_to_delete.dart';

class _FakeApi extends ApiClient {
  _FakeApi(this.articles);

  List<Map<String, dynamic>> articles;
  int posts = 0;

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

  @override
  Future<Response<T>> delete<T>(String path) async {
    final id = path.split('/').last;
    articles = articles.where((a) => a['id'] != id).toList();
    return _ok<T>(path, <String, dynamic>{'ok': true});
  }
}

Map<String, dynamic> _json(
  String id, {
  required String category,
  required String title,
  required String published,
  bool isSaved = false,
}) {
  return <String, dynamic>{
    'id': id,
    'title': title,
    'excerpt': 'excerpt-$id',
    'source': 'Source',
    'category': category,
    'imageUrl': '',
    'readTime': 2,
    'date': '2026-09-14',
    'isSaved': isSaved,
    'isRead': false,
    'summaryMarkdown': 'Body for $id',
    'originalUrl': 'https://example.com/$id',
    'publishedAt': published,
  };
}

ThemeData _themeFor(AppColors colors) {
  return ThemeData(
    brightness: colors.isDark ? Brightness.dark : Brightness.light,
    scaffoldBackgroundColor: colors.bg,
    extensions: <ThemeExtension<dynamic>>[colors],
  );
}

Future<void> _frames(WidgetTester tester, [int n = 8]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _waitFor(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 50; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Never found $finder');
}

/// [RefreshIndicatorState.show] waits on animation frames — never await
/// it before pumping, or the test deadlocks.
Future<void> _showRefresh(WidgetTester tester, Finder finder) async {
  final done = tester.state<RefreshIndicatorState>(finder).show();
  await tester.pump();
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  await done;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  late AppDatabase database;
  late _FakeApi api;
  late NewsRepository repo;

  final seed = <Map<String, dynamic>>[
    _json('fin-feat',
        category: 'Finance',
        title: 'FIN-FEATURED',
        published: '2026-09-14T12:00:00Z'),
    _json('ai-row',
        category: 'AI News',
        title: 'AI-ROW',
        published: '2026-09-14T11:00:00Z'),
    _json('mov-row',
        category: 'Movies',
        title: 'MOV-ROW',
        published: '2026-09-14T10:00:00Z'),
    _json('gen-row',
        category: 'General',
        title: 'GEN-ROW',
        published: '2026-09-14T09:00:00Z'),
    _json('saved-keep',
        category: 'Finance',
        title: 'SAVED-KEEP',
        published: '2026-09-14T08:00:00Z',
        isSaved: true),
  ];

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    NewsController.authGateTimeout = Duration.zero;
    NewsController.syncRetryDelays = const <Duration>[Duration.zero];
    NewsController.autoRemoteRefresh = false;
    AppTokenStore.instance.resetStartupGate();
    AppTokenStore.instance.markStartupReady();
    database = AppDatabase.forTesting(NativeDatabase.memory());
    api = _FakeApi(List<Map<String, dynamic>>.from(seed));
    repo = NewsRepository(database, api);
  });

  tearDown(() async {
    NewsController.debugResetPolicy();
    AppTokenStore.instance.resetStartupGate();
    await database.close();
  });

  Future<void> pumpNews(
    WidgetTester tester, {
    required AppColors colors,
    Size size = const Size(360, 800),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          appDatabaseProvider.overrideWithValue(database),
          apiClientProvider.overrideWithValue(api),
          newsRepositoryProvider.overrideWithValue(repo),
        ],
        child: MaterialApp(
          theme: _themeFor(colors),
          home: const Scaffold(body: NewsScreen()),
        ),
      ),
    );
    await tester.pump();
    await _waitFor(tester, find.text('FIN-FEATURED'));
  }

  for (final colors in [AppColors.white, AppColors.dark]) {
    final label = colors.isDark ? 'dark' : 'light';

    testWidgets('$label News paints All + every rail tab on a 360px phone',
        (tester) async {
      await pumpNews(tester, colors: colors);

      expect(find.byType(TabBarView), findsNothing);
      expect(find.byType(SwipeToDelete), findsWidgets);
      expect(find.byType(NewsActionFab), findsOneWidget);
      expect(find.text('MOV-ROW'), findsOneWidget);
      expect(find.text('GEN-ROW'), findsOneWidget);
      expect(find.text('SAVED-KEEP'), findsNothing);
      expect(find.byIcon(LucideIcons.bell), findsNothing);

      for (final tab in kNewsCategoryRailLabels) {
        final chip = find.byKey(ValueKey<String>('news-rail-$tab'));
        expect(chip, findsOneWidget, reason: '$tab missing in $label');
        expect(chip.hitTestable(), findsOneWidget,
            reason: '$tab must stay tappable at 360px in $label');
      }

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 80));
    });
  }

  testWidgets('rapid rail taps filter without dropping Movies from All',
      (tester) async {
    await pumpNews(tester, colors: AppColors.white);

    await tester.tap(find.byKey(const ValueKey<String>('news-rail-Movies')));
    await _frames(tester);
    expect(find.text('MOV-ROW'), findsOneWidget);
    expect(find.text('FIN-FEATURED'), findsNothing);

    await tester.tap(find.byKey(const ValueKey<String>('news-rail-General')));
    await _frames(tester);
    expect(find.text('GEN-ROW'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('news-rail-All')));
    await _frames(tester);
    expect(find.text('FIN-FEATURED'), findsOneWidget);
    expect(find.text('AI-ROW'), findsOneWidget);
    expect(find.text('MOV-ROW'), findsOneWidget);
    expect(find.text('GEN-ROW'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 80));
  });

  testWidgets('bookmark opens Saved library; search and back keep follow-up path',
      (tester) async {
    await pumpNews(tester, colors: AppColors.dark);

    await tester.tap(find.byIcon(LucideIcons.bookmark).hitTestable().first);
    await _frames(tester, 10);
    expect(find.byType(NewsSavedPage), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(NewsSavedPage),
        matching: find.text('SAVED-KEEP'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(NewsSavedPage),
        matching: find.text('FIN-FEATURED'),
      ),
      findsNothing,
    );

    await tester.enterText(find.byType(TextField), 'no-such-saved');
    await _frames(tester, 4);
    expect(find.textContaining('No results'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'SAVED');
    await _frames(tester, 4);
    expect(
      find.descendant(
        of: find.byType(NewsSavedPage),
        matching: find.text('SAVED-KEEP'),
      ),
      findsOneWidget,
    );

    expect(find.byKey(const Key('news-saved-refresh')), findsOneWidget);
    expect(api.posts, 0);
    await _showRefresh(tester, find.byKey(const Key('news-saved-refresh')));
    expect(api.posts, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 80));
  });

  testWidgets('pull-to-refresh stays on the feed and POSTs /news/refresh',
      (tester) async {
    await pumpNews(tester, colors: AppColors.white);

    expect(find.byKey(const Key('news-feed-refresh')), findsOneWidget);
    expect(find.byType(RefreshIndicator), findsOneWidget);
    expect(api.posts, 0,
        reason: 'auto-load is GET-only in tests; pull is the POST path');

    api.articles = [
      ...seed,
      _json(
        'fresh-pull',
        category: 'AI News',
        title: 'FRESH-PULL',
        published: '2026-09-14T13:00:00Z',
      ),
    ];

    await _showRefresh(tester, find.byKey(const Key('news-feed-refresh')));

    expect(api.posts, 1);
    expect(find.text('FRESH-PULL'), findsOneWidget);
    expect(find.textContaining('new article'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 80));
  });
}
