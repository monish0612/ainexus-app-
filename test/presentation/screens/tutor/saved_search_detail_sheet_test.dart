// Widget tests for SavedSearchDetailSheet — missing-entry, snapshot
// rendering, persistent chat history, and clean dispose without leaked
// timers or late setStates.
//
// We rely on:
//   • An in-memory Drift database via [AppDatabase.forTesting].
//   • A SavedSearchStore wired with `init(db, null)` so server pulls are
//     no-ops and we never spin up the periodic GC timer (which would
//     trip the test framework's pending-timer guard).
//   • A `ProviderScope` override that injects the test store into
//     [savedSearchStoreProvider] — TutorAiService is never invoked because
//     the assertions don't hit `_send`, so we don't need to fake Dio.

import 'package:ai_nexus/core/di/injection.dart';
import 'package:ai_nexus/core/services/saved_search_store.dart';
import 'package:ai_nexus/core/theme/app_colors.dart';
import 'package:ai_nexus/data/local/database/app_database.dart';
import 'package:ai_nexus/domain/entities/saved_search.dart';
import 'package:ai_nexus/domain/entities/tutor_entities.dart';
import 'package:ai_nexus/presentation/screens/tutor/saved_search_detail_sheet.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
// Note: settingsProvider is intentionally NOT overridden — the
// SavedSearchDetailSheet reads it defensively (try/catch with a
// const SettingsState() fallback) so widget tests can mount it
// without wiring SharedPreferences + UserPreferencesService.

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

/// Bootstraps an in-memory store + db. The widget is intentionally NOT
/// mounted here — callers should seed any required Drift rows first
/// (because `_loadEntry` only fires once in `initState`) and then call
/// [_mount] explicitly. This avoids subtle timing races.
Future<({SavedSearchStore store, AppDatabase db})> _bootstrap() async {
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

/// Mounts the SavedSearchDetailSheet with the provided overrides.
Future<void> _mount(
  WidgetTester tester, {
  required SavedSearchStore store,
  required AppDatabase db,
  required String entryId,
}) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        savedSearchStoreProvider.overrideWithValue(store),
        appDatabaseProvider.overrideWithValue(db),
      ],
      child: MaterialApp(
        theme: _testTheme(),
        home: Scaffold(body: SavedSearchDetailSheet(entryId: entryId)),
      ),
    ),
  );
}

Future<void> _drain(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SavedSearchDetailSheet', () {
    testWidgets('renders the missing-state when the entry id is unknown',
        (tester) async {
      final ctx = await _bootstrap();
      await _mount(tester,
          store: ctx.store, db: ctx.db, entryId: 'does-not-exist');
      await tester.pumpAndSettle();

      expect(find.textContaining('no longer available'), findsOneWidget);
      await _drain(tester);
    });

    testWidgets('renders the snapshot title + delete button for a saved entry',
        (tester) async {
      const result = SummarizerResult(
        title: 'My great article',
        summary: 'This is the body of the summary.',
        keyPoints: ['point one', 'point two'],
        category: 'tech',
        readTime: 3,
        source: 'blog.example.com',
        extractionMethod: 'grounding',
        url: 'https://blog.example.com/post',
        model: 'gemini-2.5-flash',
      );
      final ctx = await _bootstrap();
      // Seed BEFORE mounting so _loadEntry (initState) sees the row.
      await ctx.store.saveResult(
        id: 'fixture-id',
        kind: SavedSearchKind.url,
        query: 'https://blog.example.com/post',
        result: result,
      );
      await _mount(tester,
          store: ctx.store, db: ctx.db, entryId: 'fixture-id');
      await tester.pumpAndSettle();

      expect(find.text('ORIGINAL RESULT'), findsOneWidget);
      expect(find.text('FOLLOW-UP CHAT'), findsOneWidget);
      // Delete + Close icon buttons exist.
      expect(find.byTooltip('Delete'), findsOneWidget);
      expect(find.byTooltip('Close'), findsOneWidget);
      await _drain(tester);
    });

    testWidgets('renders previously-persisted chat messages from Drift',
        (tester) async {
      const result = TavilySearchResponse(
        answer: 'initial answer',
        query: 'q',
        results: <TavilyResultItem>[],
      );
      final ctx = await _bootstrap();
      await ctx.store.saveResult(
        id: 'with-chat',
        kind: SavedSearchKind.query,
        query: 'who won?',
        result: result,
      );
      await ctx.store.appendMessage(
        searchId: 'with-chat',
        messageId: 'm-user',
        role: 'user',
        text: 'follow-up question please',
      );
      await ctx.store.appendMessage(
        searchId: 'with-chat',
        messageId: 'm-ai',
        role: 'assistant',
        text: 'follow-up answer here',
        model: 'gemini-2.5-flash',
      );
      await _mount(tester,
          store: ctx.store, db: ctx.db, entryId: 'with-chat');
      await tester.pumpAndSettle();

      expect(find.textContaining('follow-up question please'),
          findsAtLeastNWidgets(1));
      expect(find.textContaining('follow-up answer here'),
          findsAtLeastNWidgets(1));
      await _drain(tester);
    });

    testWidgets(
        'sheet survives an immediate dismount without leaking timers '
        '(open → close → reopen)', (tester) async {
      const result = TavilySearchResponse(
        answer: 'a', query: 'q', results: <TavilyResultItem>[]);
      final ctx = await _bootstrap();
      await ctx.store.saveResult(
        id: 'cycle-id',
        kind: SavedSearchKind.query,
        query: 'q',
        result: result,
      );
      await _mount(tester,
          store: ctx.store, db: ctx.db, entryId: 'cycle-id');
      await tester.pumpAndSettle();
      expect(find.text('ORIGINAL RESULT'), findsOneWidget);

      // Dismount the sheet by replacing the host with an empty box, then
      // remount it again — verifies the store streams reattach cleanly
      // and there are no late setStates from the prior instance.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 50));

      await _mount(tester,
          store: ctx.store, db: ctx.db, entryId: 'cycle-id');
      await tester.pumpAndSettle();
      expect(find.text('ORIGINAL RESULT'), findsOneWidget,
          reason: 'second mount must rehydrate the saved entry');
      await _drain(tester);
    });
  });
}
