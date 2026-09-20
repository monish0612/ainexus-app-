// Opening News must show every For You chip + Saved from bootstrap.
// Pull-to-refresh is not required for the first paint.

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

class _FakeApi extends ApiClient {
  _FakeApi(this.articles);

  final List<Map<String, dynamic>> articles;

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
    'date': '2026-09-14',
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
  final chip = find.byKey(ValueKey<String>('news-rail-$label'));
  expect(chip, findsOneWidget, reason: 'rail tab "$label" must stay on-screen');
  await tester.tap(chip);
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

  testWidgets(
      'every News chip and Saved populate from bootstrap — no pull required',
      (tester) async {
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
        ],
        child: MaterialApp(
          theme: _theme(),
          home: const Scaffold(body: NewsScreen()),
        ),
      ),
    );

    await tester.pump();
    await _waitFor(tester, find.text('FIN-FEATURED'));

    expect(find.byKey(const ValueKey<String>('news-category-rail')), findsOneWidget);

    expect(find.text('No articles in this category'), findsNothing);
    expect(find.text('AI-ROW'), findsOneWidget);
    expect(find.text('MOV-ROW'), findsOneWidget);
    expect(find.text('GEN-ROW'), findsOneWidget);

    await _tapChip(tester, 'AI News');
    expect(find.text('AI-ROW'), findsOneWidget);
    expect(find.text('FIN-FEATURED'), findsNothing);

    await _tapChip(tester, 'Finance');
    expect(find.text('FIN-FEATURED'), findsOneWidget);

    await _tapChip(tester, 'Movies');
    expect(find.text('MOV-ROW'), findsOneWidget);

    await _tapChip(tester, 'General');
    expect(find.text('GEN-ROW'), findsOneWidget);

    await tester.tap(find.byIcon(LucideIcons.bookmark).hitTestable().first);
    await _frames(tester, 8);
    expect(find.text('SAVED-KEEP'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 80));
  });
}
