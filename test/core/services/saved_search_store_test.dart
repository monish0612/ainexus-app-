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

    // ── Draft lifecycle ────────────────────────────────────────────────────
    //
    // The "draft" concept is the cornerstone of the Saved Searches UX. A
    // search result is persisted in Drift the moment it lands on screen,
    // BEFORE the user explicitly bookmarks it, so all follow-up chat
    // messages can be keyed under a stable id from message #1. The tests
    // below cover the full state machine + the contracts the UI relies on.

    test('startDraft inserts a hidden row that watchAll/listAll exclude',
        () async {
      const result = TavilySearchResponse(
        answer: 'answer',
        query: 'q',
        results: [],
      );

      final draft = await store.startDraft(
        kind: SavedSearchKind.query,
        query: 'q',
        result: result,
      );

      expect(draft.id, isNotEmpty);
      // listAll / watchAll filter to pinned=true → drafts must NOT appear.
      expect(await store.listAll(), isEmpty,
          reason: 'drafts should be hidden from the History sheet');
      // The row IS in Drift (so chat messages can attach to it).
      final row = await (db.select(db.savedSearches)
            ..where((t) => t.id.equals(draft.id))
            ..limit(1))
          .getSingleOrNull();
      expect(row, isNotNull);
      expect(row!.pinned, isFalse,
          reason: 'a draft must be pinned=false so promoteToSaved is meaningful');
    });

    test('isSaved returns false for a draft, true after promoteToSaved',
        () async {
      const result = TavilySearchResponse(
        answer: 'answer',
        query: 'q',
        results: [],
      );

      final draft = await store.startDraft(
        kind: SavedSearchKind.query,
        query: 'q',
        result: result,
      );
      expect(await store.isSaved(draft.id), isFalse,
          reason: 'isSaved must be false for a draft so the bookmark icon '
              'renders the outlined (unsaved) state');

      final promoted = await store.promoteToSaved(draft.id);
      expect(promoted, isTrue, reason: 'first promote must return true');
      expect(await store.isSaved(draft.id), isTrue);

      // Once promoted, the entry IS visible in the History list.
      final all = await store.listAll();
      expect(all, hasLength(1));
      expect(all.first.id, equals(draft.id));
    });

    test('promoteToSaved is idempotent — second call returns false', () async {
      const result = TavilySearchResponse(
        answer: 'answer',
        query: 'q',
        results: [],
      );
      final draft = await store.startDraft(
        kind: SavedSearchKind.query,
        query: 'q',
        result: result,
      );
      expect(await store.promoteToSaved(draft.id), isTrue);
      expect(await store.promoteToSaved(draft.id), isFalse,
          reason: 'second promote on an already-saved row is a no-op');
    });

    test('discardDraftIfAny hard-deletes draft rows + cascades chat messages',
        () async {
      const result = TavilySearchResponse(
        answer: 'answer',
        query: 'q',
        results: [],
      );
      final draft = await store.startDraft(
        kind: SavedSearchKind.query,
        query: 'q',
        result: result,
      );
      // Mirror a couple of chat turns under the draft so we can verify the
      // cascade-delete of [SavedSearchChatMessages] in the same call.
      await store.appendMessage(
        searchId: draft.id,
        messageId: 'm1',
        role: 'user',
        text: 'hello',
      );
      await store.appendMessage(
        searchId: draft.id,
        messageId: 'm2',
        role: 'assistant',
        text: 'world',
      );

      final discarded = await store.discardDraftIfAny(draft.id);
      expect(discarded, isTrue);

      // Parent row gone.
      final row = await (db.select(db.savedSearches)
            ..where((t) => t.id.equals(draft.id))
            ..limit(1))
          .getSingleOrNull();
      expect(row, isNull);

      // Chat messages must also be gone — leaving them would be an orphan
      // leak (the GC would reap them eventually but clearing should be
      // immediate).
      final msgs = await (db.select(db.savedSearchChatMessages)
            ..where((t) => t.searchId.equals(draft.id)))
          .get();
      expect(msgs, isEmpty,
          reason: 'discardDraftIfAny must cascade-delete child chat messages');
    });

    test('discardDraftIfAny is a NO-OP on a saved (pinned=true) row',
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

      final discarded = await store.discardDraftIfAny(entry.id);
      expect(discarded, isFalse,
          reason: 'a user-saved row must never be hard-deleted by discardDraft');

      // Row is still there.
      expect(await store.isSaved(entry.id), isTrue);
    });

    test(
        'appendMessage works on a draft so follow-ups persist before bookmark',
        () async {
      const result = TavilySearchResponse(
        answer: 'answer',
        query: 'q',
        results: [],
      );

      final draft = await store.startDraft(
        kind: SavedSearchKind.query,
        query: 'q',
        result: result,
      );
      await store.appendMessage(
        searchId: draft.id,
        messageId: 'm1',
        role: 'user',
        text: 'hello',
      );
      await store.appendMessage(
        searchId: draft.id,
        messageId: 'm2',
        role: 'assistant',
        text: 'world',
      );

      final loaded = await store.loadMessages(draft.id);
      expect(loaded, hasLength(2),
          reason: 'follow-ups asked BEFORE save must persist under the draft id');

      // After promote, the same messages must still be readable — the row's
      // id is stable across promote so chats stay attached.
      await store.promoteToSaved(draft.id);
      final afterPromote = await store.loadMessages(draft.id);
      expect(afterPromote, hasLength(2),
          reason: 'promote must not orphan or duplicate any chat history');
    });

    test('debugRunGc reaps abandoned drafts older than the draft TTL',
        () async {
      const result = TavilySearchResponse(
        answer: 'answer',
        query: 'q',
        results: [],
      );
      // Create a draft and back-date it past the 24-hour TTL by bypassing
      // the public API (it always stamps `now`). This simulates a draft
      // the user abandoned a day ago.
      final draft = await store.startDraft(
        kind: SavedSearchKind.query,
        query: 'q',
        result: result,
      );
      final stale = DateTime.now()
          .toUtc()
          .subtract(const Duration(hours: 25))
          .toIso8601String();
      await (db.update(db.savedSearches)
            ..where((t) => t.id.equals(draft.id)))
          .write(SavedSearchesCompanion(
        savedAt: drift.Value(stale),
        updatedAt: drift.Value(stale),
      ));
      // Mirror a chat turn so we also verify cascade.
      await store.appendMessage(
        searchId: draft.id,
        messageId: 'm-stale',
        role: 'user',
        text: 'old chatter',
        createdAt: stale,
      );

      // Sanity: before GC, both rows exist.
      expect(
          await (db.select(db.savedSearches)
                ..where((t) => t.id.equals(draft.id)))
              .get(),
          hasLength(1));

      await store.debugRunGc();

      // Row gone.
      expect(
          await (db.select(db.savedSearches)
                ..where((t) => t.id.equals(draft.id)))
              .get(),
          isEmpty,
          reason: 'abandoned drafts older than 24h must be hard-deleted');
      // Chats gone too — they would otherwise survive as orphans for an
      // additional hour before the orphan sweeper picked them up.
      expect(
          await (db.select(db.savedSearchChatMessages)
                ..where((t) => t.searchId.equals(draft.id)))
              .get(),
          isEmpty);
    });

    test('debugRunGc leaves recent drafts alone', () async {
      const result = TavilySearchResponse(
        answer: 'answer',
        query: 'q',
        results: [],
      );
      final draft = await store.startDraft(
        kind: SavedSearchKind.query,
        query: 'q',
        result: result,
      );

      await store.debugRunGc();

      final still = await (db.select(db.savedSearches)
            ..where((t) => t.id.equals(draft.id)))
          .get();
      expect(still, hasLength(1),
          reason: 'recent drafts (< 24h) must survive the GC sweeper');
    });
  });
}
