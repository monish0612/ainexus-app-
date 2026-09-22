// Deep edge-case coverage for InsightAI share + whole-document selection.
// Share must open the OS chooser (mocked here), never the clipboard.
// Save, Copy, and the follow-up FAB must keep working beside it.

import 'dart:async';

import 'package:ai_nexus/core/di/injection.dart';
import 'package:ai_nexus/core/services/saved_search_store.dart';
import 'package:ai_nexus/core/theme/app_colors.dart';
import 'package:ai_nexus/data/local/database/app_database.dart';
import 'package:ai_nexus/domain/entities/saved_search.dart';
import 'package:ai_nexus/domain/entities/tutor_entities.dart';
import 'package:ai_nexus/presentation/screens/tutor/saved_search_detail_sheet.dart';
import 'package:ai_nexus/presentation/screens/tutor/search_followup_sheet.dart';
import 'package:ai_nexus/presentation/screens/tutor/search_lookup_screen.dart';
import 'package:ai_nexus/presentation/widgets/search_result_actions.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

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
          modeLite: Color(0xFF22D3EE),
          modeDeep: Color(0xFF8B5CF6),
          modeThinking: Color(0xFFF5B62C),
          providerXgrok: Color(0xFF94A3B8),
          accentText: Color(0xFF5B8CFF),
          danger: Color(0xFFEF4444),
          warning: Color(0xFFF59E0B),
          success: Color(0xFF34D399),
          isDark: true,
        ),
      ],
    );

AppColors get _colors => _theme().extension<AppColors>()!;

const _kShareChannel = MethodChannel('app.ainexus.ai_nexus/share');

GroundedSearchResponse _grounded({
  String answer = 'LOOKUP-SHARE-SENTINEL monsoon streets.',
  String query = 'monsoon chennai',
}) =>
    GroundedSearchResponse(
      answer: answer,
      query: query,
      model: 'gemini-2.5-flash',
      searchQueries: const ['monsoon chennai'],
      sources: const [
        GroundedSource(
          index: 1,
          title: 'BBC Weather',
          url: 'https://example.com/bbc-weather',
        ),
      ],
      citations: const [],
    );

TavilySearchResponse _tavily() => const TavilySearchResponse(
      answer: 'TAVILY-SHARE-SENTINEL tomatoes and wet earth.',
      query: 'monsoon chennai',
      results: [
        TavilyResultItem(
          title: 'Tavily Source',
          url: 'https://example.com/tavily',
          content: 'snippet',
          score: 0.9,
        ),
      ],
    );

List<MethodCall> _mockShareChannel({Future<bool> Function()? pending}) {
  final calls = <MethodCall>[];
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_kShareChannel, (call) async {
    calls.add(call);
    if (pending != null) return pending();
    return true;
  });
  addTearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_kShareChannel, null);
  });
  return calls;
}

Future<void> _pumpLookup(
  WidgetTester tester, {
  GroundedSearchResponse? grounded,
  TavilySearchResponse? tavily,
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    ProviderScope(
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

Future<void> _dismount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 80));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  tearDown(() {
    SearchFollowUpStore.instance.debugResetForTests();
  });

  group('SearchShareSaveCluster', () {
    testWidgets('share and save fire independently on a 320px row',
        (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      var shares = 0;
      var saves = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: _theme(),
          home: Scaffold(
            body: Row(
              children: [
                const Expanded(child: Text('Google · Gemini')),
                SearchShareSaveCluster(
                  colors: _colors,
                  onShare: () => shares++,
                  saveButton: IconButton(
                    tooltip: 'Save to history',
                    onPressed: () => saves++,
                    icon: const Icon(Icons.bookmark_outline_rounded),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(kSearchResultShareKey));
      await tester.tap(find.byTooltip('Save to history'));
      expect(shares, 1);
      expect(saves, 1);

      await tester.pumpWidget(
        MaterialApp(
          theme: _theme(),
          home: Scaffold(
            body: SearchShareSaveCluster(
              colors: _colors,
              onShare: null,
              saveButton: IconButton(
                tooltip: 'Save to history',
                onPressed: () => saves++,
                icon: const Icon(Icons.bookmark_outline_rounded),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(kSearchResultShareKey));
      expect(shares, 1, reason: 'Disabled share must not fire.');
      await tester.tap(find.byTooltip('Save to history'));
      expect(saves, 2, reason: 'Save must still work while share is disabled.');
    });

    testWidgets('AMOLED dark glass is a violet wash, not a white blob',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            extensions: const <ThemeExtension<dynamic>>[AppColors.dark],
          ),
          home: Scaffold(
            backgroundColor: Colors.black,
            body: SearchShareSaveCluster(
              colors: AppColors.dark,
              onShare: () {},
              saveButton: IconButton(
                tooltip: 'Save to history',
                onPressed: () {},
                icon: const Icon(Icons.bookmark_outline_rounded),
              ),
            ),
          ),
        ),
      );

      final deco = tester.widget<DecoratedBox>(
        find.descendant(
          of: find.byKey(kSearchResultShareSaveClusterKey),
          matching: find.byType(DecoratedBox),
        ),
      );
      final box = deco.decoration as BoxDecoration;
      expect(box.color, isNotNull);
      expect(box.color!.a, lessThan(0.35),
          reason: 'Fill must stay translucent on AMOLED.');
      expect(box.color!.computeLuminance(), lessThan(0.45),
          reason: 'Must not read as a white pill on black.');
      expect(box.border, isNotNull);
    });

    testWidgets('white theme glass stays a lilac chip, not muddy gray',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            extensions: const <ThemeExtension<dynamic>>[AppColors.white],
          ),
          home: Scaffold(
            backgroundColor: Colors.white,
            body: SearchShareSaveCluster(
              colors: AppColors.white,
              onShare: () {},
              saveButton: IconButton(
                tooltip: 'Save to history',
                onPressed: () {},
                icon: const Icon(Icons.bookmark_outline_rounded),
              ),
            ),
          ),
        ),
      );

      final deco = tester.widget<DecoratedBox>(
        find.descendant(
          of: find.byKey(kSearchResultShareSaveClusterKey),
          matching: find.byType(DecoratedBox),
        ),
      );
      final box = deco.decoration as BoxDecoration;
      expect(box.color, isNotNull);
      expect(box.color!.a, inInclusiveRange(0.06, 0.22));
      expect(box.border, isNotNull);
      expect(tester.takeException(), isNull);
    });
  });

  group('SearchLookupScreen share + selection', () {
    testWidgets(
        'share sends header+answer+follow-up, copy still works, FAB stays',
        (tester) async {
      final calls = _mockShareChannel();
      SearchFollowUpStore.instance.debugSeedTranscript(
        'monsoon chennai',
        turns: const [
          (id: 'u1', role: 'user', text: 'How many mm of rain?'),
          (id: 'a1', role: 'assistant', text: 'About forty two millimetres.'),
        ],
      );
      await _pumpLookup(tester, grounded: _grounded());

      expect(find.byKey(kSearchResultShareKey), findsOneWidget);
      expect(find.text('Copy'), findsOneWidget);
      expect(find.byType(SearchFollowUpFab), findsOneWidget);
      expect(find.byType(SelectionArea), findsWidgets);
      expect(find.byType(EditableText), findsNothing);
      final bodies = tester.widgetList<MarkdownBody>(find.byType(MarkdownBody));
      expect(bodies, isNotEmpty);
      expect(bodies.every((b) => !b.selectable), isTrue);
      expect(
        find.descendant(
          of: find.byType(SelectionArea).first,
          matching: find.textContaining('LOOKUP-SHARE-SENTINEL'),
        ),
        findsWidgets,
      );

      await tester.tap(find.byKey(kSearchResultShareKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(calls, hasLength(1));
      expect(calls.single.method, 'shareText');
      final args = calls.single.arguments as Map;
      final payload = args['text'] as String;
      expect(payload, contains('Nexus AI · Search'));
      expect(payload, contains('monsoon chennai'));
      expect(payload, contains('LOOKUP-SHARE-SENTINEL'));
      expect(payload, contains('────────  Follow-up  ────────'));
      expect(payload, contains('How many mm of rain?'));
      expect(payload, contains('About forty two millimetres.'));
      expect(payload, contains('— Shared from Nexus AI'));
      expect(args['subject'], 'monsoon chennai');
      expect(find.text('Could not open share'), findsNothing);
      expect(find.text('Copy'), findsOneWidget);
      expect(tester.getRect(find.text('Copy')).width, greaterThan(0));
      expect(find.byType(SearchFollowUpFab), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _dismount(tester);
    });

    testWidgets('share without follow-up omits the Q&A block', (tester) async {
      final calls = _mockShareChannel();
      await _pumpLookup(tester, grounded: _grounded());
      await tester.tap(find.byKey(kSearchResultShareKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      final payload =
          (calls.single.arguments as Map)['text'] as String;
      expect(payload, contains('LOOKUP-SHARE-SENTINEL'));
      expect(payload.contains('Follow-up'), isFalse);
      expect(find.byType(SearchFollowUpFab), findsOneWidget);
      await _dismount(tester);
    });

    testWidgets('in-flight share disables the button so a second tap is a no-op',
        (tester) async {
      final gate = Completer<bool>();
      final calls = _mockShareChannel(pending: () => gate.future);
      await _pumpLookup(tester, grounded: _grounded());

      await tester.tap(find.byKey(kSearchResultShareKey));
      await tester.pump();
      final during = tester.widget<IconButton>(find.byKey(kSearchResultShareKey));
      expect(during.onPressed, isNull);

      await tester.tap(find.byKey(kSearchResultShareKey));
      await tester.pump();
      expect(calls, hasLength(1));

      gate.complete(true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      final after = tester.widget<IconButton>(find.byKey(kSearchResultShareKey));
      expect(after.onPressed, isNotNull);
      await _dismount(tester);
    });

    testWidgets('Tavily share + selection on a 320px phone does not overflow',
        (tester) async {
      final calls = _mockShareChannel();
      await _pumpLookup(
        tester,
        tavily: _tavily(),
        size: const Size(320, 1400),
      );
      expect(tester.takeException(), isNull);
      expect(find.byKey(kSearchResultShareKey), findsOneWidget);
      expect(find.text('Copy'), findsOneWidget);
      expect(find.byType(EditableText), findsNothing);
      await tester.tap(find.byKey(kSearchResultShareKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      final payload =
          (calls.single.arguments as Map)['text'] as String;
      expect(payload, contains('Nexus AI · Search'));
      expect(payload, contains('TAVILY-SHARE-SENTINEL'));
      expect(payload, contains('Tavily'));
      expect(tester.takeException(), isNull);
      await _dismount(tester);
    });
  });

  group('SavedSearchDetailSheet share', () {
    testWidgets(
        'share includes the snapshot and persisted Q&A; delete/close remain',
        (tester) async {
      final calls = _mockShareChannel();
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final store = SavedSearchStore.instance
        ..debugResetForTests()
        ..init(db, null);
      addTearDown(() async {
        store.debugResetForTests();
        await db.close();
      });

      await store.saveResult(
        id: 'share-saved',
        kind: SavedSearchKind.query,
        query: 'who won?',
        result: const TavilySearchResponse(
          answer: 'SAVED-ANSWER-SENTINEL the home side.',
          query: 'who won?',
          results: [],
        ),
      );
      await store.appendMessage(
        searchId: 'share-saved',
        messageId: 'm-user',
        role: 'user',
        text: 'By how many runs?',
      );
      await store.appendMessage(
        searchId: 'share-saved',
        messageId: 'm-ai',
        role: 'assistant',
        text: 'Forty two runs.',
      );

      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            savedSearchStoreProvider.overrideWithValue(store),
            appDatabaseProvider.overrideWithValue(db),
          ],
          child: MaterialApp(
            theme: _theme(),
            home: const Scaffold(
              body: SavedSearchDetailSheet(entryId: 'share-saved'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byTooltip('Share'), findsOneWidget);
      expect(find.byTooltip('Delete'), findsOneWidget);
      expect(find.byTooltip('Close'), findsOneWidget);
      expect(find.text('FOLLOW-UP CHAT'), findsOneWidget);
      expect(find.textContaining('SAVED-ANSWER-SENTINEL'), findsWidgets);

      await tester.tap(find.byTooltip('Share'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));

      expect(calls, hasLength(1));
      final payload =
          (calls.single.arguments as Map)['text'] as String;
      expect(payload, contains('Nexus AI · Search'));
      expect(payload, contains('who won?'));
      expect(payload, contains('SAVED-ANSWER-SENTINEL'));
      expect(payload, contains('By how many runs?'));
      expect(payload, contains('Forty two runs.'));
      expect(find.byTooltip('Delete'), findsOneWidget);
      expect(find.text('Could not open share'), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 80));
    });
  });
}
