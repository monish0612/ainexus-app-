// Deep robustness, scaling and failure-mode tests for the nuke/clear/sync-queue
// changes. Everything runs against a REAL in-memory Drift DB with a
// programmable fake ApiClient so we exercise the exact production paths:
//   • atomic local wipe at scale (tens of thousands of rows)
//   • cloud DELETE → GET-verify → exponential-backoff retry → pending flag
//   • partial cloud outages (some domains fail, others succeed)
//   • transient failures that recover within the retry budget
//   • the durable salary SyncQueue: dedup, drain, partial-failure, malformed
//     payloads, and clear-purge — at scale
//   • concurrency (double-nuke, concurrent enqueue)
//   • SavedSearchStore.clearAllRemote offline → self-heal
//
// Performance assertions use generous wall-clock bounds: they exist to catch
// catastrophic O(n^2)/regression cliffs, not to micro-benchmark CI hardware.

import 'dart:convert';

import 'package:ai_nexus/core/network/api_client.dart';
import 'package:ai_nexus/core/services/app_nuke_service.dart';
import 'package:ai_nexus/core/services/reset_sync_service.dart';
import 'package:ai_nexus/core/services/saved_search_store.dart';
import 'package:ai_nexus/data/local/database/app_database.dart' as db;
import 'package:ai_nexus/data/repositories/expense_repository.dart';
import 'package:ai_nexus/data/repositories/news_repository.dart';
import 'package:ai_nexus/data/repositories/salary_repository.dart';
import 'package:ai_nexus/data/repositories/saved_words_repository.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Fake ApiClient with per-(method+path) attempt counting and a programmable
/// failure rule + GET responder, so each test can sculpt exactly the cloud
/// behaviour it needs.
class _ProgApi extends ApiClient {
  _ProgApi();

  /// Return true to make THIS call throw a connection error. Receives the
  /// HTTP method, the full path, and the 1-based attempt number for that
  /// (method, path) pair.
  bool Function(String method, String path, int attempt)? failRule;

  /// GET body provider, keyed on path. Defaults to an empty list (the shape
  /// the clear-verify reads expect).
  Object? Function(String path)? getResponder;

  final Map<String, int> _counts = <String, int>{};
  final List<String> deletes = <String>[];
  final List<({String path, Object? data})> posts = <({String path, Object? data})>[];

  int attemptsFor(String method, String path) => _counts['$method $path'] ?? 0;

  int _bump(String method, String path) {
    final key = '$method $path';
    final n = (_counts[key] ?? 0) + 1;
    _counts[key] = n;
    return n;
  }

  Response<T> _ok<T>(String path, Object? data) => Response<T>(
        requestOptions: RequestOptions(path: path),
        data: data as T?,
        statusCode: 200,
      );

  Never _offline(String path) => throw DioException(
        requestOptions: RequestOptions(path: path),
        type: DioExceptionType.connectionError,
        message: 'fake offline',
      );

  @override
  Future<Response<T>> get<T>(String path,
      {Map<String, dynamic>? queryParameters, CancelToken? cancelToken}) async {
    final n = _bump('GET', path);
    if (failRule?.call('GET', path, n) ?? false) _offline(path);
    return _ok<T>(path, getResponder?.call(path) ?? const <dynamic>[]);
  }

  @override
  Future<Response<T>> post<T>(String path,
      {Object? data, Options? options, CancelToken? cancelToken}) async {
    final n = _bump('POST', path);
    if (failRule?.call('POST', path, n) ?? false) _offline(path);
    posts.add((path: path, data: data));
    return _ok<T>(path, null);
  }

  @override
  Future<Response<T>> delete<T>(String path) async {
    final n = _bump('DELETE', path);
    if (failRule?.call('DELETE', path, n) ?? false) _offline(path);
    deletes.add(path);
    return _ok<T>(path, null);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late db.AppDatabase database;
  late _ProgApi api;
  late ExpenseRepository expenseRepo;
  late SalaryRepository salaryRepo;
  late SavedWordsRepository savedWordsRepo;
  late ResetSyncService resetSync;
  late SharedPreferences prefs;

  var savedSearchOk = true;
  var savedSearchThrows = false;
  var savedSearchCalls = 0;

  AppNukeService buildAppNuke() => AppNukeService(
        database,
        expenseRepo,
        salaryRepo,
        savedWordsRepo,
        NewsRepository(database, api),
        resetSync,
        clearSavedSearches: () async {
          savedSearchCalls++;
          if (savedSearchThrows) throw StateError('boom');
          return savedSearchOk;
        },
      );

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    prefs = await SharedPreferences.getInstance();
    database = db.AppDatabase.forTesting(NativeDatabase.memory());
    api = _ProgApi();
    expenseRepo = ExpenseRepository(database, api, prefs);
    salaryRepo = SalaryRepository(database, api, prefs);
    savedWordsRepo = SavedWordsRepository(database, api, prefs);
    resetSync = ResetSyncService(database, api, prefs);
    savedSearchOk = true;
    savedSearchThrows = false;
    savedSearchCalls = 0;
  });

  tearDown(() async {
    try {
      await database.close();
    } catch (_) {/* some tests close early */}
  });

  // ── Bulk seeding helpers (batched for speed) ────────────────────────────────

  Future<void> seedExpenses(int n) => database.batch((b) {
        for (var i = 0; i < n; i++) {
          b.insert(
            database.expenses,
            db.ExpensesCompanion.insert(
              id: 'e$i',
              amount: (i % 5000).toDouble(),
              description: 'd$i',
              category: const ['Food', 'Bills', 'Transport'][i % 3],
              bank: 'HDFC',
              cardType: 'CC',
              date: '2026-06-${(i % 28) + 1}T10:00:00.000Z',
            ),
          );
        }
      });

  Future<void> seedSavedWords(int n) => database.batch((b) {
        for (var i = 0; i < n; i++) {
          b.insert(
            database.savedWords,
            db.SavedWordsCompanion.insert(
              id: 'w$i',
              word: 'word$i',
              definition: 'def$i',
              pronunciation: '',
              partOfSpeech: 'noun',
              savedAt: '2026-06-26T10:00:00.000Z',
            ),
          );
        }
      });

  Future<void> seedLearnings(int n) => database.batch((b) {
        for (var i = 0; i < n; i++) {
          b.insert(
            database.categoryLearnings,
            db.CategoryLearningsCompanion.insert(
              keyword: 'kw$i',
              category: 'Food',
            ),
          );
        }
      });

  String salaryPayload(String month, double amount) => jsonEncode({
        'id': 'sal-$month',
        'month': month,
        'amount': amount,
        'setAt': '2026-06-01T00:00:00.000Z',
      });

  // ═══════════════════════════════════════════════════════════════════════════
  //  LARGE-DATA SCALING
  // ═══════════════════════════════════════════════════════════════════════════

  group('Scaling — full nuke on large datasets', () {
    test('wipes 40k+ rows across tables completely and quickly', () async {
      await seedExpenses(25000);
      await seedSavedWords(8000);
      await seedLearnings(8000);

      final sw = Stopwatch()..start();
      final report = await buildAppNuke().nuke();
      sw.stop();

      expect(report.totalCleared, 41000);
      expect(report.lines.firstWhere((l) => l.label == 'Expenses').count, 25000);

      final after = await database.dataRowCounts();
      expect(after.values.every((c) => c == 0), isTrue,
          reason: 'every table emptied — no partial wipe at scale');

      // Catastrophic-regression guard (in-memory drift wipes this in well under
      // a second on any machine; 20s leaves enormous headroom for slow CI).
      expect(sw.elapsedMilliseconds, lessThan(20000));

      // DB still fully usable after a large wipe (schema intact).
      await seedExpenses(3);
      expect((await database.select(database.expenses).get()).length, 3);
    });

    test('dataRowCounts is exact under large, uneven table sizes', () async {
      await seedExpenses(12345);
      await seedSavedWords(6789);
      await seedLearnings(321);

      final counts = await database.dataRowCounts();
      expect(counts['Expenses'], 12345);
      expect(counts['Saved words'], 6789);
      expect(counts['Learnings'], 321);
      expect(counts['News'], 0);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  //  SALARY SYNCQUEUE — scaling + robustness
  // ═══════════════════════════════════════════════════════════════════════════

  group('SyncQueue — scaling & robustness', () {
    test('drains hundreds of queued months on reconnect', () async {
      for (var i = 0; i < 365; i++) {
        final month = '20${10 + (i ~/ 12)}-${(i % 12) + 1}';
        await database.enqueueSync(
          entityType: 'salary',
          entityId: month,
          action: 'upsert',
          payload: salaryPayload(month, (1000 + i).toDouble()),
        );
      }
      expect(await database.pendingSyncItems('salary'), hasLength(365));

      final sw = Stopwatch()..start();
      final drained = await salaryRepo.drainSyncQueue();
      sw.stop();

      expect(drained, 365);
      expect(await database.pendingSyncItems('salary'), isEmpty);
      expect(api.posts.where((p) => p.path.contains('/salary')).length, 365);
      expect(sw.elapsedMilliseconds, lessThan(20000));
    });

    test('heavy same-key churn collapses to a single latest row', () async {
      for (var i = 0; i < 2000; i++) {
        await database.enqueueSync(
          entityType: 'salary',
          entityId: '2026-06',
          action: 'upsert',
          payload: salaryPayload('2026-06', 100 + i.toDouble()),
        );
      }
      final queued = await database.pendingSyncItems('salary');
      expect(queued, hasLength(1), reason: 'no unbounded growth on re-saves');

      final decoded = jsonDecode(queued.single.payload) as Map<String, dynamic>;
      expect(decoded['amount'], 2099, reason: 'latest write wins');
    });

    test('drain keeps the items whose push fails, removes the rest', () async {
      const months = ['m1', 'm2', 'm3', 'm4', 'm5'];
      for (final m in months) {
        await database.enqueueSync(
          entityType: 'salary',
          entityId: m,
          action: 'upsert',
          payload: salaryPayload(m, 5000),
        );
      }
      // Fail only the 3rd POST to the salary endpoint.
      api.failRule = (method, path, attempt) =>
          method == 'POST' && path.contains('/salary') && attempt == 3;

      final drained = await salaryRepo.drainSyncQueue();
      expect(drained, 4);

      final left = await database.pendingSyncItems('salary');
      expect(left, hasLength(1));
      expect(left.single.entityId, 'm3', reason: 'only the failing item remains');

      // A later drain (now healthy) clears it.
      api.failRule = null;
      expect(await salaryRepo.drainSyncQueue(), 1);
      expect(await database.pendingSyncItems('salary'), isEmpty);
    });

    test('drain tolerates a malformed payload row without crashing', () async {
      // Corrupt row inserted directly (simulates a schema/codec drift).
      await database.into(database.syncQueue).insert(
            db.SyncQueueCompanion.insert(
              entityType: 'salary',
              entityId: 'bad',
              action: 'upsert',
              payload: 'this-is-not-json',
              createdAt: '2026-06-01T00:00:00.000Z',
            ),
          );
      await database.enqueueSync(
        entityType: 'salary',
        entityId: '2026-06',
        action: 'upsert',
        payload: salaryPayload('2026-06', 9000),
      );

      final drained = await salaryRepo.drainSyncQueue();
      expect(drained, 1, reason: 'valid row drained, malformed skipped');

      final left = await database.pendingSyncItems('salary');
      expect(left, hasLength(1));
      expect(left.single.entityId, 'bad', reason: 'malformed row preserved');
    });

    test('clearSalaryHistory purges a large queue (no resurrection)', () async {
      for (var i = 0; i < 100; i++) {
        await database.enqueueSync(
          entityType: 'salary',
          entityId: 'm$i',
          action: 'upsert',
          payload: salaryPayload('m$i', 1000),
        );
      }
      expect(await database.pendingSyncItems('salary'), hasLength(100));

      await salaryRepo.clearSalaryHistory();
      expect(await database.pendingSyncItems('salary'), isEmpty);
    });

    test('a full nuke also purges the durable queue (no resurrection)',
        () async {
      await database.enqueueSync(
        entityType: 'salary',
        entityId: '2026-06',
        action: 'upsert',
        payload: salaryPayload('2026-06', 80000),
      );
      // Even with the cloud offline, the local wipe clears the outbox.
      api.failRule = (method, _, __) => method == 'DELETE';
      await buildAppNuke().nuke();
      expect(await database.pendingSyncItems('salary'), isEmpty,
          reason: 'queued offline write must not survive a full reset');
    });

    test('queued rows never inflate the nuke report counts', () async {
      await database.enqueueSync(
        entityType: 'salary',
        entityId: '2026-06',
        action: 'upsert',
        payload: salaryPayload('2026-06', 80000),
      );
      final counts = await database.dataRowCounts();
      // sync_queue is internal plumbing — it must not appear as user data.
      expect(counts.containsKey('SyncQueue'), isFalse);
      expect(counts.values.fold<int>(0, (s, v) => s + v), 0);
    });

    test('different entity types never collide in the queue', () async {
      await database.enqueueSync(
        entityType: 'salary',
        entityId: '2026-06',
        action: 'upsert',
        payload: salaryPayload('2026-06', 1000),
      );
      await database.enqueueSync(
        entityType: 'other',
        entityId: '2026-06',
        action: 'upsert',
        payload: '{}',
      );
      expect(await database.pendingSyncItems('salary'), hasLength(1));
      expect(await database.pendingSyncItems('other'), hasLength(1));

      await database.purgeSyncByType('salary');
      expect(await database.pendingSyncItems('salary'), isEmpty);
      expect(await database.pendingSyncItems('other'), hasLength(1),
          reason: 'purge is scoped to a single entity type');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  //  CLOUD FAILURE MODES
  // ═══════════════════════════════════════════════════════════════════════════

  group('Cloud clear — verify + retry + partial failure', () {
    test('DELETE 200 but server still returns data → NOT marked synced',
        () async {
      await seedSavedWords(3);
      // Server "loses" the delete: GET keeps returning a non-empty list.
      api.getResponder = (path) =>
          path.contains('saved-words') ? const [{'id': 'ghost'}] : const [];

      final ok = await savedWordsRepo.clearAll();
      expect(ok, isFalse, reason: 'verify must fail when data persists');
      expect(prefs.getBool('pending_clear_saved_words'), isTrue);
      // 3 delete attempts were made (verify failed each time).
      expect(api.attemptsFor('DELETE', anySavedWordsPath(api)), 3);
    });

    test('transient DELETE failure recovers within the retry budget', () async {
      await seedSavedWords(2);
      // Fail first two delete attempts, succeed the third; verify is empty.
      api.failRule = (method, path, attempt) =>
          method == 'DELETE' && path.contains('saved-words') && attempt < 3;

      final ok = await savedWordsRepo.clearAll();
      expect(ok, isTrue, reason: 'third attempt succeeds');
      expect(prefs.getBool('pending_clear_saved_words'), isNot(true));
    });

    test('partial cloud outage: only the failing domain is queued', () async {
      await database.batch((b) {
        b.insert(database.expenses,
            db.ExpensesCompanion.insert(id: 'e1', amount: 1, description: 'd', category: 'Food', bank: 'H', cardType: 'CC', date: '2026-06-01T00:00:00.000Z'));
        b.insert(database.budgetEntries,
            db.BudgetEntriesCompanion.insert(id: 'b1', amount: 1, setAt: '2026-06-01T00:00:00.000Z'));
        b.insert(database.salaryEntries,
            db.SalaryEntriesCompanion.insert(id: 's1', month: '2026-06', amount: 1, setAt: '2026-06-01T00:00:00.000Z'));
        b.insert(database.savedWords,
            db.SavedWordsCompanion.insert(id: 'w1', word: 'w', definition: 'd', pronunciation: '', partOfSpeech: 'n', savedAt: '2026-06-01T00:00:00.000Z'));
      });

      // Only the expenses DELETE fails — everything else clears cleanly.
      api.failRule = (method, path, _) =>
          method == 'DELETE' && path.endsWith('/expenses');

      final report = await buildAppNuke().nuke();

      lineFor(String l) => report.lines.firstWhere((x) => x.label == l);
      expect(lineFor('Expenses').cloudSynced, isFalse);
      expect(lineFor('Budget history').cloudSynced, isTrue);
      expect(lineFor('Salary').cloudSynced, isTrue);
      expect(lineFor('Saved words').cloudSynced, isTrue);
      expect(report.fullySynced, isFalse);

      // Local wipe is total regardless of the cloud outage.
      final after = await database.dataRowCounts();
      expect(after.values.every((c) => c == 0), isTrue);

      // Exactly the failed domain is flagged for retry.
      expect(prefs.getBool('pending_clear_expenses'), isTrue);
      expect(prefs.getBool('pending_clear_budget'), isNot(true));
      expect(prefs.getBool('pending_clear_saved_words'), isNot(true));
    });

    test('full nuke survives a THROWING cloud step (guarded, no crash)',
        () async {
      await seedExpenses(5);
      savedSearchThrows = true; // injected clear blows up

      final report = await buildAppNuke().nuke();

      expect(savedSearchCalls, 1);
      expect(report.lines.firstWhere((l) => l.label == 'Saved searches').cloudSynced, isFalse);
      expect(report.fullySynced, isFalse);
      final after = await database.dataRowCounts();
      expect(after.values.every((c) => c == 0), isTrue,
          reason: 'a throwing cloud step never blocks the local wipe');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  //  CONCURRENCY
  // ═══════════════════════════════════════════════════════════════════════════

  group('Concurrency', () {
    test('two simultaneous full nukes are safe and idempotent', () async {
      await seedExpenses(500);
      await seedSavedWords(200);

      final results = await Future.wait([
        buildAppNuke().nuke(),
        buildAppNuke().nuke(),
      ]);

      expect(results, hasLength(2));
      final after = await database.dataRowCounts();
      expect(after.values.every((c) => c == 0), isTrue);
    });

    test('concurrent enqueue of the same key still collapses to one row',
        () async {
      await Future.wait([
        for (var i = 0; i < 25; i++)
          database.enqueueSync(
            entityType: 'salary',
            entityId: '2026-06',
            action: 'upsert',
            payload: salaryPayload('2026-06', 100 + i.toDouble()),
          ),
      ]);
      expect(await database.pendingSyncItems('salary'), hasLength(1));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  //  SavedSearchStore.clearAllRemote — offline self-heal
  // ═══════════════════════════════════════════════════════════════════════════

  group('SavedSearchStore.clearAllRemote', () {
    setUp(() {
      SavedSearchStore.debugDisablePeriodicSync = true;
      SavedSearchStore.instance.debugResetForTests();
    });
    tearDown(() {
      SavedSearchStore.instance.debugResetForTests();
      SavedSearchStore.debugDisablePeriodicSync = false;
    });

    test('offline clear flags pending, then self-heals on startup', () async {
      final store = SavedSearchStore.instance;
      store.init(database, api);

      // Server unreachable for the bulk clear.
      api.failRule = (method, path, _) =>
          method == 'DELETE' && path.contains('saved-searches');

      final ok = await store.clearAllRemote();
      expect(ok, isFalse);
      expect(prefs.getBool('savedSearchStore.pendingFullClear'), isTrue);

      // Reconnect → explicit cold-start hook finishes the server clear.
      api.failRule = null;
      await store.retryPendingFullClearOnStartup();
      expect(prefs.getBool('savedSearchStore.pendingFullClear'), isNot(true));
      expect(api.deletes.where((p) => p.contains('saved-searches')), isNotEmpty);
    });

    test('online clear succeeds immediately with no pending flag', () async {
      final store = SavedSearchStore.instance;
      store.init(database, api);

      final ok = await store.clearAllRemote();
      expect(ok, isTrue);
      expect(prefs.getBool('savedSearchStore.pendingFullClear'), isNot(true));
    });
  });
}

/// The full saved-words endpoint path, as the repo builds it — used so the
/// attempt-count assertion keys on the exact path the fake recorded.
String anySavedWordsPath(_ProgApi api) =>
    api.deletes.firstWhere((p) => p.contains('saved-words'),
        orElse: () => 'http://localhost:3000/api/v1/saved-words');
