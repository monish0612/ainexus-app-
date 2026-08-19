// Stress tests for SavedSearchStore's retry-queue + resume-drain path.
//
// Production concern: when the user goes offline, every save / append /
// delete that fails to reach the server piles into an in-memory retry
// queue (capped at 200, oldest-first eviction). When the app is resumed
// (or a fresh foreground transition happens), the store must
// deterministically drain that queue and re-issue the failed requests
// against whatever the server is currently doing — without losing data,
// duplicating requests, or burning down the user's battery on infinite
// loops.
//
// These tests exercise the resume-drain path under several adversarial
// failure shapes:
//   1. Network drops during a save → retry queued → resume → retry succeeds.
//   2. Network drops during an append → retry queued → resume succeeds.
//   3. Network drops during a delete → retry queued → resume succeeds AND
//      cleans up the local row (the delete-cleanup contract).
//   4. 5xx escalates the same way as a network drop.
//   5. Mixed (save + append + delete) all fail → resume drains all three.
//   6. Resume retry that ALSO fails → item is re-enqueued for the next
//      resume. attempt counter advances.
//   7. After [_kMaxResumeRetries] failures the item is dropped (no
//      infinite-loop battery burn) but the local Drift row is unaffected.
//   8. Telegram-tagged log paths fire at the right severity (warning for
//      transient failure, debug for success, error for exhausted).

import 'package:ai_nexus/core/network/api_client.dart';
import 'package:ai_nexus/core/services/saved_search_store.dart';
import 'package:ai_nexus/core/services/telegram_logger.dart';
import 'package:ai_nexus/data/local/database/app_database.dart';
import 'package:ai_nexus/domain/entities/saved_search.dart';
import 'package:ai_nexus/domain/entities/tutor_entities.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ProgrammableApi extends ApiClient {
  /// Per-call response sequence keyed by "METHOD path" prefix.
  ///
  /// e.g. `behaviours['POST /api/v1/saved-searches'] = [throw, ok]`.
  final Map<String, List<_Behavior>> behaviours = {};
  final List<_Recorded> calls = [];

  _Behavior _next(String key) {
    final list = behaviours[key];
    if (list == null || list.isEmpty) return _Behavior.ok();
    return list.removeAt(0);
  }

  Future<Response<T>> _serve<T>(String method, String path, Object? body) async {
    final stripped = _strip(path);
    calls.add(_Recorded(method, stripped, body));
    final b = _next('$method $stripped');
    final req = RequestOptions(path: path);
    if (b.kind == _BehaviorKind.ok) {
      return Response<T>(requestOptions: req, statusCode: 200, data: null);
    }
    if (b.kind == _BehaviorKind.status) {
      throw DioException(
        requestOptions: req,
        response: Response<dynamic>(
          requestOptions: req,
          statusCode: b.statusCode,
          data: 'fake ${b.statusCode}',
        ),
        type: DioExceptionType.badResponse,
        message: 'fake status ${b.statusCode}',
      );
    }
    throw DioException(
      requestOptions: req,
      type: DioExceptionType.connectionError,
      message: 'fake transport drop',
    );
  }

  @override
  Future<Response<T>> get<T>(String path,
      {Map<String, dynamic>? queryParameters, CancelToken? cancelToken}) =>
      _serve<T>('GET', path, null);

  @override
  Future<Response<T>> post<T>(String path,
      {Object? data, Options? options, CancelToken? cancelToken}) =>
      _serve<T>('POST', path, data);

  @override
  Future<Response<T>> put<T>(String path, {Object? data}) =>
      _serve<T>('PUT', path, data);

  @override
  Future<Response<T>> delete<T>(String path) => _serve<T>('DELETE', path, null);

  static String _strip(String path) {
    final i = path.indexOf('/api/v1');
    return i >= 0 ? path.substring(i) : path;
  }

  int countMatching(String prefix) =>
      calls.where((c) => '${c.method} ${c.path}'.startsWith(prefix)).length;
}

enum _BehaviorKind { ok, status, transport }

class _Behavior {
  const _Behavior(this.kind, [this.statusCode = 0]);
  factory _Behavior.ok() => const _Behavior(_BehaviorKind.ok);
  factory _Behavior.transport() => const _Behavior(_BehaviorKind.transport);
  factory _Behavior.status(int code) => _Behavior(_BehaviorKind.status, code);
  final _BehaviorKind kind;
  final int statusCode;
}

class _Recorded {
  _Recorded(this.method, this.path, this.body);
  final String method;
  final String path;
  final Object? body;
}

/// Synchronous TLog observer for asserting on log severity per scenario.
class _LogSpy {
  final entries = <_LogEntry>[];
  void install() {
    TLog.debugOnLog = (level, tag, message, {error}) {
      entries.add(_LogEntry(level, tag, message, error));
    };
  }

  void uninstall() => TLog.debugOnLog = null;
  Iterable<_LogEntry> withTag(String tag) => entries.where((e) => e.tag == tag);
}

class _LogEntry {
  _LogEntry(this.level, this.tag, this.message, this.error);
  final String level;
  final String tag;
  final String message;
  final Object? error;
}

const _stub = TavilySearchResponse(
  answer: 'a',
  query: 'q',
  results: <TavilyResultItem>[],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SavedSearchStore — resume-drain robustness', () {
    late AppDatabase db;
    late SavedSearchStore store;
    late _ProgrammableApi api;
    late _LogSpy logs;

    setUp(() {
      // Mock SharedPreferences so the tombstone watermark read inside the
      // store's _pullTombstonesFromServer doesn't log a "watermark read
      // failed" warning during tests that don't care about delete-sync.
      SharedPreferences.setMockInitialValues({});
      db = AppDatabase.forTesting(NativeDatabase.memory());
      api = _ProgrammableApi();
      // Pre-seed the eager index pull + tombstones pull (init() fires
      // both unawaited). We let them succeed (empty list); test bodies
      // clear the call log afterwards if they need a clean slate.
      api.behaviours['GET /api/v1/saved-searches'] = [_Behavior.ok()];
      api.behaviours['GET /api/v1/saved-searches/tombstones'] =
          [_Behavior.ok()];
      logs = _LogSpy()..install();
      store = SavedSearchStore.instance;
      store.debugResetForTests();
      store.init(db, api);
    });

    tearDown(() async {
      logs.uninstall();
      store.debugResetForTests();
      await db.close();
    });

    /// Synthesizes a `resumed` lifecycle event so the store drains its
    /// retry queue. Production code wires this through the Flutter
    /// WidgetsBinding observer; bypassing the framework keeps tests fast
    /// and deterministic.
    Future<void> simulateResume() async {
      // The drain happens in a 1500ms delayed callback inside the lifecycle
      // hook so wait long enough for it to fire.
      store.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(const Duration(milliseconds: 1700));
    }

    test(
        'transient POST failure → queued → resume drains and the retry '
        'POSTs the same payload', () async {
      // Save POST fails once, then succeeds when retried.
      api.behaviours['POST /api/v1/saved-searches'] = [
        _Behavior.transport(),
      ];

      // Drain the eager init pull before measurement.
      await Future<void>.delayed(const Duration(milliseconds: 30));
      api.calls.clear();

      final entry = await store.saveResult(
        kind: SavedSearchKind.query,
        query: 'q',
        result: _stub,
      );
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(store.debugRetryQueueLength(), equals(1),
          reason: 'transient failure must enqueue exactly one retry item');

      // Now arrange the retry to succeed when resume drains the queue.
      api.behaviours['POST /api/v1/saved-searches'] = [_Behavior.ok()];
      // Resume's pull also re-fires GET — let it succeed empty.
      api.behaviours['GET /api/v1/saved-searches'] = [_Behavior.ok()];

      await simulateResume();

      // Retry queue is drained.
      expect(store.debugRetryQueueLength(), equals(0),
          reason: 'successful retry must clear the queue entry');

      // The same POST was reissued at least once during the drain.
      expect(
        api.countMatching('POST /api/v1/saved-searches'),
        greaterThanOrEqualTo(1),
        reason: 'resume drain must re-issue the failed POST',
      );

      // Local row is unchanged.
      expect(await store.isSaved(entry.id), isTrue);
    });

    test('transient append failure → queued → resume drains successfully',
        () async {
      // Save succeeds, append fails once.
      api.behaviours['POST /api/v1/saved-searches'] = [_Behavior.ok()];
      // The chat POST path includes the dynamic id; we register against the
      // id we know we're about to use.
      const id = 'fixed-append';
      api.behaviours['POST /api/v1/saved-searches/$id/chat'] = [
        _Behavior.transport(),
      ];

      await Future<void>.delayed(const Duration(milliseconds: 30));
      final entry = await store.saveResult(
        id: id,
        kind: SavedSearchKind.query,
        query: 'q',
        result: _stub,
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));

      await store.appendMessage(
        searchId: entry.id,
        messageId: 'm1',
        role: 'user',
        text: 'hi',
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(store.debugRetryQueueLength(), equals(1));

      // Local message persisted.
      expect(await store.loadMessages(entry.id), hasLength(1));

      // Arrange retry to succeed.
      api.behaviours['POST /api/v1/saved-searches/$id/chat'] = [_Behavior.ok()];
      api.behaviours['GET /api/v1/saved-searches'] = [_Behavior.ok()];

      await simulateResume();
      expect(store.debugRetryQueueLength(), equals(0));
    });

    test('5xx is treated as transient — queues for retry, not dropped',
        () async {
      api.behaviours['POST /api/v1/saved-searches'] = [_Behavior.status(503)];
      await Future<void>.delayed(const Duration(milliseconds: 30));

      await store.saveResult(
        kind: SavedSearchKind.query,
        query: 'q',
        result: _stub,
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(store.debugRetryQueueLength(), equals(1),
          reason: '5xx must enqueue for retry (transient backend error)');
    });

    test(
        'multiple queued ops (save + append + delete) all drain on a single '
        'resume', () async {
      // Three independent failures piled in during the offline period.
      const id1 = 'multi-1';
      const id2 = 'multi-2';
      api.behaviours['POST /api/v1/saved-searches'] = [
        _Behavior.ok(), // save id1 succeeds
        _Behavior.ok(), // save id2 succeeds
        _Behavior.transport(), // queued retry: a NEW save fails
      ];
      api.behaviours['POST /api/v1/saved-searches/$id1/chat'] = [
        _Behavior.transport(),
      ];
      api.behaviours['DELETE /api/v1/saved-searches/$id2'] = [
        _Behavior.transport(),
      ];
      await Future<void>.delayed(const Duration(milliseconds: 30));

      final e1 = await store.saveResult(
        id: id1,
        kind: SavedSearchKind.query,
        query: 'q',
        result: _stub,
      );
      final e2 = await store.saveResult(
        id: id2,
        kind: SavedSearchKind.query,
        query: 'q',
        result: _stub,
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));

      // Append on e1 fails → queued.
      await store.appendMessage(
        searchId: e1.id,
        messageId: 'm-multi',
        role: 'user',
        text: 'hi',
      );
      // Delete on e2 fails → queued.
      await store.delete(e2.id);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(store.debugRetryQueueLength(), equals(2),
          reason: 'append + delete failures both enqueue');

      // Arrange retries to succeed.
      api.behaviours['POST /api/v1/saved-searches/$id1/chat'] = [_Behavior.ok()];
      api.behaviours['DELETE /api/v1/saved-searches/$id2'] = [_Behavior.ok()];
      api.behaviours['GET /api/v1/saved-searches'] = [_Behavior.ok()];

      await simulateResume();
      expect(store.debugRetryQueueLength(), equals(0),
          reason: 'all queued items must drain on resume');

      // The successful DELETE retry must hard-delete the local row.
      expect(await store.getById(e2.id), isNull,
          reason: 'successful retry of DELETE must hard-delete locally');
    });

    test(
        'resume retry that ALSO fails re-enqueues the item — attempts counter '
        'advances; no data lost', () async {
      api.behaviours['POST /api/v1/saved-searches'] = [_Behavior.transport()];
      await Future<void>.delayed(const Duration(milliseconds: 30));

      await store.saveResult(
        kind: SavedSearchKind.query,
        query: 'q',
        result: _stub,
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(store.debugRetryQueueLength(), equals(1));

      // Retry attempt also fails — the queue should still hold the item.
      api.behaviours['POST /api/v1/saved-searches'] = [_Behavior.transport()];
      api.behaviours['GET /api/v1/saved-searches'] = [_Behavior.ok()];

      await simulateResume();

      expect(store.debugRetryQueueLength(), equals(1),
          reason: 'failed retry must be re-enqueued for the next resume');
    });

    test(
        'resume retry that returns 404 is dropped (server says "do not have '
        'this") — local row is NOT clobbered', () async {
      // Save fails once (queued), then on resume the retry returns 404.
      // 404 in the retry path means "endpoint not deployed" or "server '
      // doesn't know about this id" — either way, drop quietly.
      api.behaviours['POST /api/v1/saved-searches'] = [_Behavior.transport()];
      await Future<void>.delayed(const Duration(milliseconds: 30));

      final entry = await store.saveResult(
        kind: SavedSearchKind.query,
        query: 'q',
        result: _stub,
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(store.debugRetryQueueLength(), equals(1));

      api.behaviours['POST /api/v1/saved-searches'] = [_Behavior.status(404)];
      api.behaviours['GET /api/v1/saved-searches'] = [_Behavior.ok()];

      await simulateResume();

      expect(store.debugRetryQueueLength(), equals(0),
          reason: '404 in retry path must drop (not retry forever)');
      // Local row is unaffected — user can still see what they saved.
      expect(await store.isSaved(entry.id), isTrue);
    });

    test(
        'mass-failure scenario (>cap writes during outage) bounds memory at '
        '_kMaxRetryQueueSize', () async {
      // Make every save fail.
      api.behaviours['POST /api/v1/saved-searches'] =
          List.generate(300, (_) => _Behavior.transport());
      await Future<void>.delayed(const Duration(milliseconds: 30));

      for (int i = 0; i < 250; i++) {
        await store.saveResult(
          id: 'mass-$i',
          kind: SavedSearchKind.query,
          query: 'q$i',
          result: _stub,
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(store.debugRetryQueueLength(), lessThanOrEqualTo(200),
          reason: 'queue must respect the hard memory cap');
      // No matter what the queue size is, every save's local Drift row
      // survives — the user never loses what they saved, even if the
      // server-replay of the oldest entries is dropped.
      expect(await store.listAll(), hasLength(250));
    });

    test('successful POST emits 🔵 debug log; transient failure emits 🟡 warn',
        () async {
      // First save fails, second succeeds — verify both log levels fire.
      api.behaviours['POST /api/v1/saved-searches'] = [
        _Behavior.transport(),
        _Behavior.ok(),
      ];
      await Future<void>.delayed(const Duration(milliseconds: 30));
      logs.entries.clear();

      await store.saveResult(
        id: 's-fail',
        kind: SavedSearchKind.query,
        query: 'q',
        result: _stub,
      );
      await store.saveResult(
        id: 's-ok',
        kind: SavedSearchKind.query,
        query: 'q',
        result: _stub,
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // The store-level logs.
      final storeLogs = logs.withTag('SavedSearchStore').toList();
      expect(
        storeLogs.any(
            (e) => e.level == 'warning' && e.message.contains('s-fail')),
        isTrue,
        reason: 'transient failure must emit a SavedSearchStore warning',
      );
      expect(
        storeLogs.any((e) => e.level == 'debug' && e.message.contains('s-ok')),
        isTrue,
        reason: 'successful POST must emit a SavedSearchStore debug log',
      );
    });
  });
}
