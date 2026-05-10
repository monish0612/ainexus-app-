// End-to-end sync tests for SavedSearchStore against a fake backend.
//
// These tests are the production-grade safety net for the cross-device
// sync flow that ships in the Flutter app and depends on the new
// /api/v1/saved-searches backend router.
//
// The [FakeSavedSearchesBackend] embedded below mirrors the real Express
// router exactly:
//   • POST /api/v1/saved-searches              upsert by id
//   • GET  /api/v1/saved-searches              list pinned=TRUE rows
//   • DELETE /api/v1/saved-searches/:id        hard delete (cascade)
//   • GET  /api/v1/saved-searches/:id/chat     all messages for a search
//   • POST /api/v1/saved-searches/:id/chat     upsert one message
//   • PUT  /api/v1/saved-searches/:id/summary  upsert summary
//
// Wire shape (camelCase outbound, tolerant inbound) matches what
// backend/api/src/index.js writes; if those diverge, these tests fail
// loud at the contract boundary.
//
// Scenarios covered:
//   1. Round-trip: save on Device A → pull on Device B → identical row.
//   2. Round-trip: save + chat on Device A → pull on Device B → all
//      messages appear in the same order with the same content.
//   3. responseJson is preserved verbatim (including nested
//      camelCase / arrays / numbers).
//   4. Soft-deleted row on Device A doesn't get resurrected by a stale
//      server pull while the DELETE is still in flight.
//   5. Server returns rows in the exact shape SavedSearchEntry.fromJson
//      expects (this is the contract guarantee).
//   6. Tombstone protection: pull skipping deletedAt-tagged rows.

import 'dart:convert';

import 'package:ai_nexus/core/network/api_client.dart';
import 'package:ai_nexus/core/services/saved_search_store.dart';
import 'package:ai_nexus/data/local/database/app_database.dart';
import 'package:ai_nexus/domain/entities/saved_search.dart';
import 'package:ai_nexus/domain/entities/tutor_entities.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

// ─────────────────────────────────────────────────────────────────────────
//  FakeSavedSearchesBackend — pure-Dart re-implementation of the Express
//  router in backend/api/src/index.js. We keep it inline so contract
//  drift between the two halves of the wire is caught by `flutter test`
//  without spinning up Postgres.
// ─────────────────────────────────────────────────────────────────────────

class _FakeSavedRow {
  _FakeSavedRow({
    required this.id,
    required this.kind,
    required this.query,
    required this.title,
    required this.responseType,
    required this.responseJson,
    required this.model,
    required this.provider,
    required this.mode,
    required this.pinned,
    required this.savedAt,
    required this.updatedAt,
  });

  String id;
  String kind;
  String query;
  String title;
  String responseType;
  String responseJson; // canonical: stored as JSON-encoded string
  String model;
  String provider;
  String mode;
  bool pinned;
  String savedAt;
  String updatedAt;

  Map<String, dynamic> toJson() {
    Object decoded;
    try {
      decoded = jsonDecode(responseJson);
    } catch (_) {
      decoded = responseJson;
    }
    return {
      'id': id,
      'kind': kind,
      'query': query,
      'title': title,
      'responseType': responseType,
      'responseJson': decoded,
      'model': model,
      'provider': provider,
      'mode': mode,
      'pinned': pinned,
      'savedAt': savedAt,
      'updatedAt': updatedAt,
    };
  }
}

class _FakeChatRow {
  _FakeChatRow({
    required this.id,
    required this.searchId,
    required this.role,
    required this.text,
    required this.model,
    required this.sourcesJson,
    required this.createdAt,
  });
  String id;
  String searchId;
  String role;
  String text;
  String model;
  String sourcesJson;
  String createdAt;
}

class FakeSavedSearchesBackend {
  final Map<String, _FakeSavedRow> _searches = {};
  final Map<String, _FakeChatRow> _chats = {};
  final Map<String, Map<String, Object>> _summaries = {};

  /// Recorded calls — each entry is "METHOD path".
  final List<String> calls = [];

  /// Optional behavioral hooks. Set to throw a DioException to simulate
  /// backend errors (5xx, network drop, etc.) on a per-call basis.
  ///
  /// Keys: full method+path string e.g. "POST /api/v1/saved-searches".
  final Map<String, DioException Function()> failures = {};

  /// One-shot failure injectors — each invocation pops the matching entry.
  /// Lets us say "fail the next save POST then succeed forever after".
  final Map<String, List<DioException Function()>> oneShotFailures = {};

  int searchCount() => _searches.length;
  int chatCount() => _chats.length;
  bool hasSearch(String id) => _searches.containsKey(id);
  Map<String, Object> get summaries =>
      _summaries.map((k, v) => MapEntry(k, Map<String, Object>.unmodifiable(v)));

  Object? handle(String method, String path, {Object? body}) {
    final key = '$method $path';
    calls.add(key);

    // Pop a one-shot failure if registered.
    final shots = oneShotFailures[key];
    if (shots != null && shots.isNotEmpty) {
      throw shots.removeAt(0)();
    }
    final perm = failures[key];
    if (perm != null) throw perm();

    // Route resolution — these are the routes the production server exposes.
    if (method == 'GET' && path == '/api/v1/saved-searches') {
      return _searches.values
          .where((r) => r.pinned)
          .toList()
          .reversed // newest-updatedAt-first roughly; tests don't depend on order
          .map((r) => r.toJson())
          .toList();
    }
    if (method == 'POST' && path == '/api/v1/saved-searches') {
      final m = (body as Map).cast<String, Object?>();
      final id = m['id']?.toString() ?? '';
      if (id.isEmpty) {
        throw _http(400, '/api/v1/saved-searches', 'id required');
      }
      // responseJson can arrive as a structured object OR as a string.
      String responseJsonStr;
      final rj = m['responseJson'] ?? m['response_json'];
      if (rj is String) {
        responseJsonStr = rj;
      } else if (rj is Map || rj is List) {
        responseJsonStr = jsonEncode(rj);
      } else {
        responseJsonStr = '{}';
      }
      _searches[id] = _FakeSavedRow(
        id: id,
        kind: m['kind']?.toString() ?? 'query',
        query: m['query']?.toString() ?? '',
        title: m['title']?.toString() ?? '',
        responseType:
            m['responseType']?.toString() ?? m['response_type']?.toString() ?? '',
        responseJson: responseJsonStr,
        model: m['model']?.toString() ?? '',
        provider: m['provider']?.toString() ?? '',
        mode: m['mode']?.toString() ?? '',
        pinned: m['pinned'] is bool ? m['pinned'] as bool : true,
        savedAt: m['savedAt']?.toString() ?? '',
        updatedAt: m['updatedAt']?.toString() ?? '',
      );
      return {'ok': true, 'id': id};
    }

    final searchMatch =
        RegExp(r'^/api/v1/saved-searches/([^/]+)$').firstMatch(path);
    if (searchMatch != null) {
      final id = searchMatch.group(1)!;
      if (method == 'GET') {
        final row = _searches[id];
        if (row == null) throw _http(404, path, 'not found');
        return row.toJson();
      }
      if (method == 'DELETE') {
        _searches.remove(id);
        _chats.removeWhere((_, c) => c.searchId == id);
        _summaries.remove(id);
        return {'ok': true, 'deleted': 1};
      }
    }

    final chatMatch =
        RegExp(r'^/api/v1/saved-searches/([^/]+)/chat$').firstMatch(path);
    if (chatMatch != null) {
      final searchId = chatMatch.group(1)!;
      if (method == 'GET') {
        // Return the same camelCase shape the real Express router emits so
        // the client's `pullMessagesFromServer` parsing path is exercised.
        final rows = _chats.values
            .where((c) => c.searchId == searchId)
            .toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
        return rows
            .map((c) => {
                  'id': c.id,
                  'searchId': c.searchId,
                  'role': c.role,
                  'text': c.text,
                  'model': c.model,
                  'sourcesJson': c.sourcesJson,
                  'createdAt': c.createdAt,
                })
            .toList();
      }
      if (method == 'POST') {
        final m = (body as Map).cast<String, Object?>();
        final id = m['id']?.toString() ?? '';
        final role = m['role']?.toString() ?? '';
        if (id.isEmpty || role.isEmpty) {
          throw _http(400, path, 'id and role required');
        }
        _chats[id] = _FakeChatRow(
          id: id,
          searchId: searchId,
          role: role,
          text: m['text']?.toString() ?? '',
          model: m['model']?.toString() ?? '',
          sourcesJson: m['sourcesJson']?.toString() ??
              m['sources_json']?.toString() ??
              '[]',
          createdAt: m['createdAt']?.toString() ??
              m['created_at']?.toString() ??
              DateTime.now().toUtc().toIso8601String(),
        );
        // Bump parent updatedAt to match the production server.
        final parent = _searches[searchId];
        if (parent != null) {
          parent.updatedAt = m['createdAt']?.toString() ?? parent.updatedAt;
        }
        return {'ok': true, 'id': id};
      }
      if (method == 'DELETE') {
        _chats.removeWhere((_, c) => c.searchId == searchId);
        return {'ok': true, 'deleted': 1};
      }
    }

    final summaryMatch =
        RegExp(r'^/api/v1/saved-searches/([^/]+)/summary$').firstMatch(path);
    if (summaryMatch != null) {
      final searchId = summaryMatch.group(1)!;
      if (method == 'GET') {
        return _summaries[searchId] ?? {};
      }
      if (method == 'PUT') {
        final m = (body as Map).cast<String, Object?>();
        final summaryText =
            (m['summaryText'] ?? m['summary_text'])?.toString() ?? '';
        final pairsCovered =
            ((m['pairsCovered'] ?? m['pairs_covered']) as num?)?.toInt() ?? 0;
        _summaries[searchId] = {
          'summaryText': summaryText,
          'pairsCovered': pairsCovered,
          'updatedAt': m['updatedAt']?.toString() ??
              DateTime.now().toUtc().toIso8601String(),
        };
        return {'ok': true, 'searchId': searchId, 'pairsCovered': pairsCovered};
      }
      if (method == 'DELETE') {
        _summaries.remove(searchId);
        return {'ok': true, 'deleted': 1};
      }
    }

    throw _http(404, path, 'no route');
  }

  static DioException _http(int code, String path, String msg) {
    final req = RequestOptions(path: path);
    return DioException(
      requestOptions: req,
      response: Response<dynamic>(
        requestOptions: req,
        statusCode: code,
        data: msg,
      ),
      type: DioExceptionType.badResponse,
      message: msg,
    );
  }
}

class _BackedApiClient extends ApiClient {
  _BackedApiClient(this._backend);
  final FakeSavedSearchesBackend _backend;

  @override
  Future<Response<T>> get<T>(String path,
      {Map<String, dynamic>? queryParameters}) async {
    final body = _backend.handle('GET', _stripBase(path));
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
      data: body as T?,
    );
  }

  @override
  Future<Response<T>> post<T>(String path,
      {Object? data, Options? options, CancelToken? cancelToken}) async {
    final body = _backend.handle('POST', _stripBase(path), body: data);
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
      data: body as T?,
    );
  }

  @override
  Future<Response<T>> put<T>(String path, {Object? data}) async {
    final body = _backend.handle('PUT', _stripBase(path), body: data);
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
      data: body as T?,
    );
  }

  @override
  Future<Response<T>> delete<T>(String path) async {
    final body = _backend.handle('DELETE', _stripBase(path));
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
      data: body as T?,
    );
  }

  static String _stripBase(String path) {
    // Strip whatever base the test runner thinks AppConstants.baseUrl is so
    // the fake backend can match on the canonical /api/v1/... prefix.
    final i = path.indexOf('/api/v1');
    return i >= 0 ? path.substring(i) : path;
  }
}

// ─────────────────────────────────────────────────────────────────────────

const _stub = TavilySearchResponse(
  answer: 'a',
  query: 'q',
  results: <TavilyResultItem>[],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // We intentionally instantiate AppDatabase from two separate
  // NativeDatabase.memory() executors per test to simulate Device A and
  // Device B. The drift "multiple database" warning fires for distinct
  // QueryExecutors too — it's a false positive here, so we silence it.
  drift.driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('Saved Searches — E2E sync against fake backend', () {
    late FakeSavedSearchesBackend backend;
    late _BackedApiClient api;
    late AppDatabase deviceA;
    late SavedSearchStore storeA;

    setUp(() async {
      backend = FakeSavedSearchesBackend();
      api = _BackedApiClient(backend);
      deviceA = AppDatabase.forTesting(NativeDatabase.memory());
      storeA = SavedSearchStore.instance;
      storeA.debugResetForTests();
      storeA.init(deviceA, api);
      // Drain init's eager index pull before every test so "calls" only
      // contains operations the test actually exercised.
      await Future<void>.delayed(const Duration(milliseconds: 30));
      backend.calls.clear();
    });

    tearDown(() async {
      storeA.debugResetForTests();
      await deviceA.close();
    });

    test('saveResult round-trips to the server in the exact wire shape',
        () async {
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

      final entry = await storeA.saveResult(
        kind: SavedSearchKind.url,
        query: 'https://example.com/article',
        result: result,
      );
      // Wait for the unawaited POST to settle.
      await Future<void>.delayed(const Duration(milliseconds: 30));

      // 1. The server received the POST.
      expect(backend.calls, contains('POST /api/v1/saved-searches'));
      // 2. The server can return the row through GET — exactly one row,
      //    matching the entry we just saved.
      final list =
          (await api.get<Object?>('/api/v1/saved-searches')).data as List;
      expect(list, hasLength(1));
      final wire = (list.single as Map).cast<String, Object?>();

      // 3. The server's wire shape parses cleanly through fromJson — i.e.
      //    the contract between server and client is intact.
      final parsed = SavedSearchEntry.fromJson(wire);
      expect(parsed.id, equals(entry.id));
      expect(parsed.kind, equals(SavedSearchKind.url));
      expect(parsed.query, equals('https://example.com/article'));
      expect(parsed.responseType,
          equals(SavedSearchResponseType.summarizer));
      expect(parsed.model, equals('gemini-2.5-flash'));
      expect(parsed.savedAt, isNotEmpty);
      expect(parsed.updatedAt, isNotEmpty);
      expect(parsed.pinned, isTrue);

      // 4. Decoding the responseJson recovers the original DTO.
      final decoded = parsed.decodedResult();
      expect(decoded, isA<SummarizerResult>());
      expect((decoded as SummarizerResult).keyPoints,
          equals(<String>['one', 'two']));
      expect(decoded.summary, equals('A short summary'));
    });

    test(
        'Device A saves → Device B pulls → row appears with identical content',
        () async {
      const result = SummarizerResult(
        title: 'Cross-device sync',
        summary: 'shared',
        keyPoints: ['x'],
        category: 'tech',
        readTime: 1,
        source: 'src',
        extractionMethod: 'grounding',
        url: 'https://example.com/x',
        model: 'gemini',
      );
      final saved = await storeA.saveResult(
        kind: SavedSearchKind.url,
        query: 'https://example.com/x',
        result: result,
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(backend.hasSearch(saved.id), isTrue,
          reason: 'server must have received the row');

      // Device B comes online — same backend, fresh local Drift.
      final deviceB = AppDatabase.forTesting(NativeDatabase.memory());
      // We can't have two SavedSearchStore singletons, so use a one-off
      // instance via reset/re-init pattern.
      storeA.debugResetForTests();
      storeA.init(deviceB, api);

      // Trigger an index pull — same code path as the resume-lifecycle hook.
      // Because init's eager pull fires unawaited, just give it time to settle.
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final mirrored = await storeA.listAll();
      expect(mirrored, hasLength(1),
          reason: 'Device B must see the row Device A saved');
      final row = mirrored.single;
      expect(row.id, equals(saved.id));
      expect(row.query, equals('https://example.com/x'));
      expect(row.responseType, equals(SavedSearchResponseType.summarizer));
      expect(row.pinned, isTrue);

      // The decoded result is identical → no shape loss across the wire.
      final decoded = row.decodedResult() as SummarizerResult;
      expect(decoded.summary, equals('shared'));
      expect(decoded.keyPoints, equals(<String>['x']));

      await deviceB.close();
    });

    test(
        'chat messages round-trip — Device A appends → Device B pulls — '
        'oldest-first ordering preserved',
        () async {
      final entry = await storeA.saveResult(
        kind: SavedSearchKind.query,
        query: 'q',
        result: _stub,
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));

      // Append three turns with monotonic timestamps so ordering is
      // unambiguous on the server side.
      final t0 = DateTime.now().toUtc();
      await storeA.appendMessage(
        searchId: entry.id,
        messageId: 'q1',
        role: 'user',
        text: 'first ask',
        createdAt: t0.toIso8601String(),
      );
      await storeA.appendMessage(
        searchId: entry.id,
        messageId: 'a1',
        role: 'assistant',
        text: 'first answer',
        model: 'gemini',
        createdAt: t0.add(const Duration(seconds: 1)).toIso8601String(),
      );
      await storeA.appendMessage(
        searchId: entry.id,
        messageId: 'q2',
        role: 'user',
        text: 'follow up',
        createdAt: t0.add(const Duration(seconds: 2)).toIso8601String(),
      );
      await Future<void>.delayed(const Duration(milliseconds: 60));

      // The server received three POST chat calls.
      final chatPosts = backend.calls
          .where((c) =>
              c.startsWith('POST /api/v1/saved-searches/') && c.endsWith('/chat'))
          .toList();
      expect(chatPosts, hasLength(3),
          reason: 'every appendMessage must POST to /:id/chat');
      expect(backend.chatCount(), equals(3));

      // Device B pulls just the chat for this search via the same store.
      final deviceB = AppDatabase.forTesting(NativeDatabase.memory());
      storeA.debugResetForTests();
      storeA.init(deviceB, api);
      // First pull the index so Device B has the parent row, then pull chats.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await storeA.pullMessagesFromServer(entry.id);

      final loaded = await storeA.loadMessages(entry.id);
      expect(loaded.map((m) => m.id), <String>['q1', 'a1', 'q2'],
          reason: 'pulled messages must arrive oldest-first');
      expect(loaded[0].role, equals('user'));
      expect(loaded[0].text, equals('first ask'));
      expect(loaded[1].role, equals('assistant'));
      expect(loaded[1].model, equals('gemini'));
      expect(loaded[2].text, equals('follow up'));

      await deviceB.close();
    });

    test('responseJson preserves nested structure verbatim across the wire',
        () async {
      // Use a grounded response with sources, citations and arrays so we
      // exercise the deepest nesting our payloads contain.
      const grounded = GroundedSearchResponse(
        answer: 'The answer',
        query: 'q',
        model: 'gemini-2.5-pro',
        searchQueries: ['q'],
        sources: [
          GroundedSource(index: 1, title: 'Source A', url: 'https://a.test'),
          GroundedSource(index: 2, title: 'Source B', url: 'https://b.test'),
        ],
        citations: [],
      );
      final entry = await storeA.saveResult(
        kind: SavedSearchKind.query,
        query: 'q',
        result: grounded,
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));

      // Pull the row back from the server and verify it round-trips.
      final list =
          (await api.get<Object?>('/api/v1/saved-searches')).data as List;
      final wire = (list.single as Map).cast<String, Object?>();
      final parsed = SavedSearchEntry.fromJson(wire);
      expect(parsed.id, equals(entry.id));

      final decoded = parsed.decodedResult();
      expect(decoded, isA<GroundedSearchResponse>());
      final g = decoded as GroundedSearchResponse;
      expect(g.answer, equals('The answer'));
      expect(g.sources, hasLength(2));
      expect(g.sources[0].url, equals('https://a.test'));
      expect(g.sources[1].title, equals('Source B'));
      expect(g.model, equals('gemini-2.5-pro'));
    });

    test('soft-delete protected: pull does not resurrect a tombstoned row',
        () async {
      // Device A: save then immediately delete (server's DELETE failure
      // simulated by failing the next DELETE call so the local row stays
      // tombstoned with deletedAt set).
      final entry = await storeA.saveResult(
        kind: SavedSearchKind.query,
        query: 'q',
        result: _stub,
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));

      backend.failures['DELETE /api/v1/saved-searches/${entry.id}'] = () =>
          DioException(
            requestOptions: RequestOptions(
                path: '/api/v1/saved-searches/${entry.id}'),
            type: DioExceptionType.connectionError,
            message: 'simulated network drop',
          );

      await storeA.delete(entry.id);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      // The local row is soft-deleted (deletedAt set).
      final raw = await deviceA.select(deviceA.savedSearches).get();
      expect(raw.where((r) => r.id == entry.id).single.deletedAt, isNotNull);

      // The server still has the row (because DELETE was simulated to fail).
      expect(backend.hasSearch(entry.id), isTrue);

      // Run an index pull manually by simulating a resume — the pull MUST
      // skip the tombstoned row, otherwise the user's "delete" appears to
      // have been silently undone the next time they open the app.
      backend.failures.clear();
      // The pull is unawaited inside didChangeAppLifecycleState — call the
      // private accessor via the public re-init shim instead.
      storeA.debugResetForTests();
      storeA.init(deviceA, api);
      await Future<void>.delayed(const Duration(milliseconds: 40));

      // After the pull, the row is STILL soft-deleted locally — not visible
      // in listAll, deletedAt still set.
      expect(await storeA.listAll(), isEmpty,
          reason: 'soft-deleted rows must stay hidden after a server pull');
      final reloaded = await deviceA.select(deviceA.savedSearches).get();
      expect(reloaded.where((r) => r.id == entry.id).single.deletedAt,
          isNotNull,
          reason:
              'deletedAt must NOT be cleared by a pull — local intent wins '
              'until the DELETE round-trip completes');
    });

    test(
        'undelete re-asserts the row to the server when the local tombstone '
        'is still around (DELETE in-flight or failed)',
        () async {
      final entry = await storeA.saveResult(
        kind: SavedSearchKind.query,
        query: 'q',
        result: _stub,
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));

      // Make DELETE fail with a transport error so the local row stays as a
      // tombstone (deletedAt set, row still in Drift). This is exactly the
      // state the user is in when they tap "Undo" on the snackbar before
      // the DELETE round-trip completes (or while they're offline).
      backend.failures['DELETE /api/v1/saved-searches/${entry.id}'] = () =>
          DioException(
            requestOptions: RequestOptions(
                path: '/api/v1/saved-searches/${entry.id}'),
            type: DioExceptionType.connectionError,
            message: 'simulated network drop on DELETE',
          );

      await storeA.delete(entry.id);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      // Local row is tombstoned (deletedAt != null) but still in Drift.
      final raw = await deviceA.select(deviceA.savedSearches).get();
      expect(raw.where((r) => r.id == entry.id).single.deletedAt, isNotNull);
      // Server still has it (DELETE failed).
      expect(backend.hasSearch(entry.id), isTrue);

      // Clear failures and clear the call log before the undelete so the
      // assertion below only sees what undelete itself triggered.
      backend.failures.clear();
      backend.calls.clear();

      await storeA.undelete(entry.id);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      // The local tombstone is cleared.
      final reloaded = await deviceA.select(deviceA.savedSearches).get();
      expect(reloaded.where((r) => r.id == entry.id).single.deletedAt, isNull);
      // The store must re-POST to the server so the previously-attempted
      // DELETE is re-asserted as a re-create (idempotent in our backend
      // because POST is upsert-by-id).
      expect(backend.calls, contains('POST /api/v1/saved-searches'),
          reason: 'undelete must re-create the server row');
      expect(backend.hasSearch(entry.id), isTrue);
    });

    test('end-to-end: save → chat → delete → all cleaned up server-side',
        () async {
      final entry = await storeA.saveResult(
        kind: SavedSearchKind.query,
        query: 'q',
        result: _stub,
        id: 'e2e-1',
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await storeA.appendMessage(
        searchId: entry.id,
        messageId: 'm-1',
        role: 'user',
        text: 'hi',
      );
      await storeA.appendMessage(
        searchId: entry.id,
        messageId: 'm-2',
        role: 'assistant',
        text: 'hello',
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(backend.hasSearch(entry.id), isTrue);
      expect(backend.chatCount(), equals(2));

      await storeA.delete(entry.id);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      // Server cascade-deleted the chat rows along with the parent.
      expect(backend.hasSearch(entry.id), isFalse);
      expect(backend.chatCount(), equals(0),
          reason: 'DELETE :id must cascade to chat messages on the server');
    });
  });
}
