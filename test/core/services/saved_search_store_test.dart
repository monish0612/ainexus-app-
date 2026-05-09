// Unit tests for SavedSearchStore.
//
// Focus areas:
//   • saveResult — Drift insert + idempotency on duplicate ids.
//   • delete / undelete — soft-delete tombstone semantics.
//   • appendMessage / loadMessages — chat persistence + parent updatedAt bump.
//   • debugRunGc — orphaned chat cleanup; stale soft-delete hard-delete.
//
// These tests deliberately exercise the local Drift paths only; remote
// network calls are fire-and-forget in the production code so the local
// state machine is testable in isolation. A fake [ApiClient] is supplied
// via `init` (passed as null) so the store skips its server calls without
// throwing.

import 'package:ai_nexus/core/services/saved_search_store.dart';
import 'package:ai_nexus/data/local/database/app_database.dart';
import 'package:ai_nexus/domain/entities/saved_search.dart';
import 'package:ai_nexus/domain/entities/tutor_entities.dart';
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SavedSearchStore', () {
    late AppDatabase db;
    late SavedSearchStore store;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      store = SavedSearchStore.instance;
      store.debugResetForTests();
      // null ApiClient keeps the store off the network — local Drift only.
      store.init(db, null);
    });

    tearDown(() async {
      store.debugResetForTests();
      await db.close();
    });

    test('saveResult inserts a row that can be read back', () async {
      const result = SummarizerResult(
        title: 'Hello',
        summary: 'A short summary',
        keyPoints: ['one', 'two'],
        category: 'tech',
        readTime: 2,
        source: 'example.com',
        extractionMethod: 'grounding',
        url: 'https://example.com/article',
        model: 'gemini-2.5-flash',
      );

      final entry = await store.saveResult(
        kind: SavedSearchKind.url,
        query: 'https://example.com/article',
        result: result,
      );

      expect(entry.id, isNotEmpty);
      expect(entry.responseType, equals(SavedSearchResponseType.summarizer));
      expect(entry.kind, equals(SavedSearchKind.url));
      expect(entry.title, contains('example.com'));

      final all = await store.listAll();
      expect(all, hasLength(1));
      expect(all.first.id, equals(entry.id));

      final decoded = all.first.decodedResult();
      expect(decoded, isA<SummarizerResult>());
      expect((decoded as SummarizerResult).summary, equals('A short summary'));
      expect(decoded.keyPoints, equals(<String>['one', 'two']));
    });

    test('isSaved returns true after save and false after delete', () async {
      const result = TavilySearchResponse(
        answer: 'answer',
        query: 'q',
        results: [],
      );

      final entry = await store.saveResult(
        kind: SavedSearchKind.query,
        query: 'q',
        result: result,
      );
      expect(await store.isSaved(entry.id), isTrue);

      await store.delete(entry.id);
      expect(await store.isSaved(entry.id), isFalse,
          reason: 'soft-deleted rows should report as not saved');
    });

    test('undelete restores a soft-deleted row', () async {
      const result = TavilySearchResponse(
        answer: 'answer',
        query: 'q',
        results: [],
      );

      final entry = await store.saveResult(
        kind: SavedSearchKind.query,
        query: 'q',
        result: result,
      );
      await store.delete(entry.id);
      expect(await store.isSaved(entry.id), isFalse);

      await store.undelete(entry.id);
      expect(await store.isSaved(entry.id), isTrue);
    });

    test('saveResult with a fixed id is idempotent', () async {
      const result = TavilySearchResponse(
        answer: 'answer',
        query: 'q',
        results: [],
      );

      final a = await store.saveResult(
        id: 'fixed-id',
        kind: SavedSearchKind.query,
        query: 'q',
        result: result,
      );
      final b = await store.saveResult(
        id: 'fixed-id',
        kind: SavedSearchKind.query,
        query: 'q (updated)',
        result: result,
      );

      expect(a.id, equals(b.id));
      final all = await store.listAll();
      expect(all, hasLength(1),
          reason: 'second save with same id should upsert, not duplicate');
      expect(all.single.query, equals('q (updated)'));
    });

    test('appendMessage persists messages and bumps parent updatedAt',
        () async {
      const result = TavilySearchResponse(
        answer: 'answer',
        query: 'q',
        results: [],
      );

      final entry = await store.saveResult(
        kind: SavedSearchKind.query,
        query: 'q',
        result: result,
      );
      final originalUpdatedAt = entry.updatedAt;
      // Wait one ms so the bump is detectable on fast machines.
      await Future<void>.delayed(const Duration(milliseconds: 5));

      await store.appendMessage(
        searchId: entry.id,
        messageId: 'm1',
        role: 'user',
        text: 'hello',
      );
      await store.appendMessage(
        searchId: entry.id,
        messageId: 'm2',
        role: 'assistant',
        text: 'hi back',
        model: 'gemini',
      );

      final msgs = await store.loadMessages(entry.id);
      expect(msgs, hasLength(2));
      expect(msgs[0].role, equals('user'));
      expect(msgs[0].text, equals('hello'));
      expect(msgs[1].role, equals('assistant'));
      expect(msgs[1].model, equals('gemini'));

      final fresh = await store.getById(entry.id);
      expect(fresh, isNotNull);
      expect(fresh!.updatedAt.compareTo(originalUpdatedAt), greaterThan(0),
          reason: 'updatedAt should advance whenever a chat turn lands');
    });

    test('debugRunGc prunes chat messages with no parent saved-search',
        () async {
      // Insert a chat message with a fabricated searchId that was never saved.
      final oldTs =
          DateTime.now().toUtc().subtract(const Duration(hours: 5)).toIso8601String();
      await db.into(db.savedSearchChatMessages).insert(
            SavedSearchChatMessagesCompanion.insert(
              id: 'orphan-msg',
              searchId: 'never-existed',
              role: 'user',
              msgText: 'leftover',
              createdAt: oldTs,
            ),
          );
      // And a recent one — should NOT be removed since it's within the TTL.
      final freshTs = DateTime.now().toUtc().toIso8601String();
      await db.into(db.savedSearchChatMessages).insert(
            SavedSearchChatMessagesCompanion.insert(
              id: 'fresh-msg',
              searchId: 'never-existed',
              role: 'user',
              msgText: 'new',
              createdAt: freshTs,
            ),
          );

      await store.debugRunGc();

      final remaining =
          await db.select(db.savedSearchChatMessages).get();
      expect(remaining.map((r) => r.id), contains('fresh-msg'));
      expect(remaining.map((r) => r.id), isNot(contains('orphan-msg')),
          reason: 'orphan messages older than the TTL should be GCed');
    });

    test('debugRunGc hard-deletes soft-deleted rows older than 7 days',
        () async {
      final staleTs = DateTime.now()
          .toUtc()
          .subtract(const Duration(days: 8))
          .toIso8601String();
      await db.into(db.savedSearches).insert(
            SavedSearchesCompanion.insert(
              id: 'old-stub',
              kind: SavedSearchKind.query,
              query: 'q',
              title: 't',
              responseType: SavedSearchResponseType.tavily,
              responseJson: '{}',
              savedAt: staleTs,
              updatedAt: staleTs,
              deletedAt: drift.Value(staleTs),
            ),
          );

      await store.debugRunGc();

      final left = await db.select(db.savedSearches).get();
      expect(left.where((r) => r.id == 'old-stub'), isEmpty,
          reason: 'a soft-deleted row older than 7 days should be hard-deleted');
    });
  });
}
