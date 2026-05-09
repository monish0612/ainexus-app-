// Widget tests for SavedSearchesSheet + SavedSearchDetailSheet.
//
// These tests rely on:
//   • An in-memory Drift database via [AppDatabase.forTesting].
//   • A SavedSearchStore wired with `init(db, null)` so server pushes are
//     silent no-ops while local Drift behaviour is exercised end to end.
//   • A `ProviderScope` override that injects the test store directly into
//     [savedSearchStoreProvider] — the API client provider is never read,
//     so we don't need to fake Dio.

import 'package:ai_nexus/core/di/injection.dart';
import 'package:ai_nexus/core/services/saved_search_store.dart';
import 'package:ai_nexus/core/theme/app_colors.dart';
import 'package:ai_nexus/data/local/database/app_database.dart';
import 'package:ai_nexus/domain/entities/saved_search.dart';
import 'package:ai_nexus/domain/entities/tutor_entities.dart';
import 'package:ai_nexus/presentation/screens/tutor/saved_searches_sheet.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _result = SummarizerResult(
  title: 'Hello world',
  summary: 'A short summary',
  keyPoints: ['k1', 'k2'],
  category: 'tech',
  readTime: 2,
  source: 'example.com',
  extractionMethod: 'grounding',
  url: 'https://example.com/article',
  model: 'gemini-2.5-flash',
);

ThemeData _testTheme() {
  return ThemeData(
    extensions: const <ThemeExtension<dynamic>>[
      AppColors(
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

/// Wraps [child] in a ProviderScope that overrides the saved-search store
/// to point at our test instance. Returns the live store reference so
/// individual tests can stage data via the public API.
///
/// Cleanup is registered via [addTearDown] so the in-memory database is
/// closed BEFORE the widget tree is dismantled — without this Drift's
/// stream-cleanup zero-duration timer trips the test framework's pending-
/// timer guard during widget disposal.
Future<({SavedSearchStore store, AppDatabase db})> _pumpSheet(
  WidgetTester tester, {
  required Widget child,
}) async {
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  final store = SavedSearchStore.instance
    ..debugResetForTests()
    ..init(db, null);

  addTearDown(() async {
    store.debugResetForTests();
    await db.close();
  });

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        savedSearchStoreProvider.overrideWithValue(store),
        appDatabaseProvider.overrideWithValue(db),
      ],
      child: MaterialApp(
        theme: _testTheme(),
        home: Scaffold(body: child),
      ),
    ),
  );
  return (store: store, db: db);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SavedSearchesSheet', () {
    tearDown(() {
      SavedSearchStore.instance.debugResetForTests();
    });

    testWidgets('shows empty state when no entries are saved', (tester) async {
      await _pumpSheet(tester, child: const SavedSearchesSheet());
      // First settle is for stream/initial frame.
      await tester.pumpAndSettle();

      expect(find.text('No saved searches yet'), findsOneWidget);

      // Dismount the providers/streams + drain Drift's cleanup timer before
      // the test framework's pending-timer guard runs.
      await _drain(tester);
    });

    testWidgets('renders a saved entry and the count badge', (tester) async {
      final ctx = await _pumpSheet(tester, child: const SavedSearchesSheet());
      await ctx.store.saveResult(
        kind: SavedSearchKind.url,
        query: 'https://example.com/article',
        result: _result,
      );
      // Allow the Drift stream + UI rebuild.
      await tester.pumpAndSettle();

      // Title rendered + count badge "1" present.
      expect(find.text('Saved searches'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.textContaining('example.com'), findsAtLeastNWidgets(1));
      await _drain(tester);
    });

    testWidgets('filter input narrows the list', (tester) async {
      final ctx = await _pumpSheet(tester, child: const SavedSearchesSheet());
      await ctx.store.saveResult(
        kind: SavedSearchKind.query,
        query: 'cricket scores',
        result: const TavilySearchResponse(
          answer: 'a',
          query: 'cricket scores',
          results: [],
        ),
      );
      await ctx.store.saveResult(
        kind: SavedSearchKind.query,
        query: 'baking sourdough',
        result: const TavilySearchResponse(
          answer: 'a',
          query: 'baking sourdough',
          results: [],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('cricket scores'), findsOneWidget);
      expect(find.text('baking sourdough'), findsOneWidget);

      await tester.enterText(
          find.byType(TextField), 'cricket');
      await tester.pumpAndSettle();

      expect(find.text('cricket scores'), findsOneWidget);
      expect(find.text('baking sourdough'), findsNothing);
      await _drain(tester);
    });
  });
}

/// Replaces the on-screen tree with an empty placeholder and waits for any
/// scheduled cleanup timers (notably Drift's StreamQueryStore zero-duration
/// timer) to drain. Required before the test framework's pending-timer
/// guard runs during widget tree disposal.
Future<void> _drain(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 100));
}
