// Deep widget tests for search A−/A+ on the real screens:
// SearchLookupScreen (grounded + Tavily), SavedSearchDetailSheet,
// SearchFollowUpFab sheet, and news-reader preference sharing.
//
// Pulse/entry animations use repeating controllers — never pumpAndSettle.

import 'dart:convert';

import 'package:ai_nexus/core/di/injection.dart';
import 'package:ai_nexus/core/network/api_client.dart';
import 'package:ai_nexus/core/services/saved_search_store.dart';
import 'package:ai_nexus/core/theme/app_colors.dart';
import 'package:ai_nexus/data/local/database/app_database.dart';
import 'package:ai_nexus/data/services/user_preferences_service.dart';
import 'package:ai_nexus/domain/entities/news_entities.dart';
import 'package:ai_nexus/domain/entities/saved_search.dart';
import 'package:ai_nexus/domain/entities/tutor_entities.dart';
import 'package:ai_nexus/presentation/screens/news/article_detail_modal.dart';
import 'package:ai_nexus/presentation/screens/news/news_reader_text_scale.dart';
import 'package:ai_nexus/presentation/screens/settings/settings_controller.dart';
import 'package:ai_nexus/presentation/screens/tutor/saved_search_detail_sheet.dart';
import 'package:ai_nexus/presentation/screens/tutor/search_answer_text_scale.dart';
import 'package:ai_nexus/presentation/screens/tutor/search_followup_sheet.dart';
import 'package:ai_nexus/presentation/screens/tutor/search_lookup_screen.dart';
import 'package:ai_nexus/presentation/widgets/search_result_actions.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

ThemeData _theme() => ThemeData(
      extensions: const <ThemeExtension<dynamic>>[
        AppColors(
          shadowColor: Color(0x66000000),
          glassFill: Color(0x0DFFFFFF),
          scrim: Color(0x99000000),
          cardGradientTop: Color(0xFF0B0B0F),
          cardGradientBottom: Color(0xFF060608),
          shimmerBase: Color(0x14FFFFFF),
          shimmerHighlight: Color(0x2EFFFFFF),
          bg: Color(0xFF000000),
          bg1: Color(0xFF060608),
          bg2: Color(0xFF131316),
          bg3: Color(0xFF1B1B1F),
          bg4: Color(0xFF26262B),
          text: Color(0xFFF1F5F9),
          text2: Color(0xFF94A3B8),
          text3: Color(0xFF6B7280),
          text4: Color(0xFF4B5563),
          text5: Color(0xFF374151),
          border: Color(0xFF1F2937),
          border2: Color(0xFF111827),
          headerBg: Color(0xFF000000),
          navBg: Color(0xFF000000),
          isDark: true,
        ),
      ],
    );

double _scalerOf(WidgetTester tester, Finder finder) {
  final ctx = tester.element(finder);
  return MediaQuery.textScalerOf(ctx).scale(1.0);
}

Future<void> _drain(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

Future<void> _dismount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 80));
}

class _StubAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromBytes(
      utf8.encode('{}'),
      200,
      headers: {
        'content-type': ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

const _groundedAnswer =
    'The monsoon arrived overnight and the streets of Chennai filled with rain.';
const _tavilyAnswer =
    'LOOKUP-TAVILY-SENTINEL tomatoes and wet earth on the streets.';

GroundedSearchResponse _grounded() => const GroundedSearchResponse(
      answer: _groundedAnswer,
      query: 'monsoon chennai',
      model: 'gemini-2.5-flash',
      searchQueries: ['monsoon chennai'],
      sources: [
        GroundedSource(
          index: 1,
          title: 'BBC Weather Sentinel',
          url: 'https://example.com/bbc-weather',
        ),
      ],
      citations: [],
    );

TavilySearchResponse _tavily() => const TavilySearchResponse(
      answer: _tavilyAnswer,
      query: 'monsoon chennai',
      results: [
        TavilyResultItem(
          title: 'Tavily Source Sentinel',
          url: 'https://example.com/tavily',
          content: 'snippet',
          score: 0.9,
        ),
      ],
    );

Future<void> _pumpLookup(
  WidgetTester tester, {
  GroundedSearchResponse? grounded,
  TavilySearchResponse? tavily,
  Size size = const Size(390, 844),
  List<Override> overrides = const [],
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: _theme(),
        home: SearchLookupScreen(
          query: 'monsoon chennai',
          debugGroundedResult: grounded,
          debugTavilyResult: tavily,
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

Future<({SavedSearchStore store, AppDatabase db})> _savedBootstrap() async {
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  final store = SavedSearchStore.instance
    ..debugResetForTests()
    ..init(db, null);
  addTearDown(() async {
    store.debugResetForTests();
    await db.close();
  });
  return (store: store, db: db);
}

Future<void> _pumpSaved(
  WidgetTester tester, {
  required SavedSearchStore store,
  required AppDatabase db,
  required String entryId,
  List<Override> overrides = const [],
}) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        savedSearchStoreProvider.overrideWithValue(store),
        appDatabaseProvider.overrideWithValue(db),
        ...overrides,
      ],
      child: MaterialApp(
        theme: _theme(),
        home: Scaffold(body: SavedSearchDetailSheet(entryId: entryId)),
      ),
    ),
  );
}

Future<SettingsController> _settings() async {
  SharedPreferences.setMockInitialValues({
    'lite_model': 'gemini-2.5-flash-lite',
    'deep_model': 'gemini-2.5-pro',
    'xgrok_enabled': false,
    'online_search_provider': 'gemini',
    'default_followup_provider': 'gemini',
  });
  final apiClient = ApiClient();
  apiClient.dio.httpClientAdapter = _StubAdapter();
  final prefs = await SharedPreferences.getInstance();
  return SettingsController(prefs, UserPreferencesService(apiClient));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  tearDown(() {
    SearchFollowUpStore.instance.debugResetForTests();
  });

  group('SearchLookupScreen — grounded', () {
    testWidgets('A−/A+ scale the answer and leave Copy / ANSWER / sources',
        (tester) async {
      await _pumpLookup(tester, grounded: _grounded());

      expect(find.byKey(kSearchAnswerTextSizeBarKey), findsOneWidget);
      expect(find.text('ANSWER'), findsOneWidget);
      expect(find.text('Copy'), findsOneWidget);
      expect(find.textContaining('Chennai filled with rain'), findsOneWidget);
      expect(find.text('1 source'), findsOneWidget);
      expect(find.byType(SearchFollowUpFab), findsOneWidget);
      expect(find.byKey(kSearchResultShareKey), findsOneWidget);
      expect(find.byType(SelectionArea), findsWidgets);
      expect(find.byType(EditableText), findsNothing);
      final bodies = tester.widgetList<MarkdownBody>(find.byType(MarkdownBody));
      expect(bodies, isNotEmpty);
      expect(bodies.every((b) => !b.selectable), isTrue);

      expect(
        _scalerOf(tester, find.textContaining('Chennai filled with rain')),
        closeTo(1.0, 0.01),
      );
      expect(_scalerOf(tester, find.text('Copy')), closeTo(1.0, 0.01));
      expect(_scalerOf(tester, find.text('ANSWER')), closeTo(1.0, 0.01));
      expect(_scalerOf(tester, find.text('1 source')), closeTo(1.0, 0.01));

      await tester.tap(find.byKey(kSearchAnswerTextIncreaseKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));

      expect(
        _scalerOf(tester, find.textContaining('Chennai filled with rain')),
        closeTo(1.15, 0.01),
      );
      expect(_scalerOf(tester, find.text('Copy')), closeTo(1.0, 0.01));
      expect(_scalerOf(tester, find.text('ANSWER')), closeTo(1.0, 0.01));
      expect(_scalerOf(tester, find.text('1 source')), closeTo(1.0, 0.01));
      expect(find.text('Search'), findsOneWidget);

      await tester.tap(find.text('1 source'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('BBC Weather Sentinel'), findsOneWidget);
      expect(
        _scalerOf(tester, find.text('BBC Weather Sentinel')),
        closeTo(1.0, 0.01),
      );
      expect(tester.takeException(), isNull);
      await _dismount(tester);
    });

    testWidgets('max scale on a 320px phone does not overflow grounded card',
        (tester) async {
      await _pumpLookup(
        tester,
        grounded: _grounded(),
        size: const Size(320, 1400),
        overrides: [
          newsReaderTextScaleProvider.overrideWith(
            (ref) => NewsReaderTextScale(
              initial: kNewsReaderTextScaleMax,
              hydrate: false,
            ),
          ),
        ],
      );

      expect(tester.takeException(), isNull);
      expect(find.textContaining('Chennai filled with rain'), findsOneWidget);
      expect(find.text('Copy'), findsOneWidget);
      expect(find.byKey(kSearchResultShareKey), findsOneWidget);
      expect(
        _scalerOf(tester, find.textContaining('Chennai filled with rain')),
        closeTo(kNewsReaderTextScaleMax, 0.01),
      );
      expect(_scalerOf(tester, find.text('Copy')), closeTo(1.0, 0.01));
      await _dismount(tester);
    });
  });

  group('SearchLookupScreen — Tavily', () {
    testWidgets('A−/A+ scale the Tavily answer; Copy and AI ANSWER stay put',
        (tester) async {
      await _pumpLookup(tester, tavily: _tavily());

      expect(find.byKey(kSearchAnswerTextSizeBarKey), findsOneWidget);
      expect(find.text('AI ANSWER'), findsOneWidget);
      expect(find.textContaining('LOOKUP-TAVILY-SENTINEL'), findsOneWidget);
      expect(find.byType(SearchFollowUpFab), findsNothing);

      await tester.tap(find.byKey(kSearchAnswerTextIncreaseKey));
      await tester.pump();

      expect(
        _scalerOf(tester, find.textContaining('LOOKUP-TAVILY-SENTINEL')),
        closeTo(1.15, 0.01),
      );
      expect(_scalerOf(tester, find.text('Copy')), closeTo(1.0, 0.01));
      expect(_scalerOf(tester, find.text('AI ANSWER')), closeTo(1.0, 0.01));

      await tester.tap(find.byKey(kSearchAnswerTextDecreaseKey));
      await tester.pump();
      expect(
        _scalerOf(tester, find.textContaining('LOOKUP-TAVILY-SENTINEL')),
        closeTo(1.0, 0.01),
      );
      expect(tester.takeException(), isNull);
      await _dismount(tester);
    });
  });

  group('SavedSearchDetailSheet', () {
    testWidgets(
        'snapshot body and assistant chat scale; user chat and chrome do not',
        (tester) async {
      const snapshot =
          'SAVED-SNAPSHOT-SENTINEL a long enough original answer body '
          'that still renders inside the collapsed snapshot card.';
      const result = TavilySearchResponse(
        answer: snapshot,
        query: 'who won?',
        results: <TavilyResultItem>[],
      );
      final ctx = await _savedBootstrap();
      await ctx.store.saveResult(
        id: 'scale-saved',
        kind: SavedSearchKind.query,
        query: 'who won?',
        result: result,
      );
      await ctx.store.appendMessage(
        searchId: 'scale-saved',
        messageId: 'm-user',
        role: 'user',
        text: 'SAVED-USER-SENTINEL follow-up question please',
      );
      await ctx.store.appendMessage(
        searchId: 'scale-saved',
        messageId: 'm-ai',
        role: 'assistant',
        text: 'SAVED-AI-SENTINEL follow-up answer here',
        model: 'gemini-2.5-flash',
      );

      await _pumpSaved(
        tester,
        store: ctx.store,
        db: ctx.db,
        entryId: 'scale-saved',
      );
      await tester.pumpAndSettle();

      expect(find.byKey(kSearchAnswerTextSizeBarKey), findsOneWidget);
      expect(find.text('ORIGINAL RESULT'), findsOneWidget);
      expect(find.textContaining('SAVED-SNAPSHOT-SENTINEL'), findsOneWidget);
      expect(find.textContaining('SAVED-USER-SENTINEL'), findsOneWidget);
      expect(find.textContaining('SAVED-AI-SENTINEL'), findsOneWidget);

      await tester.tap(find.byKey(kSearchAnswerTextIncreaseKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));

      expect(
        _scalerOf(tester, find.textContaining('SAVED-SNAPSHOT-SENTINEL')),
        closeTo(1.15, 0.01),
      );
      expect(
        _scalerOf(tester, find.textContaining('SAVED-AI-SENTINEL')),
        closeTo(1.15, 0.01),
      );
      expect(
        _scalerOf(tester, find.textContaining('SAVED-USER-SENTINEL')),
        closeTo(1.0, 0.01),
      );
      expect(
        _scalerOf(tester, find.text('ORIGINAL RESULT')),
        closeTo(1.0, 0.01),
      );
      expect(tester.takeException(), isNull);
      await _dismount(tester);
    });

    testWidgets('image-analysis snapshot scales the answer not the chrome',
        (tester) async {
      final ctx = await _savedBootstrap();
      await ctx.store.saveResult(
        id: 'img-scale',
        kind: SavedSearchKind.image,
        query: 'what is this?',
        result: const ImageGroundedResult(
          response: GroundedSearchResponse(
            answer: 'IMAGE-ANSWER-SENTINEL a cat sitting on a mat.',
            query: 'what is this?',
            model: 'gemini-2.5-flash',
            searchQueries: [],
            sources: [],
            citations: [],
          ),
          thumbDataUrl: '',
          originalMediaType: 'image/jpeg',
          question: 'what is this?',
        ),
      );

      await _pumpSaved(
        tester,
        store: ctx.store,
        db: ctx.db,
        entryId: 'img-scale',
      );
      await tester.pumpAndSettle();

      expect(find.text('IMAGE ANALYSIS'), findsOneWidget);
      expect(find.textContaining('IMAGE-ANSWER-SENTINEL'), findsOneWidget);

      await tester.tap(find.byKey(kSearchAnswerTextIncreaseKey));
      await tester.pump();

      expect(
        _scalerOf(tester, find.textContaining('IMAGE-ANSWER-SENTINEL')),
        closeTo(1.15, 0.01),
      );
      expect(_scalerOf(tester, find.text('IMAGE ANALYSIS')), closeTo(1.0, 0.01));
      expect(tester.takeException(), isNull);
      await _dismount(tester);
    });
  });

  group('SearchFollowUp sheet', () {
    testWidgets('header A−/A+ scales assistant markdown, not user or Ask AI',
        (tester) async {
      const query = 'follow-up scale query';
      SearchFollowUpStore.instance.debugSeedTranscript(
        query,
        turns: const [
          (
            id: 'u1',
            role: 'user',
            text: 'FOLLOWUP-USER-SENTINEL please explain more',
          ),
          (
            id: 'a1',
            role: 'assistant',
            text: 'FOLLOWUP-AI-SENTINEL here is a longer grounded reply.',
          ),
        ],
      );

      final settings = await _settings();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsProvider.overrideWith((ref) => settings),
          ],
          child: MaterialApp(
            theme: _theme(),
            home: const Scaffold(
              body: Center(
                child: SearchFollowUpFab(
                  query: query,
                  initialAnswer: 'original grounded answer',
                  model: 'gemini-2.5-flash',
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byType(SearchFollowUpFab));
      await _drain(tester);

      expect(find.text('Ask AI'), findsOneWidget);
      expect(find.byKey(kSearchAnswerTextSizeBarKey), findsOneWidget);
      expect(find.textContaining('FOLLOWUP-USER-SENTINEL'), findsOneWidget);
      expect(find.textContaining('FOLLOWUP-AI-SENTINEL'), findsOneWidget);

      await tester.tap(find.byKey(kSearchAnswerTextIncreaseKey));
      await tester.pump();

      expect(
        _scalerOf(tester, find.textContaining('FOLLOWUP-AI-SENTINEL')),
        closeTo(1.15, 0.01),
      );
      expect(
        _scalerOf(tester, find.textContaining('FOLLOWUP-USER-SENTINEL')),
        closeTo(1.0, 0.01),
      );
      expect(_scalerOf(tester, find.text('Ask AI')), closeTo(1.0, 0.01));
      expect(tester.takeException(), isNull);
      await _dismount(tester);
    });
  });

  group('shared preference with news reader', () {
    testWidgets('search A+ is the size the news reader opens at',
        (tester) async {
      await _pumpLookup(tester, tavily: _tavily());
      await tester.tap(find.byKey(kSearchAnswerTextIncreaseKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble(kNewsReaderTextScalePrefKey), 1.15);
      await _dismount(tester);

      const title = 'Readable article title for the news reader';
      await tester.pumpWidget(
        ProviderScope(
          child: MediaQuery(
            data: const MediaQueryData(size: Size(390, 844)),
            child: MaterialApp(
              theme: _theme(),
              home: ArticleDetailModal(
                article: Article(
                  id: 'scale-from-search',
                  title: title,
                  excerpt: 'UNIQUE-EXCERPT-SENTINEL',
                  source: 'Test Source',
                  category: 'Movies',
                  imageUrl: '',
                  readTime: 5,
                  date: 'Aug 20, 2026',
                  blocks: const [],
                  summaryMarkdown:
                      'The monsoon arrived overnight and the streets filled.',
                  originalUrl: 'https://example.com/article',
                  isFullContent: true,
                ),
                onToggleSave: (_) {},
                onMarkRead: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));

      expect(
        _scalerOf(tester, find.text(title)),
        closeTo(1.15, 0.01),
      );
      await _dismount(tester);
    });
  });
}
