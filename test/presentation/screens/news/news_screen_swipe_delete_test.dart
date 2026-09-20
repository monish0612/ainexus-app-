// Integration tests: For You swipe-to-delete on All / AI News / Finance
// (and Movies / General) must DELETE the article — never page to Saved,
// never toggle isSaved.
//
// Real NewsScreen + real NewsController + in-memory Drift + fake API.
// FAB pulse animation repeats forever, so these tests never pumpAndSettle.

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
import 'package:ai_nexus/presentation/screens/news/news_screen.dart';
import 'package:ai_nexus/presentation/widgets/news_action_fab.dart';
import 'package:ai_nexus/presentation/widgets/swipe_to_delete.dart';

class _FakeApi extends ApiClient {
  _FakeApi(this.articles);

  List<Map<String, dynamic>> articles;
  final List<String> calls = <String>[];

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
    calls.add('GET $path');
    if (path.contains('/api/v1/news') && !path.contains('/news/')) {
      return _ok<T>(path, <String, dynamic>{'articles': articles});
    }
    return _ok<T>(path, <String, dynamic>{'articles': articles});
  }

  @override
  Future<Response<T>> delete<T>(String path) async {
    calls.add('DELETE $path');
    final id = path.split('/').last;
    articles = articles.where((a) => a['id'] != id).toList();
    return _ok<T>(path, <String, dynamic>{'ok': true});
  }

  @override
  Future<Response<T>> post<T>(
    String path, {
    Object? data,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    calls.add('POST $path');
    return _ok<T>(path, <String, dynamic>{'articles': articles});
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
    'date': '2026-08-21',
    'isSaved': isSaved,
    'isRead': false,
    'summaryMarkdown': 'Body for $id',
    'originalUrl': 'https://example.com/$id',
    'publishedAt': published,
  };
}

ThemeData _theme() {
  return ThemeData(
    extensions: const <ThemeExtension<dynamic>>[
      AppColors(
        shadowColor: Color(0x66000000),
        glassFill: Color(0x0DFFFFFF),
        scrim: Color(0x99000000),
        cardGradientTop: Color(0xFF0B0B0F),
        cardGradientBottom: Color(0xFF060608),
        shimmerBase: Color(0x14FFFFFF),
        shimmerHighlight: Color(0x2EFFFFFF),
        bg: Color(0xFFFFFFFF),
        bg1: Color(0xFFF8F9FB),
        bg2: Color(0xFFEEF1F5),
        bg3: Color(0xFFE5E9EF),
        bg4: Color(0xFFDDE2EA),
        text: Color(0xFF101828),
        text2: Color(0xFF1F2937),
        text3: Color(0xFF374151),
        text4: Color(0xFF6B7280),
        text5: Color(0xFF94A3B8),
        border: Color(0xFFE2E8F0),
        border2: Color(0xFFCBD5E1),
        headerBg: Color(0xFFFFFFFF),
        navBg: Color(0xFFFFFFFF),
        isDark: false,
      ),
    ],
  );
}

Future<void> _frames(WidgetTester tester, [int n = 10]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _waitFor(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 50; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) return;
  }
  final texts = find
      .byType(Text)
      .evaluate()
      .map((e) => (e.widget as Text).data)
      .whereType<String>()
      .toList();
  fail('Never found $finder. Visible text: $texts');
}

Future<void> _tapChip(WidgetTester tester, String label) async {
  final scaffolds = find.byType(Scaffold);
  if (scaffolds.evaluate().isNotEmpty) {
    ScaffoldMessenger.of(tester.element(scaffolds.first)).clearSnackBars();
    await tester.pump();
  }
  final chip = find.byKey(ValueKey<String>('news-rail-$label'));
  expect(chip, findsOneWidget, reason: 'rail tab "$label" must stay on-screen');
  await tester.tap(chip);
  await _frames(tester, 6);
}

Future<void> _dismount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 80));
}

Future<void> _swipeAway(WidgetTester tester, String title) async {
  await tester.drag(find.text(title), const Offset(320, 0));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
  expect(find.byKey(const Key('swipe-delete-confirm')), findsOneWidget,
      reason: 'swipe must ask before deleting "$title"');
  await tester.tap(find.byKey(const Key('swipe-delete-confirm')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await _frames(tester, 8);
}

Future<void> _swipeThenKeep(WidgetTester tester, String title) async {
  await tester.drag(find.text(title), const Offset(320, 0));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
  expect(find.text('Delete this article?'), findsOneWidget);
  await tester.tap(find.byKey(const Key('swipe-delete-keep')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await _frames(tester, 6);
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
        published: '2026-08-21T12:00:00Z'),
    _json('fin-row',
        category: 'Finance',
        title: 'FIN-ROW',
        published: '2026-08-21T11:00:00Z'),
    _json('ai-row',
        category: 'AI News',
        title: 'AI-ROW',
        published: '2026-08-21T10:00:00Z'),
    _json('mov-row',
        category: 'Movies',
        title: 'MOV-ROW',
        published: '2026-08-21T09:00:00Z'),
    _json('gen-row',
        category: 'General',
        title: 'GEN-ROW',
        published: '2026-08-21T08:00:00Z'),
    _json('saved-keep',
        category: 'Finance',
        title: 'SAVED-KEEP',
        published: '2026-08-21T07:00:00Z',
        isSaved: true),
  ];

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    NewsController.authGateTimeout = Duration.zero;
    NewsController.autoRemoteRefresh = false;
    AppTokenStore.instance.resetStartupGate();
    AppTokenStore.instance.markStartupReady();
    database = AppDatabase.forTesting(NativeDatabase.memory());
    api = _FakeApi(List<Map<String, dynamic>>.from(seed));
    repo = NewsRepository(database, api);
    await repo.syncNews();
    final rows = await database.select(database.newsArticles).get();
    expect(rows.length, seed.length, reason: 'fake news API must seed Drift');
  });

  tearDown(() async {
    NewsController.debugResetPolicy();
    AppTokenStore.instance.resetStartupGate();
    await database.close();
  });

  Future<void> pumpNews(WidgetTester tester) async {
    tester.view.physicalSize = const Size(720, 900);
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
          newsControllerProvider.overrideWith((ref) {
            // Seeded Drift already has rows; skip bootstrap() so a late
            // syncNews cannot set state after the test disposes the notifier.
            return NewsController(repo);
          }),
        ],
        child: MaterialApp(
          theme: _theme(),
          home: const Scaffold(body: NewsScreen()),
        ),
      ),
    );
    await tester.pump();
    await _waitFor(tester, find.text('FIN-FEATURED'));
  }

  testWidgets(
      'All / AI News / Finance swipe-delete like Movies — never opens Saved',
      (tester) async {
    await pumpNews(tester);

    expect(find.byType(SwipeToDelete), findsWidgets);
    expect(find.byType(NewsActionFab), findsOneWidget);
    expect(find.text('FIN-FEATURED'), findsOneWidget);
    expect(find.text('FIN-ROW'), findsOneWidget);
    expect(find.text('AI-ROW'), findsOneWidget);
    expect(find.text('MOV-ROW'), findsOneWidget);
    expect(find.text('GEN-ROW'), findsOneWidget);
    expect(find.text('SAVED-KEEP'), findsNothing);

    await _swipeThenKeep(tester, 'FIN-FEATURED');
    expect(find.text('FIN-FEATURED'), findsOneWidget,
        reason: 'Keep must leave the featured article in the feed');

    await tester.drag(find.text('FIN-FEATURED').first, const Offset(320, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Delete this article?'), findsOneWidget);
    final edge = await tester.startGesture(const Offset(16, 72));
    await tester.pump();
    await edge.moveBy(const Offset(220, 0));
    await edge.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await _frames(tester, 6);
    expect(find.text('Delete this article?'), findsNothing,
        reason: 'swipe-back on the confirm overlay must close the popup');
    expect(find.text('FIN-FEATURED'), findsOneWidget,
        reason: 'swipe-back on the confirm overlay must not delete');

    // Swipe featured Finance card on All.
    await _swipeAway(tester, 'FIN-FEATURED');
    expect(find.text('FIN-FEATURED'), findsNothing);
    expect(find.text('SAVED-KEEP'), findsNothing);

    // Swipe list row still on All.
    await _swipeAway(tester, 'FIN-ROW');
    expect(find.text('FIN-ROW'), findsNothing);

    await _tapChip(tester, 'AI News');
    expect(find.text('AI-ROW'), findsOneWidget);
    await _swipeAway(tester, 'AI-ROW');
    expect(find.text('AI-ROW'), findsNothing);
    expect(find.text('SAVED-KEEP'), findsNothing);

    await _tapChip(tester, 'Finance');
    expect(find.text('No articles in this category'), findsOneWidget);

    await _tapChip(tester, 'Movies');
    expect(find.text('MOV-ROW'), findsOneWidget);
    await _swipeAway(tester, 'MOV-ROW');
    expect(find.text('MOV-ROW'), findsNothing);

    await _tapChip(tester, 'General');
    expect(find.text('GEN-ROW'), findsOneWidget);
    // Under-threshold: article stays, still not Saved.
    await tester.drag(find.text('GEN-ROW'), const Offset(40, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('GEN-ROW'), findsOneWidget);
    expect(find.text('SAVED-KEEP'), findsNothing);

    await _swipeAway(tester, 'GEN-ROW');
    expect(find.text('GEN-ROW'), findsNothing);

    // Saved library is a header bookmark, not a sibling tab.
    await tester.tap(find.byIcon(LucideIcons.bookmark).hitTestable().first);
    await _frames(tester, 8);
    expect(find.text('SAVED-KEEP'), findsOneWidget);
    expect(find.text('FIN-FEATURED'), findsNothing);
    expect(find.text('FIN-ROW'), findsNothing);
    expect(find.text('AI-ROW'), findsNothing);
    expect(find.text('MOV-ROW'), findsNothing);
    expect(find.text('GEN-ROW'), findsNothing);

    await tester.tap(find.byIcon(LucideIcons.trash2));
    await _frames(tester, 8);
    expect(find.text('SAVED-KEEP'), findsNothing);

    await tester.tap(find.byIcon(LucideIcons.arrowLeft));
    await _frames(tester, 8);
    expect(find.text('SAVED-KEEP'), findsNothing);

    final deletes = api.calls.where((c) => c.startsWith('DELETE')).toList();
    expect(deletes.any((c) => c.contains('fin-feat')), isTrue);
    expect(deletes.any((c) => c.contains('fin-row')), isTrue);
    expect(deletes.any((c) => c.contains('ai-row')), isTrue);
    expect(deletes.any((c) => c.contains('mov-row')), isTrue);
    expect(deletes.any((c) => c.contains('gen-row')), isTrue);
    expect(deletes.any((c) => c.contains('saved-keep')), isTrue);
    expect(
      api.calls.any((c) => c.endsWith('/save')),
      isFalse,
      reason: 'swipe-delete must never POST .../save',
    );
    await _dismount(tester);
  });

  testWidgets('All / AI News / Finance keep Summarize on the FAB',
      (tester) async {
    await pumpNews(tester);

    await tester.tap(find.byIcon(LucideIcons.sparkles).hitTestable().first);
    await _frames(tester, 8);
    expect(find.text('Summarize'), findsOneWidget);
    expect(find.textContaining('Swipe a card left or right'), findsOneWidget);
    await _dismount(tester);
  });

  testWidgets('Movies FAB still offers Summarize now that All includes it',
      (tester) async {
    await pumpNews(tester);

    await _tapChip(tester, 'Movies');
    expect(find.byIcon(LucideIcons.sparkles), findsOneWidget);
    await tester.tap(find.byIcon(LucideIcons.sparkles).hitTestable().first);
    await _frames(tester, 8);
    expect(find.text('Summarize'), findsOneWidget);
    expect(find.text('Clear All'), findsOneWidget);
    await _dismount(tester);
  });
}
