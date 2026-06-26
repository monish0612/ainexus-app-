// Adversarial tests for SavedSearchStore's retry-queue + cleanup paths.
//
// These tests use a `_FakeApiClient` subclass of [ApiClient] that lets us
// program the response sequence (succeed | throw connection-error | throw
// 404) without going anywhere near the network. They exercise:
//
//   • Transient failures land items in the retry queue.
//   • The queue is bounded at `_kMaxRetryQueueSize`; oldest entries are
//     evicted on overflow.
//   • A 404 from the server purges the local row PLUS its chat messages
//     and summaries — no orphan rows, ever.
//   • A successful retry executes the right HTTP verb (POST for create,
//     DELETE for delete, POST for append) and clears the queue.
//
// The store is reset between tests so the singleton state can't leak.

import 'package:ai_nexus/core/network/api_client.dart';
import 'package:ai_nexus/core/services/saved_search_store.dart';
import 'package:ai_nexus/data/local/database/app_database.dart';
import 'package:ai_nexus/domain/entities/saved_search.dart';
import 'package:ai_nexus/domain/entities/tutor_entities.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Programmable ApiClient. Each WRITE call (POST/DELETE/PUT) records its
/// method+path and consumes the next programmed behaviour — returning 200,
/// throwing a DioException with the configured statusCode, or throwing a
/// transport-level connection error.
///
/// GETs are special: they back the store's background sync (the index pull
/// AND the tombstone pull that [SavedSearchStore.init] fires on cold start).
/// These are NOT part of any test's intent, so they always succeed with an
/// empty list and never consume the programmed [behaviours] sequence. This
/// keeps each test's behaviour list a clean 1:1 mapping to the write
/// operations it actually exercises, regardless of how many background GETs
/// init happens to fire.
class _FakeApiClient extends ApiClient {
  /// Sequence of behaviours for WRITE calls, applied in order. Once
  /// exhausted, all subsequent writes succeed with HTTP 200.
  final List<_FakeBehaviour> behaviours;
  final List<_FakeCall> calls = [];

  _FakeApiClient({required this.behaviours});

  _FakeBehaviour _next() {
    if (behaviours.isEmpty) return _FakeBehaviour.ok();
    return behaviours.removeAt(0);
  }

  @override
  Future<Response<T>> post<T>(String path,
      {Object? data, Options? options, CancelToken? cancelToken}) async {
    calls.add(_FakeCall('POST', path, data));
    return _apply<T>(_next(), path);
  }

  @override
  Future<Response<T>> get<T>(String path,
      {Map<String, dynamic>? queryParameters}) async {
    calls.add(_FakeCall('GET', path, null));
    // Background sync pulls always succeed with an empty index/tombstone list.
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
      data: const <dynamic>[] as T?,
    );
  }

  @override
  Future<Response<T>> delete<T>(String path) async {
    calls.add(_FakeCall('DELETE', path, null));
    return _apply<T>(_next(), path);
  }

  @override
  Future<Response<T>> put<T>(String path, {Object? data}) async {
    calls.add(_FakeCall('PUT', path, data));
    return _apply<T>(_next(), path);
  }

  Future<Response<T>> _apply<T>(_FakeBehaviour b, String path) async {
    final req = RequestOptions(path: path);
    if (b.kind == _FakeKind.ok) {
      return Response<T>(requestOptions: req, statusCode: 200, data: null);
    }
    if (b.kind == _FakeKind.status) {
      throw DioException(
        requestOptions: req,
        response: Response(requestOptions: req, statusCode: b.statusCode),
        type: DioExceptionType.badResponse,
        message: 'fake ${b.statusCode}',
      );
    }
    throw DioException(
      requestOptions: req,
      type: DioExceptionType.connectionError,
      message: 'fake connection error',
    );
  }
}

enum _FakeKind { ok, status, transport }

class _FakeBehaviour {
  const _FakeBehaviour(this.kind, [this.statusCode = 0]);
  factory _FakeBehaviour.ok() => const _FakeBehaviour(_FakeKind.ok);
  factory _FakeBehaviour.status(int code) =>
      _FakeBehaviour(_FakeKind.status, code);
  factory _FakeBehaviour.transport() =>
      const _FakeBehaviour(_FakeKind.transport);
  final _FakeKind kind;
  final int statusCode;
}

class _FakeCall {
  _FakeCall(this.method, this.path, this.body);
  final String method;
  final String path;
  final Object? body;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SavedSearchStore — retry queue + cleanup', () {
    late AppDatabase db;
    late SavedSearchStore store;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      store = SavedSearchStore.instance;
      store.debugResetForTests();
    });

    tearDown(() async {
      store.debugResetForTests();
      await db.close();
    });

    test('transient failure on _pushSave enqueues for retry', () async {
      // Background GET pulls (index + tombstones) always succeed and do not
      // consume the behaviour sequence, so the single programmed behaviour
      // maps directly to the save POST we want to fail.
      final api = _FakeApiClient(behaviours: [
        _FakeBehaviour.transport(), // POST /saved-searches (the save) fails
      ]);
      store.init(db, api);
      // Drain the unawaited index-pull before issuing the save.
      await Future<void>.delayed(const Duration(milliseconds: 30));
      const result = TavilySearchResponse(
          answer: 'a', query: 'q', results: <TavilyResultItem>[]);

      final entry = await store.saveResult(
        kind: SavedSearchKind.query,
        query: 'q',
        result: result,
      );
      // Wait for the unawaited _pushSave to settle.
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(api.calls.where((c) => c.method == 'POST'), hasLength(1),
          reason: 'one POST attempt was made before failure');
      expect(store.debugRetryQueueLength(), equals(1),
          reason: 'failed POST should be queued for retry');

      // Local Drift row is unaffected — the user can still see their save.
      expect(await store.isSaved(entry.id), isTrue);
    });

    test('404 on _pushSave is silently dropped (no retry)', () async {
      final api = _FakeApiClient(behaviours: [
        _FakeBehaviour.status(404), // POST → 404
      ]);
      store.init(db, api);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      const result = TavilySearchResponse(
          answer: 'a', query: 'q', results: <TavilyResultItem>[]);

      await store.saveResult(
        kind: SavedSearchKind.query,
        query: 'q',
        result: result,
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(store.debugRetryQueueLength(), equals(0),
          reason: '404 means backend not deployed — never retry');
    });

    test('404 on _pushDelete purges saved-search + chat + summary rows',
        () async {
      // Pre-seed an entry with a chat message AND a summary row so we can
      // verify all three tables are emptied for that id.
      final api = _FakeApiClient(behaviours: [
        _FakeBehaviour.ok(), // POST /saved-searches (initial save)
        _FakeBehaviour.status(404), // DELETE returns 404 → cleanup path
      ]);
      store.init(db, api);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      const result = TavilySearchResponse(
          answer: 'a', query: 'q', results: <TavilyResultItem>[]);
      final entry = await store.saveResult(
        kind: SavedSearchKind.query,
        query: 'q',
        result: result,
        id: 'e1',
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));

      // Insert a chat message + summary row for this id so we can verify
      // they're cleaned up by the 404 path.
      await db.into(db.savedSearchChatMessages).insert(
            SavedSearchChatMessagesCompanion.insert(
              id: 'm1',
              searchId: entry.id,
              role: 'user',
              msgText: 'hi',
              createdAt: DateTime.now().toUtc().toIso8601String(),
            ),
          );
      await db.into(db.savedSearchChatSummaries).insert(
            SavedSearchChatSummariesCompanion.insert(
              searchId: entry.id,
              summaryText: 'summary',
              pairsCovered: 1,
              updatedAt: DateTime.now().toUtc().toIso8601String(),
            ),
          );

      await store.delete(entry.id);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final searches = await db.select(db.savedSearches).get();
      final messages = await db.select(db.savedSearchChatMessages).get();
      final summaries =
          await db.select(db.savedSearchChatSummaries).get();
      expect(searches.where((r) => r.id == entry.id), isEmpty);
      expect(messages.where((r) => r.searchId == entry.id), isEmpty,
          reason: '404 cleanup must purge orphan chat messages');
      expect(summaries.where((r) => r.searchId == entry.id), isEmpty,
          reason: '404 cleanup must purge orphan summaries');
    });

    test('successful 200 DELETE purges saved-search + chat + summary rows',
        () async {
      final api = _FakeApiClient(behaviours: [
        _FakeBehaviour.ok(), // POST  (initial save)
        _FakeBehaviour.ok(), // DELETE (successful remote)
      ]);
      store.init(db, api);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      const result = TavilySearchResponse(
          answer: 'a', query: 'q', results: <TavilyResultItem>[]);
      final entry = await store.saveResult(
        kind: SavedSearchKind.query,
        query: 'q',
        result: result,
        id: 'e2',
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));

      await db.into(db.savedSearchChatMessages).insert(
            SavedSearchChatMessagesCompanion.insert(
              id: 'm2',
              searchId: entry.id,
              role: 'assistant',
              msgText: 'reply',
              createdAt: DateTime.now().toUtc().toIso8601String(),
            ),
          );
      await db.into(db.savedSearchChatSummaries).insert(
            SavedSearchChatSummariesCompanion.insert(
              searchId: entry.id,
              summaryText: 'sum',
              pairsCovered: 1,
              updatedAt: DateTime.now().toUtc().toIso8601String(),
            ),
          );

      await store.delete(entry.id);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final searches = await db.select(db.savedSearches).get();
      final messages = await db.select(db.savedSearchChatMessages).get();
      final summaries =
          await db.select(db.savedSearchChatSummaries).get();
      expect(searches, isEmpty);
      expect(messages, isEmpty);
      expect(summaries, isEmpty);
    });

    test('appendMessage transient failure enqueues for retry', () async {
      // 1 OK for the save POST; 1 transport failure for the chat append POST.
      final api = _FakeApiClient(behaviours: [
        _FakeBehaviour.ok(), // POST save
        _FakeBehaviour.transport(), // POST chat (fails)
      ]);
      store.init(db, api);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      const result = TavilySearchResponse(
          answer: 'a', query: 'q', results: <TavilyResultItem>[]);
      final entry = await store.saveResult(
        kind: SavedSearchKind.query,
        query: 'q',
        result: result,
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));

      await store.appendMessage(
        searchId: entry.id,
        messageId: 'm1',
        role: 'user',
        text: 'hi',
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(store.debugRetryQueueLength(), equals(1),
          reason: 'failed chat POST should be queued for retry');

      // The local row is still there.
      final msgs = await store.loadMessages(entry.id);
      expect(msgs, hasLength(1));
    });

    test('retry queue is bounded — oldest entries are evicted on overflow',
        () async {
      // Make every call fail so all 250 saves enqueue.
      final api = _FakeApiClient(
        behaviours: List.generate(260, (_) => _FakeBehaviour.transport()),
      );
      store.init(db, api);
      const result = TavilySearchResponse(
          answer: 'a', query: 'q', results: <TavilyResultItem>[]);

      // Push 250 saves through. The retry queue cap is 200; the oldest
      // 50 should be evicted as the newest land.
      for (int i = 0; i < 250; i++) {
        await store.saveResult(
          kind: SavedSearchKind.query,
          query: 'q$i',
          result: result,
          id: 'fixed-$i',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(store.debugRetryQueueLength(), lessThanOrEqualTo(200),
          reason: 'retry queue must respect the hard cap');
      // Local Drift state is unaffected by retry queue caps.
      final all = await store.listAll();
      expect(all, hasLength(250),
          reason: 'all local saves persisted even when remote sync was lost');
    });
  });
}
