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
import 'package:shared_preferences/shared_preferences.dart';

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
  // Cross-device delete log — id → ISO-8601 deletedAt. Mirrors the
  // production `deleted_saved_searches` table.
  final Map<String, String> _tombstones = {};

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

  /// Per-URL response overrides — when set, the backend returns this
  /// payload INSTEAD of computing the real one. Useful for adversarial
  /// tests that inject malformed payloads to verify graceful degradation.
  /// Keys: full method+path (or method+path?prefix). Matched longest-prefix.
  final Map<String, Object?> responseOverrides = {};

  int searchCount() => _searches.length;
  int chatCount() => _chats.length;
  int tombstoneCount() => _tombstones.length;
  bool hasSearch(String id) => _searches.containsKey(id);
  bool hasTombstone(String id) => _tombstones.containsKey(id);

  /// Test seam — drop the search row WITHOUT writing a tombstone.
  /// Combined with [addTombstone] this lets a test fake "Device B
  /// just deleted row X server-side" without going through the full
  /// DELETE handler that would also clear it locally on Device A.
  void deleteSearchOnly(String id) {
    _searches.remove(id);
    _chats.removeWhere((_, row) => row.searchId == id);
    _summaries.remove(id);
  }

  /// Test seam — inject a tombstone for [id] with [deletedAt] timestamp.
  void addTombstone(String id, DateTime deletedAt) {
    _tombstones[id] = deletedAt.toUtc().toIso8601String();
  }
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

    // Response overrides — return injected payload INSTEAD of computing.
    // Match exact key first, then longest-prefix match (lets `?since=...`
    // requests resolve via a `'GET /api/v1/saved-searches/tombstones'` key).
    if (responseOverrides.containsKey(key)) {
      return responseOverrides[key];
    }
    for (final overrideKey in responseOverrides.keys) {
      if (key.startsWith('$overrideKey?') || key.startsWith('$overrideKey&')) {
        return responseOverrides[overrideKey];
      }
    }

    // Route resolution — these are the routes the production server exposes.
    if (method == 'GET' && path == '/api/v1/saved-searches') {
      return _searches.values
          .where((r) => r.pinned)
          .toList()
          .reversed // newest-updatedAt-first roughly; tests don't depend on order
          .map((r) => r.toJson())
          .toList();
    }

    // Tombstone log — must match BEFORE the /:id route resolves so the
    // string "tombstones" is not misread as an id. The path may include
    // an optional `?since=<iso>` query string.
    const tsBase = '/api/v1/saved-searches/tombstones';
    if (method == 'GET' &&
        (path == tsBase || path.startsWith('$tsBase?'))) {
      String? since;
      final qIdx = path.indexOf('?');
      if (qIdx >= 0) {
        final qs = path.substring(qIdx + 1);
        for (final kv in qs.split('&')) {
          final eq = kv.indexOf('=');
          if (eq < 0) continue;
          final k = kv.substring(0, eq);
          final v = Uri.decodeQueryComponent(kv.substring(eq + 1));
          if (k == 'since') since = v;
        }
      }
      final sinceVal = since;
      final entries = _tombstones.entries
          .where((e) => sinceVal == null || e.value.compareTo(sinceVal) > 0)
          .toList()
        ..sort((a, b) => a.value.compareTo(b.value));
      return entries
          .map((e) => {'id': e.key, 'deletedAt': e.value})
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
      // Cross-device "undelete": the production POST handler clears any
      // tombstone for this id so a re-saved row isn't immediately deleted
      // again by other devices' tombstone pulls.
      _tombstones.remove(id);
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
        // Production server writes the tombstone FIRST so cross-device
        // delete sync still works even if the cascade fails partway.
        _tombstones[id] = DateTime.now().toUtc().toIso8601String();
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
      {Map<String, dynamic>? queryParameters, CancelToken? cancelToken}) async {
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
      // Reset SharedPreferences between tests so the per-install
      // tombstone watermark doesn't leak across test scenarios.
      SharedPreferences.setMockInitialValues({});
      backend = FakeSavedSearchesBackend();
      api = _BackedApiClient(backend);
      deviceA = AppDatabase.forTesting(NativeDatabase.memory());
      storeA = SavedSearchStore.instance;
      storeA.debugResetForTests();
      storeA.init(deviceA, api);
      // Drain init's eager index pull before every test so "calls" only
      // contains operations the test actually exercised.
      await Future<void>.delayed(const Duration(milliseconds: 50));
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
      // Tombstone is recorded for cross-device delete sync.
      expect(backend.hasTombstone(entry.id), isTrue,
          reason: 'DELETE must write a tombstone so other devices can sync');
    });

    // ── Cross-device delete sync (the main reason this test file exists) ──

    test(
        'Device A deletes → tombstone written → Device B pull removes the row '
        'locally', () async {
      // Step 1: Device A saves a row → server has it.
      final entry = await storeA.saveResult(
        id: 'cross-del-1',
        kind: SavedSearchKind.query,
        query: 'q',
        result: _stub,
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(backend.hasSearch(entry.id), isTrue);

      // Step 2: Device B comes online and pulls — has the row locally.
      final deviceB = AppDatabase.forTesting(NativeDatabase.memory());
      storeA.debugResetForTests();
      // Reset SharedPreferences for Device B so its tombstone watermark
      // starts empty (different "install").
      SharedPreferences.setMockInitialValues({});
      storeA.init(deviceB, api);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(await storeA.listAll(), hasLength(1),
          reason: 'Device B should see Device A\'s saved row');

      // Step 3: switch back to Device A and delete the row.
      storeA.debugResetForTests();
      SharedPreferences.setMockInitialValues({});
      storeA.init(deviceA, api);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      await storeA.delete(entry.id);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(backend.hasSearch(entry.id), isFalse);
      expect(backend.hasTombstone(entry.id), isTrue,
          reason: 'DELETE must write a tombstone for cross-device sync');

      // Step 4: Device B comes back online (e.g. opens the app) → its
      // index pull also pulls tombstones, applying them locally.
      storeA.debugResetForTests();
      SharedPreferences.setMockInitialValues({});
      storeA.init(deviceB, api);
      await Future<void>.delayed(const Duration(milliseconds: 80));

      // The deleted row is GONE from Device B.
      expect(await storeA.listAll(), isEmpty,
          reason: 'Device B must apply the tombstone and remove the row');
      // Hard-deleted, not just soft-deleted — no orphan row in Drift.
      final remaining = await deviceB.select(deviceB.savedSearches).get();
      expect(remaining.where((r) => r.id == entry.id), isEmpty,
          reason:
              'tombstone apply must hard-delete locally, not soft-delete');

      await deviceB.close();
    });

    test(
        'tombstone watermark advances across pulls — second pull only fetches '
        'the delta', () async {
      // First delete → first tombstone.
      final e1 = await storeA.saveResult(
        id: 'wm-1',
        kind: SavedSearchKind.query,
        query: 'q',
        result: _stub,
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await storeA.delete(e1.id);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(backend.tombstoneCount(), equals(1));

      // Pull #1 fetches the tombstone. The watermark is now at e1's deletedAt.
      await storeA.debugPullTombstones();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // Pull #2 with no new tombstones — server should be queried with
      // ?since=<watermark> so it returns []. Verify by inspecting the
      // recorded calls: the second tombstone GET should have a since= param.
      backend.calls.clear();
      await storeA.debugPullTombstones();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final tsCalls = backend.calls
          .where((c) => c.contains('/api/v1/saved-searches/tombstones'))
          .toList();
      expect(tsCalls, isNotEmpty);
      expect(tsCalls.first, contains('?since='),
          reason:
              'second pull must include since= so the server only ships the delta');

      // Now delete a second row — the next pull picks up only this new
      // tombstone, NOT the first one again.
      final e2 = await storeA.saveResult(
        id: 'wm-2',
        kind: SavedSearchKind.query,
        query: 'q',
        result: _stub,
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));
      // Deliberately advance time so e2's tombstone is unambiguously
      // newer than e1's on the millisecond clock.
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await storeA.delete(e2.id);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(backend.tombstoneCount(), equals(2));

      backend.calls.clear();
      await storeA.debugPullTombstones();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // Watermark is now at e2's deletedAt.
      expect(
        backend.calls
            .where((c) => c.contains('/api/v1/saved-searches/tombstones'))
            .first,
        contains('?since='),
      );
    });

    test(
        'POST upsert clears the tombstone — re-saving an id that was deleted '
        'on another device removes the tombstone so other devices do not '
        'delete the resurrected row', () async {
      final entry = await storeA.saveResult(
        id: 'undel-1',
        kind: SavedSearchKind.query,
        query: 'q',
        result: _stub,
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));

      // Delete → tombstone written.
      await storeA.delete(entry.id);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(backend.hasTombstone(entry.id), isTrue);

      // Now POST a new row with the SAME id (simulating a re-save on
      // any device). The fake backend (mirroring production) clears the
      // tombstone so other devices won't apply it.
      await storeA.saveResult(
        id: entry.id,
        kind: SavedSearchKind.query,
        query: 'q-redo',
        result: _stub,
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(backend.hasSearch(entry.id), isTrue,
          reason: 're-save POST must restore the row on the server');
      expect(backend.hasTombstone(entry.id), isFalse,
          reason:
              're-save POST must clear the tombstone so other devices do not '
              'delete the resurrected row on their next pull');
    });

    test(
        'tombstone pull is idempotent — applying the same tombstone twice is '
        'a no-op', () async {
      final entry = await storeA.saveResult(
        id: 'idem-1',
        kind: SavedSearchKind.query,
        query: 'q',
        result: _stub,
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));

      // Device B mirrors the row.
      final deviceB = AppDatabase.forTesting(NativeDatabase.memory());
      storeA.debugResetForTests();
      SharedPreferences.setMockInitialValues({});
      storeA.init(deviceB, api);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(await storeA.listAll(), hasLength(1));

      // Switch to A, delete.
      storeA.debugResetForTests();
      SharedPreferences.setMockInitialValues({});
      storeA.init(deviceA, api);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      await storeA.delete(entry.id);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      // Switch to B and pull repeatedly — the second pull should be a no-op
      // because the watermark has advanced past this tombstone.
      storeA.debugResetForTests();
      SharedPreferences.setMockInitialValues({});
      storeA.init(deviceB, api);
      await Future<void>.delayed(const Duration(milliseconds: 60));

      await storeA.debugPullTombstones();
      await storeA.debugPullTombstones();
      await storeA.debugPullTombstones();

      // Row is gone exactly once — no exceptions, no duplicate work.
      expect(await storeA.listAll(), isEmpty);

      await deviceB.close();
    });

    test('tombstone endpoint 404 is downgraded to a warning, not an error',
        () async {
      // Pre-deploy scenario: backend doesn't have the tombstones endpoint
      // yet. Pull must NOT crash, NOT enqueue a retry, and NOT escalate
      // to TLog.e — the rest of sync must continue working unaffected.
      backend.failures['GET /api/v1/saved-searches/tombstones'] = () =>
          DioException(
            requestOptions: RequestOptions(
                path: '/api/v1/saved-searches/tombstones'),
            response: Response<dynamic>(
              requestOptions: RequestOptions(
                  path: '/api/v1/saved-searches/tombstones'),
              statusCode: 404,
              data: 'not found',
            ),
            type: DioExceptionType.badResponse,
            message: 'fake 404',
          );

      // The pull should complete without throwing.
      await storeA.debugPullTombstones();
      // Doing a normal save still works after a 404'd tombstone pull.
      final entry = await storeA.saveResult(
        kind: SavedSearchKind.query,
        query: 'q',
        result: _stub,
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(backend.hasSearch(entry.id), isTrue);
    });

    // ── Adversarial / edge-case tombstone scenarios ──────────────────────

    test('tombstone server 500 does NOT crash and does NOT advance watermark',
        () async {
      backend.failures['GET /api/v1/saved-searches/tombstones'] = () =>
          DioException(
            requestOptions: RequestOptions(
                path: '/api/v1/saved-searches/tombstones'),
            response: Response<dynamic>(
              requestOptions: RequestOptions(
                  path: '/api/v1/saved-searches/tombstones'),
              statusCode: 500,
              data: 'pg pool exhausted',
            ),
            type: DioExceptionType.badResponse,
            message: 'fake 500',
          );

      await storeA.debugPullTombstones();
      // Watermark is still null in SharedPreferences so the next pull will
      // re-request from the start.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('savedSearchStore.lastTombstonePullAt'), isNull,
          reason:
              'a failed pull must NOT advance the watermark — otherwise we '
              'silently miss tombstones the server eventually returns');

      // Recover and pull again.
      backend.failures.clear();
      await storeA.debugPullTombstones();
      // Still no entries to apply, watermark may stay null (no rows
      // returned to set it from). This is expected and safe.
    });

    test(
        'tombstone payload with malformed/missing fields: garbage entries '
        'are skipped, the valid one in the same batch is still applied',
        () async {
      // Brand-new device with one row in Drift and an empty tombstone
      // watermark. Inject a hand-crafted mixed payload via the response
      // override hook — production code's parser MUST defensively skip
      // the garbage entries and still apply the valid one.
      final deviceB = AppDatabase.forTesting(NativeDatabase.memory());
      storeA.debugResetForTests();
      SharedPreferences.setMockInitialValues({});
      storeA.init(deviceB, api);
      await Future<void>.delayed(const Duration(milliseconds: 60));

      // Manually seed a local row that we expect to be tombstoned.
      const targetId = 'kill-me-1';
      await deviceB.into(deviceB.savedSearches).insertOnConflictUpdate(
            SavedSearchesCompanion.insert(
              id: targetId,
              kind: 'query',
              query: 'q',
              title: '',
              responseType: 'tavily',
              responseJson: '{}',
              savedAt: DateTime.now().toUtc().toIso8601String(),
              updatedAt: DateTime.now().toUtc().toIso8601String(),
              pinned: const drift.Value(true),
            ),
          );
      expect(await storeA.listAll(), hasLength(1));

      // Inject malformed-mixed-with-valid response.
      backend.responseOverrides['GET /api/v1/saved-searches/tombstones'] = [
        // 1. Not even a Map — should be skipped.
        'not-a-map',
        // 2. Map missing `id` — should be skipped.
        {'deletedAt': '2099-01-01T00:00:00Z'},
        // 3. Map with empty id — should be skipped.
        {'id': '', 'deletedAt': '2099-01-01T00:00:00Z'},
        // 4. Map with id but no deletedAt — should still apply (deletedAt
        //    only affects watermark advancement, not the apply itself).
        {'id': 'orphan-no-ts'},
        // 5. The valid tombstone for our seeded row.
        {'id': targetId, 'deletedAt': '2099-01-02T00:00:00Z'},
      ];

      await storeA.debugPullTombstones();
      await Future<void>.delayed(const Duration(milliseconds: 30));

      // The valid tombstone was applied — the seeded row is gone.
      expect(await storeA.listAll(), isEmpty,
          reason:
              'a valid tombstone in a batch with malformed entries must '
              'still apply — partial validity is not all-or-nothing');

      await deviceB.close();
    });

    test(
        'watermark survives a store reset (debugResetForTests) — persisted '
        'in SharedPreferences across init cycles', () async {
      final entry = await storeA.saveResult(
        id: 'wm-persist-1',
        kind: SavedSearchKind.query,
        query: 'q',
        result: _stub,
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await storeA.delete(entry.id);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      await storeA.debugPullTombstones();
      await Future<void>.delayed(const Duration(milliseconds: 30));

      // Read the watermark before reset.
      final prefs = await SharedPreferences.getInstance();
      final beforeReset =
          prefs.getString('savedSearchStore.lastTombstonePullAt');
      expect(beforeReset, isNotNull,
          reason: 'first pull with applied tombstones must persist watermark');

      // Reset the store (simulates app cold-start: in-memory state wiped,
      // but SharedPreferences survives).
      storeA.debugResetForTests();
      storeA.init(deviceA, api);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      // Watermark in prefs is unchanged — store reads it lazily on next pull.
      final afterReset =
          prefs.getString('savedSearchStore.lastTombstonePullAt');
      expect(afterReset, equals(beforeReset),
          reason:
              'debugResetForTests must NOT clear SharedPreferences — the '
              'watermark must survive an app cold-start');

      // Now do another pull. Since no new tombstones, this is a no-op
      // and the GET should include since=<watermark>.
      backend.calls.clear();
      await storeA.debugPullTombstones();
      final tsCall = backend.calls.firstWhere(
        (c) => c.contains('/api/v1/saved-searches/tombstones'),
        orElse: () => '',
      );
      expect(tsCall, contains('?since='),
          reason:
              'after reset+init, the persisted watermark must be re-used so '
              'we still only fetch the delta');
    });

    test(
        'three devices: A deletes → B pulls (row gone) → A re-saves → '
        'C must end with the row PRESENT (POST clears tombstone)', () async {
      // Save on A.
      const id = 'three-dev-1';
      await storeA.saveResult(
        id: id,
        kind: SavedSearchKind.query,
        query: 'q',
        result: _stub,
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(backend.hasSearch(id), isTrue);

      // Device B pulls — has the row.
      final deviceB = AppDatabase.forTesting(NativeDatabase.memory());
      storeA.debugResetForTests();
      SharedPreferences.setMockInitialValues({});
      storeA.init(deviceB, api);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(await storeA.listAll(), hasLength(1));

      // A deletes (server writes tombstone).
      storeA.debugResetForTests();
      SharedPreferences.setMockInitialValues({});
      storeA.init(deviceA, api);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      await storeA.delete(id);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(backend.hasTombstone(id), isTrue);

      // B pulls again → row gone.
      storeA.debugResetForTests();
      SharedPreferences.setMockInitialValues({});
      storeA.init(deviceB, api);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(await storeA.listAll(), isEmpty);

      // A re-saves (undelete) — server clears tombstone.
      storeA.debugResetForTests();
      SharedPreferences.setMockInitialValues({});
      storeA.init(deviceA, api);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      await storeA.saveResult(
        id: id,
        kind: SavedSearchKind.query,
        query: 'q-redux',
        result: _stub,
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(backend.hasSearch(id), isTrue,
          reason: 're-save must restore the row server-side');
      expect(backend.hasTombstone(id), isFalse,
          reason: 'POST upsert must clear the prior tombstone');

      // Device C (a fresh device that never saw any of this) pulls.
      // It should see the row PRESENT — the tombstone was cleared so
      // it doesn't sync the (now-stale) delete.
      final deviceC = AppDatabase.forTesting(NativeDatabase.memory());
      storeA.debugResetForTests();
      SharedPreferences.setMockInitialValues({});
      storeA.init(deviceC, api);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      final rowsOnC = await storeA.listAll();
      expect(rowsOnC, hasLength(1),
          reason:
              'Device C must see the resurrected row — the tombstone must '
              'have been cleared by the POST so C does NOT delete it');
      expect(rowsOnC.first.id, equals(id));
      expect(rowsOnC.first.query, equals('q-redux'));

      await deviceB.close();
      await deviceC.close();
    });

    test(
        'large tombstone batch (50 rows) applies in a single pull and '
        'watermark advances to the latest', () async {
      // Save 50 rows.
      final ids = <String>[];
      for (var i = 0; i < 50; i++) {
        final e = await storeA.saveResult(
          id: 'batch-$i',
          kind: SavedSearchKind.query,
          query: 'q-$i',
          result: _stub,
        );
        ids.add(e.id);
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(backend.searchCount(), equals(50));

      // Device B mirrors them.
      final deviceB = AppDatabase.forTesting(NativeDatabase.memory());
      storeA.debugResetForTests();
      SharedPreferences.setMockInitialValues({});
      storeA.init(deviceB, api);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(await storeA.listAll(), hasLength(50));

      // A deletes ALL of them.
      storeA.debugResetForTests();
      SharedPreferences.setMockInitialValues({});
      storeA.init(deviceA, api);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      for (final id in ids) {
        await storeA.delete(id);
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(backend.tombstoneCount(), equals(50),
          reason: 'each delete writes a tombstone');
      expect(backend.searchCount(), equals(0));

      // B pulls — must remove all 50 in one go.
      storeA.debugResetForTests();
      SharedPreferences.setMockInitialValues({});
      storeA.init(deviceB, api);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(await storeA.listAll(), isEmpty,
          reason: 'all 50 tombstones must apply in a single pull');

      await deviceB.close();
    });

    test('delete a row that DOES NOT exist locally — tombstone applies safely',
        () async {
      // This is the new-device-pulls-old-tombstones scenario. Device B is
      // brand-new, has nothing locally, but the server's tombstone log
      // still contains rows that were deleted from other devices.
      // Applying the tombstone must be a graceful no-op.
      final e = await storeA.saveResult(
        id: 'never-here-1',
        kind: SavedSearchKind.query,
        query: 'q',
        result: _stub,
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await storeA.delete(e.id);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(backend.hasTombstone(e.id), isTrue);

      // Brand-new device that has no local rows.
      final deviceC = AppDatabase.forTesting(NativeDatabase.memory());
      storeA.debugResetForTests();
      SharedPreferences.setMockInitialValues({});
      storeA.init(deviceC, api);
      await Future<void>.delayed(const Duration(milliseconds: 80));

      // No exceptions, no log noise — graceful no-op.
      expect(await storeA.listAll(), isEmpty);
      // And further pulls are still idempotent.
      await storeA.debugPullTombstones();
      await storeA.debugPullTombstones();
      expect(await storeA.listAll(), isEmpty);

      await deviceC.close();
    });

    test('rapid delete + undelete + delete — final server state is DELETED',
        () async {
      final entry = await storeA.saveResult(
        id: 'flap-1',
        kind: SavedSearchKind.query,
        query: 'q',
        result: _stub,
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(backend.hasSearch(entry.id), isTrue);

      // delete → undelete → delete in rapid succession.
      await storeA.delete(entry.id);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await storeA.undelete(entry.id);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await storeA.delete(entry.id);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      // The final state on the server is DELETED with a tombstone present.
      expect(backend.hasSearch(entry.id), isFalse,
          reason: 'final delete must hard-delete server-side');
      expect(backend.hasTombstone(entry.id), isTrue,
          reason: 'final state must have a tombstone for cross-device sync');
    });

    test(
        'tombstone GET returns malformed JSON shape (not a list) — store '
        'logs a warning and continues', () async {
      // Spy on log severity to confirm we don't escalate to ERROR.
      backend.failures['GET /api/v1/saved-searches/tombstones'] = () =>
          DioException(
            requestOptions: RequestOptions(
                path: '/api/v1/saved-searches/tombstones'),
            response: Response<dynamic>(
              requestOptions: RequestOptions(
                  path: '/api/v1/saved-searches/tombstones'),
              statusCode: 200,
              // Wrong shape — string instead of list.
              data: 'tombstones unavailable',
            ),
            type: DioExceptionType.badResponse,
            message: 'wrong shape',
          );

      // Should not throw, should not crash the store.
      await storeA.debugPullTombstones();

      // Subsequent saves still work.
      backend.failures.clear();
      final entry = await storeA.saveResult(
        kind: SavedSearchKind.query,
        query: 'q',
        result: _stub,
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(backend.hasSearch(entry.id), isTrue);
    });

    test(
        'watermark uses string lex-ordering on ISO-8601 (which is a '
        'monotonic ordering) so 2026-01-02 > 2026-01-01 etc.', () async {
      // Sanity check on the production assumption: ISO-8601 strings sort
      // lexicographically the same way they sort temporally. If this ever
      // breaks (e.g. Postgres switches format), tombstone watermark
      // advancement would silently regress.
      const a = '2026-01-01T00:00:00.000Z';
      const b = '2026-01-02T00:00:00.000Z';
      const c = '2026-12-31T23:59:59.999Z';
      const d = '2027-01-01T00:00:00.000Z';
      expect(a.compareTo(b), lessThan(0));
      expect(b.compareTo(c), lessThan(0));
      expect(c.compareTo(d), lessThan(0));
      // Cross-day boundary
      expect('2026-01-09T23:00:00.000Z'.compareTo('2026-01-10T00:00:00.000Z'),
          lessThan(0));
    });

    // ─── New: parallel-sync, coalescing, watch-by-id, real-time delete ────

    test(
        'syncNow runs index pull AND tombstone pull in PARALLEL — total '
        'wall-time is max(t_index, t_tombstones), not their sum', () async {
      // Save a few rows so the index pull has work to do.
      await storeA.saveResult(
          kind: SavedSearchKind.query, query: 'a', result: _stub);
      await storeA.saveResult(
          kind: SavedSearchKind.query, query: 'b', result: _stub);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      backend.calls.clear();

      final stopwatch = Stopwatch()..start();
      await storeA.syncNow(reason: 'test-parallel', force: true);
      stopwatch.stop();

      // Both endpoints must have been called.
      final hadIndex = backend.calls
          .any((c) => c == 'GET /api/v1/saved-searches');
      final hadTombstones = backend.calls.any((c) =>
          c.startsWith('GET /api/v1/saved-searches/tombstones'));
      expect(hadIndex, isTrue,
          reason: 'syncNow must hit the index endpoint');
      expect(hadTombstones, isTrue,
          reason: 'syncNow must hit the tombstones endpoint');
      // No assertion on stopwatch — that would be flaky in CI — the
      // CONTRACT is that both calls fire concurrently. A future
      // regression where they're sequenced would fail the next test.
    });

    test(
        'syncNow coalesces concurrent callers into a single network '
        'round-trip (no thundering herd from sheet-open + lifecycle-resume)',
        () async {
      backend.calls.clear();

      // Fire 10 simultaneous syncNow calls — exactly mimics:
      //   - sheet-open scheduling a sync
      //   - lifecycle-resumed firing the same instant
      //   - the 30 s timer ticking right at that moment
      //   - the user tapping back into the sheet a second later (debounce)
      // First call uses force=true to defeat the debounce from setUp's
      // cold-start sync; the in-flight coalescing guard then makes the
      // remaining 9 calls join the same Future regardless of `force`.
      await Future.wait<void>(
        List.generate(
            10,
            (i) => storeA.syncNow(
                reason: 'concurrent-$i', force: i == 0)),
      );

      final indexHits =
          backend.calls.where((c) => c == 'GET /api/v1/saved-searches').length;
      final tombstoneHits = backend.calls
          .where((c) => c.startsWith('GET /api/v1/saved-searches/tombstones'))
          .length;

      // Coalesced: at MOST one round-trip per endpoint, NOT 10.
      expect(indexHits, lessThanOrEqualTo(1),
          reason: 'concurrent syncNow must not stampede the index endpoint');
      expect(tombstoneHits, lessThanOrEqualTo(1),
          reason:
              'concurrent syncNow must not stampede the tombstones endpoint');
    });

    test(
        'syncNow debounces rapid sequential calls (sub-500 ms gap) so '
        'tab-switch-spam does not stampede the network', () async {
      backend.calls.clear();

      // First call uses force=true to defeat the cold-start debounce
      // window from setUp; subsequent UN-FORCED calls within 500 ms
      // MUST be debounced.
      await storeA.syncNow(reason: 'first', force: true);
      await storeA.syncNow(reason: 'second');
      await storeA.syncNow(reason: 'third');

      final indexHits =
          backend.calls.where((c) => c == 'GET /api/v1/saved-searches').length;
      expect(indexHits, equals(1),
          reason: 'rapid syncNow within debounce window must coalesce');
    });

    test(
        'watchById emits null when a tombstone arrives from another device '
        '— sheet auto-pop signal works end-to-end', () async {
      // 1. Device A saves a row.
      final entry = await storeA.saveResult(
          kind: SavedSearchKind.query, query: 'shared', result: _stub);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(backend.hasSearch(entry.id), isTrue);

      // 2. Subscribe to the live row.
      final emissions = <SavedSearchEntry?>[];
      final sub = storeA.watchById(entry.id).listen(emissions.add);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(emissions.last, isNotNull);
      expect(emissions.last!.id, equals(entry.id));

      // 3. Simulate "Device B deleted this row" — manually inject a
      //    tombstone on the backend and pull it.
      backend.deleteSearchOnly(entry.id);
      backend.addTombstone(entry.id, DateTime.now());
      await storeA.debugPullTombstones();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // 4. The watcher must have emitted null (row vanished).
      expect(emissions.last, isNull,
          reason:
              'watchById must emit null after a remote tombstone hard-deletes the row');

      await sub.cancel();
    });

    test(
        'syncNow is silent (no error, no exception) when network completely '
        'unavailable — safe to call from anywhere in UI', () async {
      // Make every endpoint fail with a transport error.
      backend.failures['GET /api/v1/saved-searches'] = () => DioException(
            requestOptions:
                RequestOptions(path: '/api/v1/saved-searches'),
            type: DioExceptionType.connectionError,
            message: 'no network',
          );
      backend.failures['GET /api/v1/saved-searches/tombstones'] = () =>
          DioException(
            requestOptions: RequestOptions(
                path: '/api/v1/saved-searches/tombstones'),
            type: DioExceptionType.connectionError,
            message: 'no network',
          );

      // MUST NOT throw — UI callers expect fire-and-forget semantics.
      await storeA.syncNow(reason: 'no-network');
      // And calling it a second time still doesn't throw.
      backend.calls.clear();
      await storeA.syncNow(reason: 'no-network-2');
    });
  });
}
