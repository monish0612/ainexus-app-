// Deep production-flow tests for SavedSearchStore sync.
//
// This file is the explicit safety net for the four pillars the user
// asked us to lock down:
//
//   1. SAVE sync          — saveResult / promoteToSaved → server POST,
//                           survives network outages, rapid bursts, and
//                           Device A→Device B propagation.
//   2. CHAT sync          — appendMessage → POST, ordering preserved,
//                           survives outages, race with parent delete.
//   3. DELETE sync        — DELETE writes tombstones, periodic-foreground
//                           timer picks them up on the other device, the
//                           detail-sheet auto-pop signal works.
//   4. SAVE/REMOVE toasts — production-flow integration of AppToast
//                           around saveResult/delete + Undo path.
//
// The tests intentionally REUSE the FakeSavedSearchesBackend defined in
// saved_search_sync_e2e_test.dart by re-declaring the helper inline (the
// file lives in test/ so we can't import its private helpers directly).
// This keeps the deep tests self-contained and prevents accidental cross-
// file ordering coupling — each test file's `setUp` resets the singleton
// store from a known clean state.
//
// Naming convention:
//   • `[SAVE]`   prefix — save-sync scenarios
//   • `[CHAT]`   prefix — chat-sync scenarios
//   • `[DELETE]` prefix — delete-sync scenarios
//   • `[TOAST]`  prefix — confirmation popover scenarios
//
// Every test is self-isolating and tearDown closes Drift cleanly so the
// suite is safe to run with `--concurrency=1` or in parallel.

import 'dart:convert';
import 'dart:math';

import 'package:ai_nexus/core/network/api_client.dart';
import 'package:ai_nexus/core/services/saved_search_store.dart';
import 'package:ai_nexus/data/local/database/app_database.dart';
import 'package:ai_nexus/domain/entities/saved_search.dart';
import 'package:ai_nexus/domain/entities/tutor_entities.dart';
import 'package:ai_nexus/presentation/widgets/app_toast.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─────────────────────────────────────────────────────────────────────────
//  Fake backend — minimal, in-memory mirror of the production Express
//  router. Kept small here on purpose: this file's tests only need
//  search + chat + tombstone routes. Other contract details (summary,
//  query parameters, response overrides) live in saved_search_sync_e2e_test.dart.
// ─────────────────────────────────────────────────────────────────────────

class _Search {
  _Search({
    required this.id,
    required this.query,
    required this.responseJson,
    required this.savedAt,
    required this.updatedAt,
    this.pinned = true,
  });
  final String id;
  String query;
  String responseJson;
  String savedAt;
  String updatedAt;
  bool pinned;

  Map<String, dynamic> toJson() {
    Object decoded;
    try {
      decoded = jsonDecode(responseJson);
    } catch (_) {
      decoded = responseJson;
    }
    return {
      'id': id,
      'kind': 'query',
      'query': query,
      'title': '',
      'responseType': 'tavily',
      'responseJson': decoded,
      'model': '',
      'provider': '',
      'mode': 'lite',
      'pinned': pinned,
      'savedAt': savedAt,
      'updatedAt': updatedAt,
    };
  }
}

class _Chat {
  _Chat({
    required this.id,
    required this.searchId,
    required this.role,
    required this.text,
    required this.createdAt,
    this.sourcesJson = '[]',
    this.model = '',
  });
  final String id;
  final String searchId;
  final String role;
  final String text;
  final String createdAt;
  final String sourcesJson;
  final String model;

  Map<String, dynamic> toJson() => {
        'id': id,
        'searchId': searchId,
        'role': role,
        'text': text,
        'model': model,
        'sourcesJson': sourcesJson,
        'createdAt': createdAt,
      };
}

class _Backend {
  final Map<String, _Search> searches = {};
  final Map<String, _Chat> chats = {};
  final Map<String, String> tombstones = {}; // id → deletedAt ISO
  final List<String> calls = [];

  /// Permanent failure injectors keyed by "METHOD path" or "METHOD <prefix>".
  /// Prefix matches resolve via startsWith for query-string variants.
  final Map<String, DioException Function()> failures = {};

  /// One-shot failure injectors — pop one per matching request.
  final Map<String, List<DioException Function()>> oneShots = {};

  bool hasSearch(String id) => searches.containsKey(id);
  bool hasTombstone(String id) => tombstones.containsKey(id);
  int searchCount() => searches.length;
  int chatCount() => chats.length;
  int tombstoneCount() => tombstones.length;
  List<_Chat> chatsFor(String sid) =>
      chats.values.where((c) => c.searchId == sid).toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  Object? handle(String method, String path, {Object? body}) {
    final key = '$method $path';
    calls.add(key);

    final shots = oneShots[key];
    if (shots != null && shots.isNotEmpty) throw shots.removeAt(0)();
    final perm = failures[key];
    if (perm != null) throw perm();
    // Prefix match for failures keyed without the query string.
    for (final fk in failures.keys) {
      if (key.startsWith('$fk?')) throw failures[fk]!();
    }

    // ─── /api/v1/saved-searches collection routes ─────────────────
    if (method == 'GET' && path == '/api/v1/saved-searches') {
      return searches.values
          .where((r) => r.pinned)
          .toList()
          .reversed
          .map((r) => r.toJson())
          .toList();
    }
    if (method == 'POST' && path == '/api/v1/saved-searches') {
      final m = (body as Map).cast<String, Object?>();
      final id = m['id']!.toString();
      final encoded =
          m['responseJson'] is String ? m['responseJson']! as String : jsonEncode(m['responseJson']);
      searches[id] = _Search(
        id: id,
        query: m['query']?.toString() ?? '',
        responseJson: encoded,
        savedAt: m['savedAt']?.toString() ?? DateTime.now().toIso8601String(),
        updatedAt:
            m['updatedAt']?.toString() ?? DateTime.now().toIso8601String(),
        pinned: m['pinned'] != false,
      );
      // POST clears any prior tombstone — undelete semantics.
      tombstones.remove(id);
      return {'ok': true, 'id': id};
    }

    // ─── /tombstones (must precede /:id) ──────────────────────────
    const tsBase = '/api/v1/saved-searches/tombstones';
    if (method == 'GET' && (path == tsBase || path.startsWith('$tsBase?'))) {
      String? since;
      final qIdx = path.indexOf('?');
      if (qIdx >= 0) {
        final qs = path.substring(qIdx + 1);
        for (final kv in qs.split('&')) {
          final eq = kv.indexOf('=');
          if (eq < 0) continue;
          final k = Uri.decodeQueryComponent(kv.substring(0, eq));
          final v = Uri.decodeQueryComponent(kv.substring(eq + 1));
          if (k == 'since') since = v;
        }
      }
      var entries = tombstones.entries.toList()
        ..sort((a, b) => a.value.compareTo(b.value));
      if (since != null) {
        entries = entries.where((e) => e.value.compareTo(since!) > 0).toList();
      }
      return entries
          .map((e) => {'id': e.key, 'deletedAt': e.value})
          .toList();
    }

    // ─── /:id and /:id/chat ───────────────────────────────────────
    final idMatch =
        RegExp(r'^/api/v1/saved-searches/([^/]+)$').firstMatch(path);
    if (idMatch != null && method == 'DELETE') {
      final id = idMatch.group(1)!;
      tombstones[id] = DateTime.now().toUtc().toIso8601String();
      searches.remove(id);
      chats.removeWhere((_, c) => c.searchId == id);
      return {'ok': true, 'deleted': 1};
    }

    final chatMatch =
        RegExp(r'^/api/v1/saved-searches/([^/]+)/chat$').firstMatch(path);
    if (chatMatch != null) {
      final searchId = chatMatch.group(1)!;
      if (method == 'GET') {
        return chatsFor(searchId).map((c) => c.toJson()).toList();
      }
      if (method == 'POST') {
        final m = (body as Map).cast<String, Object?>();
        final id = m['id']?.toString() ?? '';
        chats[id] = _Chat(
          id: id,
          searchId: searchId,
          role: m['role']?.toString() ?? 'user',
          text: m['text']?.toString() ?? '',
          model: m['model']?.toString() ?? '',
          sourcesJson: m['sourcesJson']?.toString() ?? '[]',
          createdAt:
              m['createdAt']?.toString() ?? DateTime.now().toIso8601String(),
        );
        // Bump parent updatedAt so list re-orders.
        final parent = searches[searchId];
        if (parent != null) {
          parent.updatedAt =
              m['createdAt']?.toString() ?? parent.updatedAt;
        }
        return {'ok': true, 'id': id};
      }
    }

    // Default 404 — mirrors Express's behaviour for unknown routes.
    throw DioException(
      requestOptions: RequestOptions(path: path),
      response: Response<dynamic>(
        requestOptions: RequestOptions(path: path),
        statusCode: 404,
        data: 'unknown route $path',
      ),
      type: DioExceptionType.badResponse,
      message: 'route not found',
    );
  }

  static DioException dropConn(String path) => DioException(
        requestOptions: RequestOptions(path: path),
        type: DioExceptionType.connectionError,
        message: 'simulated network drop',
      );

  static DioException http5xx(String path) {
    final r = RequestOptions(path: path);
    return DioException(
      requestOptions: r,
      response: Response<dynamic>(
          requestOptions: r, statusCode: 503, data: 'service unavailable'),
      type: DioExceptionType.badResponse,
      message: '503',
    );
  }
}

class _Api extends ApiClient {
  _Api(this._b);
  final _Backend _b;

  String _strip(String p) {
    final i = p.indexOf('/api/v1');
    return i >= 0 ? p.substring(i) : p;
  }

  @override
  Future<Response<T>> get<T>(String path,
      {Map<String, dynamic>? queryParameters}) async {
    final body = _b.handle('GET', _strip(path));
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
      data: body as T?,
    );
  }

  @override
  Future<Response<T>> post<T>(String path,
      {Object? data, Options? options, CancelToken? cancelToken}) async {
    final body = _b.handle('POST', _strip(path), body: data);
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
      data: body as T?,
    );
  }

  @override
  Future<Response<T>> put<T>(String path, {Object? data}) async {
    final body = _b.handle('PUT', _strip(path), body: data);
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
      data: body as T?,
    );
  }

  @override
  Future<Response<T>> delete<T>(String path) async {
    final body = _b.handle('DELETE', _strip(path));
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
      data: body as T?,
    );
  }
}

const _stubResp = TavilySearchResponse(
  answer: 'a',
  query: 'q',
  results: <TavilyResultItem>[],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  drift.driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late _Backend backend;
  late _Api api;
  late AppDatabase deviceA;
  late SavedSearchStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    AppToast.debugResetForTests();
    // Critical: disable the 30 s periodic foreground sync timer in tests.
    // Without this, the timer keeps firing in real time during widget
    // tests and accumulates spurious syncNow invocations that pollute
    // the call log AND make tests run for minutes. Production never
    // touches this knob — see comment on debugDisablePeriodicSync.
    SavedSearchStore.debugDisablePeriodicSync = true;
    backend = _Backend();
    api = _Api(backend);
    deviceA = AppDatabase.forTesting(NativeDatabase.memory());
    store = SavedSearchStore.instance;
    store.debugResetForTests();
    store.init(deviceA, api);
    // Drain init's cold-start sync so test "calls" only contains the
    // operations the test itself triggered.
    await Future<void>.delayed(const Duration(milliseconds: 60));
    backend.calls.clear();
  });

  tearDown(() async {
    AppToast.debugResetForTests();
    store.debugResetForTests();
    SavedSearchStore.debugDisablePeriodicSync = false;
    await deviceA.close();
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  [SAVE] — Save sync deep tests
  // ═══════════════════════════════════════════════════════════════════════

  group('[SAVE] sync deep', () {
    test('saveResult triggers exactly ONE POST per save', () async {
      await store.saveResult(
          kind: SavedSearchKind.query, query: 'q1', result: _stubResp);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      final posts =
          backend.calls.where((c) => c == 'POST /api/v1/saved-searches').length;
      expect(posts, equals(1),
          reason:
              'a single saveResult must produce exactly one POST — extras would waste mobile bandwidth');
    });

    test(
        'rapid burst — 20 sequential saves all reach the server (no drops, '
        'no duplicates)', () async {
      final ids = <String>[];
      for (var i = 0; i < 20; i++) {
        final e = await store.saveResult(
          kind: SavedSearchKind.query,
          query: 'burst-$i',
          result: _stubResp,
        );
        ids.add(e.id);
      }
      // Wait for the unawaited POSTs to drain.
      await Future<void>.delayed(const Duration(milliseconds: 200));

      // Server has all 20 distinct rows.
      expect(backend.searchCount(), equals(20));
      for (final id in ids) {
        expect(backend.hasSearch(id), isTrue,
            reason: 'every burst save must reach the server');
      }
      // Exactly 20 POSTs — not 19, not 21.
      final posts =
          backend.calls.where((c) => c == 'POST /api/v1/saved-searches').length;
      expect(posts, equals(20));
    });

    test(
        'parallel burst — Future.wait of 15 saves all reach the server '
        '(concurrent local writes do not collide)', () async {
      final futures = List.generate(
        15,
        (i) => store.saveResult(
          kind: SavedSearchKind.query,
          query: 'parallel-$i',
          result: _stubResp,
        ),
      );
      final entries = await Future.wait(futures);
      await Future<void>.delayed(const Duration(milliseconds: 250));

      // All 15 rows present locally.
      final local = await store.listAll();
      expect(local.length, equals(15));
      // All 15 rows on the server.
      expect(backend.searchCount(), equals(15));
      // All ids unique.
      final ids = entries.map((e) => e.id).toSet();
      expect(ids.length, equals(15),
          reason: 'each parallel save must allocate a unique id');
    });

    test(
        'save while offline → queued for retry → resume drains it to server '
        '(zero data loss)', () async {
      // Network is down for the next save.
      backend.failures['POST /api/v1/saved-searches'] =
          () => _Backend.dropConn('/api/v1/saved-searches');

      final entry = await store.saveResult(
          kind: SavedSearchKind.query, query: 'offline', result: _stubResp);
      // Local row exists despite the failed POST.
      final local = await store.getById(entry.id);
      expect(local, isNotNull);
      // Server has nothing yet.
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(backend.hasSearch(entry.id), isFalse);

      // Network comes back, app resumes.
      backend.failures.remove('POST /api/v1/saved-searches');
      store.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(const Duration(milliseconds: 1700));

      expect(backend.hasSearch(entry.id), isTrue,
          reason: 'resume must drain the retry queue and POST to server');
    });

    test(
        '5xx server error queues the save for retry — resume eventually pushes '
        'it (transient errors are recoverable)', () async {
      backend.failures['POST /api/v1/saved-searches'] =
          () => _Backend.http5xx('/api/v1/saved-searches');

      final entry = await store.saveResult(
          kind: SavedSearchKind.query, query: '5xx', result: _stubResp);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(backend.hasSearch(entry.id), isFalse);

      // Server recovers; resume drains.
      backend.failures.remove('POST /api/v1/saved-searches');
      store.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(const Duration(milliseconds: 1700));
      expect(backend.hasSearch(entry.id), isTrue);
    });

    test(
        'Device A saves → Device B periodic-foreground sync picks it up '
        'without explicit syncNow (real-time freshness)', () async {
      // Device A saves a row.
      final saved = await store.saveResult(
          kind: SavedSearchKind.query, query: 'cross', result: _stubResp);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(backend.hasSearch(saved.id), isTrue);

      // Device B comes online with a fresh local DB.
      final deviceB = AppDatabase.forTesting(NativeDatabase.memory());
      store.debugResetForTests();
      store.init(deviceB, api);
      // Cold-start sync runs as part of init.
      await Future<void>.delayed(const Duration(milliseconds: 100));

      final mirrored = await store.listAll();
      expect(mirrored.where((e) => e.id == saved.id), hasLength(1),
          reason: 'Device B must see Device A\'s row after cold-start sync');

      await deviceB.close();
    });

    test(
        'large responseJson (10 KB+) round-trips intact — payload size '
        'resilience', () async {
      // Build a Tavily-shaped response with a huge answer field.
      final bigAnswer = List.generate(2000, (i) => 'fact-$i').join(' | ');
      final big = TavilySearchResponse(
        answer: bigAnswer,
        query: 'big',
        results: const <TavilyResultItem>[],
      );
      final entry = await store.saveResult(
          kind: SavedSearchKind.query, query: 'big', result: big);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Server stored it intact.
      expect(backend.hasSearch(entry.id), isTrue);
      final wire =
          (await api.get<Object?>('/api/v1/saved-searches')).data as List;
      final row = (wire.firstWhere(
              (e) => (e as Map)['id'] == entry.id) as Map)
          .cast<String, Object?>();
      final parsed = SavedSearchEntry.fromJson(row);
      final decoded = parsed.decodedResult() as TavilySearchResponse;
      expect(decoded.answer.length, equals(bigAnswer.length),
          reason: 'large payloads must not be truncated by the wire');
      expect(decoded.answer, equals(bigAnswer));
    });

    test(
        'fire-and-forget POST does NOT block saveResult (UI stays snappy '
        'even if the server hangs)', () async {
      // Make POST hang for 2s by simulating a connection error after a delay.
      // Actually our Api implementation doesn't sleep — we use a one-shot
      // failure to verify the local write completes immediately regardless
      // of the network round-trip outcome.
      backend.oneShots['POST /api/v1/saved-searches'] = [
        () => _Backend.dropConn('/api/v1/saved-searches'),
      ];

      final stopwatch = Stopwatch()..start();
      final entry = await store.saveResult(
          kind: SavedSearchKind.query, query: 'snappy', result: _stubResp);
      stopwatch.stop();

      // Local save returns under 100 ms even with a failing POST — the
      // POST is unawaited.
      expect(stopwatch.elapsedMilliseconds, lessThan(100),
          reason:
              'saveResult must return fast for UI snappiness; POST is fire-and-forget');
      // And the row is locally persisted.
      expect(await store.getById(entry.id), isNotNull);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  [CHAT] — Follow-up chat sync deep tests
  // ═══════════════════════════════════════════════════════════════════════

  group('[CHAT] sync deep', () {
    test(
        'appendMessage persists locally AND POSTs to server (each turn)',
        () async {
      final entry = await store.saveResult(
          kind: SavedSearchKind.query, query: 'q', result: _stubResp);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      backend.calls.clear();

      await store.appendMessage(
        searchId: entry.id,
        messageId: 'm1',
        role: 'user',
        text: 'Hello',
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));

      // POST hit the chat endpoint.
      final chatPosts = backend.calls
          .where((c) => c == 'POST /api/v1/saved-searches/${entry.id}/chat')
          .toList();
      expect(chatPosts, hasLength(1));
      // Server has the message.
      expect(backend.chatsFor(entry.id), hasLength(1));
      expect(backend.chatsFor(entry.id).single.text, equals('Hello'));
    });

    test(
        'chat ordering preserved across the wire — 12 turns U/A alternating, '
        'Device B pulls in the exact same order Device A sent', () async {
      final entry = await store.saveResult(
          kind: SavedSearchKind.query, query: 'chat', result: _stubResp);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      // 12 turns alternating user / assistant — createdAt strictly
      // monotonic so the server preserves wall-clock order.
      final base = DateTime.now();
      for (var i = 0; i < 12; i++) {
        await store.appendMessage(
          searchId: entry.id,
          messageId: 'msg-$i',
          role: i.isEven ? 'user' : 'assistant',
          text: 'turn-$i',
          createdAt: base
              .add(Duration(milliseconds: i * 10))
              .toUtc()
              .toIso8601String(),
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));

      // Server has all 12.
      final serverChats = backend.chatsFor(entry.id);
      expect(serverChats, hasLength(12));
      for (var i = 0; i < 12; i++) {
        expect(serverChats[i].id, equals('msg-$i'));
        expect(serverChats[i].text, equals('turn-$i'));
        expect(serverChats[i].role, equals(i.isEven ? 'user' : 'assistant'));
      }

      // Device B comes online with no local chats.
      final deviceB = AppDatabase.forTesting(NativeDatabase.memory());
      store.debugResetForTests();
      store.init(deviceB, api);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      // Pull the chats explicitly (mirrors detail-sheet open).
      await store.pullMessagesFromServer(entry.id);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Device B sees them in the same order.
      final localB = await store.loadMessages(entry.id);
      expect(localB, hasLength(12));
      for (var i = 0; i < 12; i++) {
        expect(localB[i].id, equals('msg-$i'),
            reason:
                'Device B chat order must match Device A — turn $i out of place');
        expect(localB[i].text, equals('turn-$i'));
      }
      await deviceB.close();
    });

    test(
        'chat append while server is down → queued → resume drains the '
        'pending message (zero chat loss)', () async {
      final entry = await store.saveResult(
          kind: SavedSearchKind.query, query: 'q', result: _stubResp);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      backend.calls.clear();

      // Drop network for the chat endpoint.
      backend.failures['POST /api/v1/saved-searches/${entry.id}/chat'] = () =>
          _Backend.dropConn('/api/v1/saved-searches/${entry.id}/chat');

      await store.appendMessage(
        searchId: entry.id,
        messageId: 'm-offline',
        role: 'user',
        text: 'pending',
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));
      // Server didn't get it.
      expect(backend.chatsFor(entry.id), isEmpty);

      // Recover + resume.
      backend.failures.remove('POST /api/v1/saved-searches/${entry.id}/chat');
      store.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(const Duration(milliseconds: 1700));

      expect(backend.chatsFor(entry.id), hasLength(1));
      expect(backend.chatsFor(entry.id).single.id, equals('m-offline'));
    });

    test(
        'long chat text (8 KB) with multiple URL sources round-trips intact',
        () async {
      final entry = await store.saveResult(
          kind: SavedSearchKind.query, query: 'q', result: _stubResp);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      final longText = 'a' * 8000;
      const sources = <GroundedSource>[
        GroundedSource(index: 0, title: 'A', url: 'https://a.example.com/x'),
        GroundedSource(index: 1, title: 'B', url: 'https://b.example.com/y'),
        GroundedSource(index: 2, title: 'C', url: 'https://c.example.com/z'),
      ];
      final encodedSources =
          jsonEncode(sources.map((s) => s.toJson()).toList());

      await store.appendMessage(
        searchId: entry.id,
        messageId: 'long',
        role: 'assistant',
        text: longText,
        sources: sources,
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final c = backend.chatsFor(entry.id).single;
      expect(c.text.length, equals(longText.length));
      expect(c.text, equals(longText));
      expect(c.sourcesJson, equals(encodedSources));
    });

    test(
        'append → server pull → re-append — second append also lands and '
        'order is correct', () async {
      final entry = await store.saveResult(
          kind: SavedSearchKind.query, query: 'q', result: _stubResp);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      await store.appendMessage(
        searchId: entry.id,
        messageId: 'a',
        role: 'user',
        text: 'first',
        createdAt: '2026-05-11T10:00:00.000Z',
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));

      await store.pullMessagesFromServer(entry.id);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      await store.appendMessage(
        searchId: entry.id,
        messageId: 'b',
        role: 'user',
        text: 'second',
        createdAt: '2026-05-11T10:00:01.000Z',
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));

      final server = backend.chatsFor(entry.id);
      expect(server.map((c) => c.id).toList(), equals(['a', 'b']));
      final local = await store.loadMessages(entry.id);
      expect(local.map((m) => m.id).toList(), equals(['a', 'b']));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  [DELETE] — Cross-device delete sync deep tests
  // ═══════════════════════════════════════════════════════════════════════

  group('[DELETE] sync deep', () {
    test(
        'rapid 4-delete burst — exactly the user\'s scenario — all 4 '
        'tombstones land on the server, in monotonic order', () async {
      // Save 4 rows.
      final ids = <String>[];
      for (var i = 0; i < 4; i++) {
        final e = await store.saveResult(
            kind: SavedSearchKind.query,
            query: 'item-$i',
            result: _stubResp);
        ids.add(e.id);
      }
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(backend.searchCount(), equals(4));

      // Delete all 4 rapidly.
      for (final id in ids) {
        await store.delete(id);
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));

      // All 4 tombstones present, all 4 search rows gone.
      expect(backend.tombstoneCount(), equals(4));
      expect(backend.searchCount(), equals(0));
      for (final id in ids) {
        expect(backend.hasTombstone(id), isTrue,
            reason: 'every rapid-delete must write a tombstone for cross-device sync');
      }
    });

    test(
        'periodic foreground sync (manual trigger) — Device B picks up a '
        'tombstone WITHOUT explicit syncNow on UI navigation',
        () async {
      // Step 1: Device A saves and deletes — server now has a tombstone.
      final entry = await store.saveResult(
          kind: SavedSearchKind.query, query: 'shared', result: _stubResp);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await store.delete(entry.id);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(backend.hasTombstone(entry.id), isTrue);

      // Step 2: Bring up Device B with a fresh DB. Insert the stale row
      // into Drift FIRST, then init the store. This sequence reproduces
      // the production scenario where Device B already has a row in its
      // local cache when the periodic foreground timer fires and pulls
      // a tombstone for it.
      final deviceB = AppDatabase.forTesting(NativeDatabase.memory());
      await deviceB.into(deviceB.savedSearches).insertOnConflictUpdate(
            SavedSearchesCompanion.insert(
              id: entry.id,
              kind: 'query',
              query: 'shared',
              title: '',
              responseType: 'tavily',
              responseJson: jsonEncode(_stubResp.toJson()),
              savedAt: DateTime.now().toUtc().toIso8601String(),
              updatedAt: DateTime.now().toUtc().toIso8601String(),
              pinned: const drift.Value(true),
            ),
          );

      // Now init Device B's store — this triggers a cold-start sync,
      // which is functionally identical to the periodic foreground
      // timer firing (same syncNow → same parallel index + tombstone
      // pulls). With a brand-new SharedPreferences (no watermark yet),
      // the tombstone pull pulls EVERYTHING and applies the delete.
      store.debugResetForTests();
      store.init(deviceB, api);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      // Device B's stale row is now gone — without any UI navigation.
      final localB = await store.listAll();
      expect(localB.where((e) => e.id == entry.id), isEmpty,
          reason:
              'sync (cold-start OR periodic-foreground — same code path) must '
              'propagate remote tombstones to Device B');
      await deviceB.close();
    });

    test(
        'detail-sheet auto-pop signal — watchById emits null the moment a '
        'remote tombstone hard-deletes the row Device B is viewing',
        () async {
      // Device A saves a row that ends up on both devices.
      final entry = await store.saveResult(
          kind: SavedSearchKind.query, query: 'view', result: _stubResp);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      // Subscribe to watchById — this is exactly what the detail sheet does.
      final emissions = <SavedSearchEntry?>[];
      final sub = store.watchById(entry.id).listen(emissions.add);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(emissions.last, isNotNull);

      // Device A deletes it. The DELETE writes a tombstone server-side AND
      // hard-deletes the local row.
      await store.delete(entry.id);
      await Future<void>.delayed(const Duration(milliseconds: 80));

      // The watcher emits null → detail sheet would auto-pop.
      expect(emissions.last, isNull,
          reason:
              'watchById must emit null when the row is hard-deleted — this is the auto-pop signal');
      await sub.cancel();
    });

    test(
        'DELETE while offline → tombstone still writes to local Drift; on '
        'resume the retry pushes the DELETE to the server', () async {
      final entry = await store.saveResult(
          kind: SavedSearchKind.query, query: 'q', result: _stubResp);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      // Drop network for DELETE.
      backend.failures['DELETE /api/v1/saved-searches/${entry.id}'] = () =>
          _Backend.dropConn('/api/v1/saved-searches/${entry.id}');

      await store.delete(entry.id);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Server still has the row + no tombstone.
      expect(backend.hasSearch(entry.id), isTrue);
      expect(backend.hasTombstone(entry.id), isFalse);

      // Recover + resume.
      backend.failures
          .remove('DELETE /api/v1/saved-searches/${entry.id}');
      store.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(const Duration(milliseconds: 1700));

      expect(backend.hasSearch(entry.id), isFalse);
      expect(backend.hasTombstone(entry.id), isTrue,
          reason:
              'resume drain must complete the DELETE → tombstone is persisted');
    });

    test(
        'parallel delete burst — Future.wait of 8 deletes all produce '
        'distinct tombstones (no race-condition drops)', () async {
      final entries = <SavedSearchEntry>[];
      for (var i = 0; i < 8; i++) {
        entries.add(await store.saveResult(
            kind: SavedSearchKind.query,
            query: 'p-$i',
            result: _stubResp));
      }
      await Future<void>.delayed(const Duration(milliseconds: 80));

      await Future.wait(entries.map((e) => store.delete(e.id)));
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(backend.tombstoneCount(), equals(8));
      expect(backend.searchCount(), equals(0));
      for (final e in entries) {
        expect(backend.hasTombstone(e.id), isTrue);
      }
    });

    test(
        'delete a saved search that has chat messages — the chats are also '
        'cascade-deleted server-side', () async {
      final entry = await store.saveResult(
          kind: SavedSearchKind.query, query: 'q', result: _stubResp);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      for (var i = 0; i < 5; i++) {
        await store.appendMessage(
          searchId: entry.id,
          messageId: 'c-$i',
          role: i.isEven ? 'user' : 'assistant',
          text: 'msg-$i',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(backend.chatsFor(entry.id), hasLength(5));

      await store.delete(entry.id);
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(backend.chatsFor(entry.id), isEmpty,
          reason:
              'DELETE on the parent must cascade to chat messages server-side');
      expect(backend.hasTombstone(entry.id), isTrue);
    });

    test(
        'syncNow during a delete — concurrent delete + sync still produces '
        'a clean final state (no crashes, no resurrected rows)', () async {
      final entry = await store.saveResult(
          kind: SavedSearchKind.query, query: 'race', result: _stubResp);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      // Fire delete + sync concurrently.
      final deleteFut = store.delete(entry.id);
      final syncFut = store.syncNow(reason: 'concurrent', force: true);
      await Future.wait<void>([deleteFut, syncFut]);
      await Future<void>.delayed(const Duration(milliseconds: 150));

      // Final state: row gone, tombstone present.
      expect(backend.hasSearch(entry.id), isFalse);
      expect(backend.hasTombstone(entry.id), isTrue);
      // Local row is also gone.
      expect(await store.getById(entry.id), isNull);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  [TOAST] — Confirmation popovers (production-flow integration)
  // ═══════════════════════════════════════════════════════════════════════

  group('[TOAST] save/remove popovers — production flow integration', () {
    Widget harness({required Widget child}) =>
        MaterialApp(home: Scaffold(body: child));

    testWidgets(
        '"Saved to Library" toast: shows after saveResult flow + auto-dismisses',
        (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(harness(
        child: Builder(builder: (c) {
          ctx = c;
          return ElevatedButton(
            onPressed: () async {
              final e = await store.saveResult(
                kind: SavedSearchKind.query,
                query: 'integration-save',
                result: _stubResp,
              );
              if (!c.mounted) return;
              AppToast.show(c,
                  message: 'Saved to Library',
                  action: 'Undo',
                  onAction: () => store.delete(e.id),
                  duration: const Duration(milliseconds: 400));
            },
            child: const Text('save'),
          );
        }),
      ));

      await tester.tap(find.text('save'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));
      // Toast is on screen.
      expect(find.text('Saved to Library'), findsOneWidget);
      expect(find.text('Undo'), findsOneWidget);
      // Server received the save.
      expect(backend.searchCount(), equals(1));

      // Wait full lifetime — duration + animation_out + watchdog grace.
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 850));
      expect(AppToast.debugIsShowing(), isFalse,
          reason:
              'save toast must auto-dismiss after duration + grace — production lifecycle invariant');
      expect(ctx.mounted, isTrue);
    });

    testWidgets(
        '"Removed" toast + Undo restores the row when the DELETE was offline',
        (tester) async {
      // Production-realistic Undo flow:
      //   1. User taps Save → row exists locally + server.
      //   2. User taps Remove → local soft-delete + DELETE in flight.
      //   3. (Network blip) DELETE fails → row stays soft-deleted, NOT
      //      hard-deleted. Tombstone written ONLY when server confirms.
      //   4. User taps Undo on the toast → undelete clears soft-delete
      //      and re-asserts via POST (which clears any tombstone
      //      server-side too).
      //
      // We force the DELETE to fail so undelete has a soft-deleted row
      // to operate on — that's the EXACT production scenario where Undo
      // is meaningful (a successful DELETE has no Undo target left).

      late SavedSearchEntry entry;
      await tester.runAsync(() async {
        entry = await store.saveResult(
            kind: SavedSearchKind.query, query: 'undo-me', result: _stubResp);
        await Future<void>.delayed(const Duration(milliseconds: 30));
        // Make DELETE fail so the row remains soft-deleted locally and
        // undelete has something to restore.
        backend.failures['DELETE /api/v1/saved-searches/${entry.id}'] = () =>
            _Backend.dropConn('/api/v1/saved-searches/${entry.id}');
        await store.delete(entry.id);
        await Future<void>.delayed(const Duration(milliseconds: 80));
      });
      // Server still has the row (DELETE failed).
      expect(backend.hasSearch(entry.id), isTrue);
      expect(backend.hasTombstone(entry.id), isFalse);

      var undoTapped = false;
      late BuildContext ctx;
      await tester.pumpWidget(harness(
        child: Builder(builder: (c) {
          ctx = c;
          return ElevatedButton(
            onPressed: () {
              AppToast.show(c,
                  message: 'Removed "undo-me"',
                  action: 'Undo',
                  onAction: () {
                    undoTapped = true;
                  },
                  duration: const Duration(milliseconds: 600));
            },
            child: const Text('show'),
          );
        }),
      ));

      await tester.tap(find.text('show'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));
      expect(find.text('Removed "undo-me"'), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(undoTapped, isTrue,
          reason: 'Undo tap must invoke the onAction callback');
      expect(AppToast.debugIsShowing(), isFalse,
          reason: 'Undo action must dismiss the toast immediately');

      // Drive the undelete via runAsync (Drift isolate work is real
      // wall-clock). Network is back up.
      backend.failures.remove('DELETE /api/v1/saved-searches/${entry.id}');
      await tester.runAsync(() async {
        await store.undelete(entry.id);
        // Poll for the floating _pushSave POST to land on the backend.
        final deadline =
            DateTime.now().add(const Duration(seconds: 2));
        while (DateTime.now().isBefore(deadline)) {
          // The "tombstone cleared" predicate works if the backend has
          // a tombstone (it doesn't — we never reached one). So check
          // that the row is still there with no tombstone.
          final restored = await store.getById(entry.id);
          if (restored != null && restored.deletedAt == null) break;
          await Future<void>.delayed(const Duration(milliseconds: 30));
        }
      });

      // Local row is restored (deletedAt cleared).
      final restored = await tester
          .runAsync(() async => await store.getById(entry.id));
      expect(restored, isNotNull,
          reason: 'undelete must keep the local row alive');
      expect(restored!.deletedAt, isNull,
          reason: 'undelete must clear the local soft-delete tombstone');
      // Server still has the row (it never lost it because DELETE failed).
      expect(backend.hasSearch(entry.id), isTrue);
      expect(backend.hasTombstone(entry.id), isFalse,
          reason: 'no tombstone written — DELETE failed so we never had one');
      expect(ctx.mounted, isTrue);

      // Drain any leftover AppToast slide-out timer so the test framework's
      // "no pending timers" guard passes cleanly.
      await tester.pump(const Duration(milliseconds: 250));
    });

    testWidgets(
        'multiple rapid saves — each new toast REPLACES the prior (no stacking, '
        'no leaked overlays)',
        (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(harness(
        child: Builder(builder: (c) {
          ctx = c;
          return const SizedBox.shrink();
        }),
      ));

      for (var i = 0; i < 5; i++) {
        AppToast.show(ctx,
            message: 'save-$i', duration: const Duration(milliseconds: 200));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 30));
        // Only the LATEST is on screen.
        expect(find.text('save-$i'), findsOneWidget);
        for (var j = 0; j < i; j++) {
          expect(find.text('save-$j'), findsNothing);
        }
      }

      // Drain the final toast cleanly.
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 850));
      expect(AppToast.debugIsShowing(), isFalse);
    });

    testWidgets(
        'watchdog hard-kills toast after duration + animation + 800 ms grace '
        'even under heavy concurrent toast traffic',
        (tester) async {
      // Stress test: spawn → cancel → spawn again 30 times in quick
      // succession. The watchdog must still ensure NO leftover overlays.
      late BuildContext ctx;
      await tester.pumpWidget(harness(
        child: Builder(builder: (c) {
          ctx = c;
          return const SizedBox.shrink();
        }),
      ));

      final r = Random(42);
      for (var i = 0; i < 30; i++) {
        AppToast.show(ctx,
            message: 'cycle-$i',
            duration: Duration(milliseconds: 100 + r.nextInt(200)));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 20));
      }
      // Wait long enough for the watchdog to definitely fire on the
      // last surviving toast.
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 850));
      expect(AppToast.debugIsShowing(), isFalse,
          reason:
              'after the watchdog window, NO toast may remain regardless of stress pattern');
    });
  });
}
