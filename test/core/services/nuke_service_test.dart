// Deep, hermetic tests for the "nuke" easter-egg engines:
//   • ExpenseNukeService — expense-scope reset (expenses + budget + salary).
//   • AppNukeService      — full-app reset (every local table + financial cloud).
//   • NukeReport          — the UI-facing summary model.
//
// Everything runs against a REAL in-memory Drift DB with a controllable fake
// ApiClient + mock SharedPreferences, so the local-first wipe, the cloud
// DELETE/retry/verify path, the offline pending-flag self-heal, and the
// crash-proof guarding are all exercised end-to-end exactly as in production.

import 'package:ai_nexus/core/network/api_client.dart';
import 'package:ai_nexus/core/services/app_nuke_service.dart';
import 'package:ai_nexus/core/services/expense_nuke_service.dart';
import 'package:ai_nexus/core/services/nuke_report.dart';
import 'package:ai_nexus/core/services/reset_sync_service.dart';
import 'package:ai_nexus/data/local/database/app_database.dart' as db;
import 'package:ai_nexus/data/repositories/expense_repository.dart';
import 'package:ai_nexus/data/repositories/news_repository.dart';
import 'package:ai_nexus/data/repositories/salary_repository.dart';
import 'package:ai_nexus/data/repositories/saved_words_repository.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeApi extends ApiClient {
  _FakeApi();

  /// HTTP verbs that should throw a connection error (simulate offline backend).
  final Set<String> failMethods = <String>{};

  /// Optional override for GET responses (used by clear-verification reads).
  Object? Function(String path)? onGet;

  final List<String> deletes = <String>[];
  final List<({String path, Object? data})> posts =
      <({String path, Object? data})>[];

  Response<T> _resp<T>(String path, Object? data) => Response<T>(
        requestOptions: RequestOptions(path: path),
        data: data as T?,
        statusCode: 200,
      );

  Never _throwOffline(String path) => throw DioException(
        requestOptions: RequestOptions(path: path),
        type: DioExceptionType.connectionError,
        message: 'fake offline',
      );

  @override
  Future<Response<T>> get<T>(String path,
      {Map<String, dynamic>? queryParameters}) async {
    if (failMethods.contains('GET')) _throwOffline(path);
    return _resp<T>(path, onGet?.call(path) ?? const <dynamic>[]);
  }

  @override
  Future<Response<T>> post<T>(String path,
      {Object? data, Options? options, CancelToken? cancelToken}) async {
    if (failMethods.contains('POST')) _throwOffline(path);
    posts.add((path: path, data: data));
    return _resp<T>(path, null);
  }

  @override
  Future<Response<T>> delete<T>(String path) async {
    if (failMethods.contains('DELETE')) _throwOffline(path);
    deletes.add(path);
    return _resp<T>(path, null);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late db.AppDatabase database;
  late _FakeApi api;
  late ExpenseRepository expenseRepo;
  late SalaryRepository salaryRepo;
  late SavedWordsRepository savedWordsRepo;
  late ResetSyncService resetSync;

  // Records calls to the injected saved-searches clear so the nuke wiring can
  // be asserted; honours the offline flag to mirror a real server outage.
  var savedSearchCleared = 0;
  late Future<bool> Function() clearSavedSearches;

  AppNukeService buildAppNuke() => AppNukeService(
        database,
        expenseRepo,
        salaryRepo,
        savedWordsRepo,
        NewsRepository(database, api),
        resetSync,
        clearSavedSearches: clearSavedSearches,
      );

  ExpenseNukeService buildExpenseNuke() =>
      ExpenseNukeService(expenseRepo, salaryRepo, resetSync);

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    database = db.AppDatabase.forTesting(NativeDatabase.memory());
    api = _FakeApi();
    expenseRepo = ExpenseRepository(database, api, prefs);
    salaryRepo = SalaryRepository(database, api, prefs);
    savedWordsRepo = SavedWordsRepository(database, api, prefs);
    resetSync = ResetSyncService(database, api, prefs);
    savedSearchCleared = 0;
    clearSavedSearches = () async {
      savedSearchCleared++;
      return !api.failMethods.contains('DELETE');
    };
    // Verify reads always see an empty server by default.
    api.onGet = (_) => const <dynamic>[];
  });

  tearDown(() async {
    // Some tests deliberately close the DB to simulate a catastrophic failure;
    // closing twice would throw, so tolerate it here.
    try {
      await database.close();
    } catch (_) {/* already closed by the test */}
  });

  // ── Seed helpers ───────────────────────────────────────────────────────────

  Future<void> addExpense(String id, double amount) =>
      database.into(database.expenses).insert(
            db.ExpensesCompanion.insert(
              id: id,
              amount: amount,
              description: 'desc-$id',
              category: 'Food',
              bank: 'HDFC',
              cardType: 'CC',
              date: '2026-06-26T10:00:00.000Z',
            ),
          );

  Future<void> addBudget(String id, double amount) =>
      database.into(database.budgetEntries).insert(
            db.BudgetEntriesCompanion.insert(
              id: id,
              amount: amount,
              setAt: '2026-06-01T00:00:00.000Z',
            ),
          );

  Future<void> addSalary(String month, double amount) =>
      database.into(database.salaryEntries).insert(
            db.SalaryEntriesCompanion.insert(
              month: month,
              id: 'sal-$month',
              amount: amount,
              setAt: '2026-06-01T00:00:00.000Z',
            ),
          );

  Future<void> addSavedWord(String id) =>
      database.into(database.savedWords).insert(
            db.SavedWordsCompanion.insert(
              id: id,
              word: 'word-$id',
              definition: 'def',
              pronunciation: '',
              partOfSpeech: 'noun',
              savedAt: '2026-06-26T10:00:00.000Z',
            ),
          );

  Future<void> addLearning(String keyword) =>
      database.into(database.categoryLearnings).insert(
            db.CategoryLearningsCompanion.insert(
              keyword: keyword,
              category: 'Food',
            ),
          );

  NukeLine lineFor(NukeReport r, String label) =>
      r.lines.firstWhere((l) => l.label == label);

  // ═══════════════════════════════════════════════════════════════════════════
  //  ExpenseNukeService
  // ═══════════════════════════════════════════════════════════════════════════

  group('ExpenseNukeService', () {
    test('clears financial domains locally + cloud, reports synced', () async {
      await addExpense('e1', 100);
      await addExpense('e2', 200);
      await addExpense('e3', 300);
      await addBudget('b1', 5000);
      await addBudget('b2', 6000);
      await addSalary('2026-06', 80000);

      final report = await buildExpenseNuke().nuke();

      expect(report.scope, NukeScope.expense);
      expect(report.lines, hasLength(3));
      expect(lineFor(report, 'Expenses').count, 3);
      expect(lineFor(report, 'Budget history').count, 2);
      expect(lineFor(report, 'Salary').count, 1);
      expect(report.totalCleared, 6);
      expect(report.fullySynced, isTrue);
      expect(report.lines.every((l) => l.cloudSynced == true), isTrue);

      // Local tables emptied.
      expect((await expenseRepo.rangeSummary()).count, 0);
      expect(await expenseRepo.getBudget(), 0);
      expect(await salaryRepo.salaryCount(), 0);

      // Each domain issued exactly one server DELETE.
      expect(api.deletes.where((p) => p.contains('expenses')), isNotEmpty);
      expect(api.deletes.where((p) => p.contains('budget')), isNotEmpty);
      expect(api.deletes.where((p) => p.contains('salary')), isNotEmpty);
    });

    test('offline: local wiped, cloud QUEUED, pending flags set for retry',
        () async {
      await addExpense('e1', 100);
      await addBudget('b1', 5000);
      await addSalary('2026-06', 80000);
      api.failMethods.add('DELETE');

      final report = await buildExpenseNuke().nuke();

      // Counts are still captured (snapshot happens before the wipe).
      expect(report.totalCleared, 3);
      // Nothing synced; every line is queued.
      expect(report.fullySynced, isFalse);
      expect(report.lines.every((l) => l.cloudSynced == false), isTrue);

      // Local is still wiped (local-first) despite the cloud outage.
      expect((await expenseRepo.rangeSummary()).count, 0);
      expect(await salaryRepo.salaryCount(), 0);

      // Pending-retry flags persisted so a later launch self-heals.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('pending_clear_expenses'), isTrue);
      expect(prefs.getBool('pending_clear_budget'), isTrue);
      expect(prefs.getBool('pending_clear_salary'), isTrue);
    });

    test('empty domain nuke is safe and reports nothing to clear', () async {
      final report = await buildExpenseNuke().nuke();
      expect(report.totalCleared, 0);
      expect(report.nonEmptyLines, isEmpty);
      // Deleting an empty server still "succeeds", so it reads as synced.
      expect(report.fullySynced, isTrue);
    });

    test('survives a catastrophic local failure without crashing', () async {
      await addExpense('e1', 100);
      await database.close(); // every DB op now throws

      // Must NOT throw — the service guards every step.
      final report = await buildExpenseNuke().nuke();
      expect(report.scope, NukeScope.expense);
      // Local deletes failed → guarded → not synced, but no crash.
      expect(report.fullySynced, isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  //  AppNukeService (full reset)
  // ═══════════════════════════════════════════════════════════════════════════

  group('AppNukeService', () {
    test('wipes EVERY local table + clears ALL re-hydrating cloud domains',
        () async {
      await addExpense('e1', 100);
      await addExpense('e2', 200);
      await addBudget('b1', 5000);
      await addSalary('2026-06', 80000);
      await addSavedWord('w1');
      await addSavedWord('w2');
      await addLearning('swiggy');

      final report = await buildAppNuke().nuke();

      expect(report.scope, NukeScope.full);

      // Financial domains: real counts + confirmed cloud sync.
      expect(lineFor(report, 'Expenses').count, 2);
      expect(lineFor(report, 'Expenses').cloudSynced, isTrue);
      expect(lineFor(report, 'Budget history').count, 1);
      expect(lineFor(report, 'Salary').count, 1);

      // Saved words + learnings are NOW cloud-backed (the reappear-bug fix):
      // they must report a confirmed server clear, not a local-only null.
      expect(lineFor(report, 'Saved words').count, 2);
      expect(lineFor(report, 'Saved words').cloudSynced, isTrue);
      expect(lineFor(report, 'Learnings').count, 1);
      expect(lineFor(report, 'Learnings').cloudSynced, isTrue);

      // Saved searches cloud clear was invoked + reported synced.
      expect(savedSearchCleared, 1);
      expect(lineFor(report, 'Saved searches').cloudSynced, isTrue);

      // News is NOW cloud-cleared too (unified with the dedicated nuke
      // command): it must report a confirmed server clear, not local-only null.
      expect(lineFor(report, 'News').cloudSynced, isTrue);
      // Cloud files stay genuinely local-only (Drive metadata — no cloud badge).
      expect(lineFor(report, 'Cloud files').cloudSynced, isNull);

      expect(report.fullySynced, isTrue);

      // Saved words actually hit the server DELETE (so they can't re-hydrate).
      expect(api.deletes.where((p) => p.contains('saved-words')), isNotEmpty);
      expect(
          api.deletes.where((p) => p.contains('category-learnings')), isNotEmpty);

      // The full nuke also fired the server-side news wipe (POST /news/nuke).
      expect(api.posts.where((p) => p.path.contains('news/nuke')), isNotEmpty);

      // EVERY data table is now empty — schema preserved.
      final after = await database.dataRowCounts();
      expect(after.values.every((c) => c == 0), isTrue,
          reason: 'full nuke leaves zero rows across all tables');

      // The DB is still usable (no table was dropped).
      await addExpense('e3', 9);
      expect((await database.select(database.expenses).get()).length, 1);
    });

    test('offline: local fully wiped, EVERY cloud domain QUEUED + pending flags',
        () async {
      await addExpense('e1', 100);
      await addBudget('b1', 5000);
      await addSalary('2026-06', 80000);
      await addSavedWord('w1');
      await addLearning('swiggy');
      api.failMethods.add('DELETE');

      final report = await buildAppNuke().nuke();

      // Local wipe is independent of the cloud and always lands.
      final after = await database.dataRowCounts();
      expect(after.values.every((c) => c == 0), isTrue);

      // Every cloud-backed line queued.
      expect(lineFor(report, 'Expenses').cloudSynced, isFalse);
      expect(lineFor(report, 'Budget history').cloudSynced, isFalse);
      expect(lineFor(report, 'Salary').cloudSynced, isFalse);
      expect(lineFor(report, 'Saved words').cloudSynced, isFalse);
      expect(lineFor(report, 'Learnings').cloudSynced, isFalse);
      expect(lineFor(report, 'Saved searches').cloudSynced, isFalse);
      expect(report.fullySynced, isFalse);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('pending_clear_expenses'), isTrue);
      expect(prefs.getBool('pending_clear_budget'), isTrue);
      expect(prefs.getBool('pending_clear_salary'), isTrue);
      expect(prefs.getBool('pending_clear_saved_words'), isTrue);
      expect(prefs.getBool('pending_clear_learnings'), isTrue);

      // …and the pending saved-words clear self-heals once back online.
      api.failMethods.remove('DELETE');
      await savedWordsRepo.retryPendingClear();
      expect(prefs.getBool('pending_clear_saved_words'), isNot(true));
    });

    test('full nuke on a pristine DB reports nothing + stays synced', () async {
      final report = await buildAppNuke().nuke();
      expect(report.totalCleared, 0);
      expect(report.nonEmptyLines, isEmpty);
      expect(report.fullySynced, isTrue);
    });

    test('idempotent — a second full nuke immediately after is a clean no-op',
        () async {
      await addExpense('e1', 100);
      await buildAppNuke().nuke();
      final second = await buildAppNuke().nuke();
      expect(second.totalCleared, 0);
      expect(second.fullySynced, isTrue);
      final after = await database.dataRowCounts();
      expect(after.values.every((c) => c == 0), isTrue);
    });

    test('large dataset wipes completely (no scaling/partial-clear issue)',
        () async {
      await database.batch((b) {
        for (var i = 0; i < 2000; i++) {
          b.insert(
            database.expenses,
            db.ExpensesCompanion.insert(
              id: 'e$i',
              amount: i.toDouble(),
              description: 'd$i',
              category: 'Food',
              bank: 'HDFC',
              cardType: 'CC',
              date: '2026-06-26T10:00:00.000Z',
            ),
          );
        }
      });

      final report = await buildAppNuke().nuke();

      expect(lineFor(report, 'Expenses').count, 2000);
      final after = await database.dataRowCounts();
      expect(after['Expenses'], 0, reason: 'all 2000 rows removed');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  //  SavedWordsRepository — cloud clear (the "saved words came back" fix)
  // ═══════════════════════════════════════════════════════════════════════════

  group('SavedWordsRepository.clearAll', () {
    test('clears local + server, no pending flag on success', () async {
      await addSavedWord('w1');
      await addSavedWord('w2');

      final ok = await savedWordsRepo.clearAll();
      expect(ok, isTrue);
      expect(await savedWordsRepo.count(), 0);
      expect(api.deletes.where((p) => p.contains('saved-words')), isNotEmpty);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('pending_clear_saved_words'), isNot(true));
    });

    test('offline: local cleared, pending flag set, retry resolves', () async {
      await addSavedWord('w1');
      api.failMethods.add('DELETE');

      final ok = await savedWordsRepo.clearAll();
      expect(ok, isFalse);
      expect(await savedWordsRepo.count(), 0, reason: 'local is cleared anyway');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('pending_clear_saved_words'), isTrue);

      api.failMethods.remove('DELETE');
      await savedWordsRepo.retryPendingClear();
      expect(prefs.getBool('pending_clear_saved_words'), isNot(true));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  //  ExpenseRepository.clearLearnings
  // ═══════════════════════════════════════════════════════════════════════════

  group('ExpenseRepository.clearLearnings', () {
    test('clears local + server', () async {
      await addLearning('swiggy');
      await addLearning('uber');
      expect(await expenseRepo.learningsCount(), 2);

      final ok = await expenseRepo.clearLearnings();
      expect(ok, isTrue);
      expect(await expenseRepo.learningsCount(), 0);
      expect((await expenseRepo.getLearnings()), isEmpty);
    });

    test('offline: pending flag set + cleared by retryPendingClears', () async {
      await addLearning('swiggy');
      api.failMethods.add('DELETE');
      final ok = await expenseRepo.clearLearnings();
      expect(ok, isFalse);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('pending_clear_learnings'), isTrue);

      api.failMethods.remove('DELETE');
      await expenseRepo.retryPendingClears();
      expect(prefs.getBool('pending_clear_learnings'), isNot(true));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  //  Salary durable SyncQueue (offline-first write durability)
  // ═══════════════════════════════════════════════════════════════════════════

  group('Salary SyncQueue', () {
    test('online write does NOT queue (inline push wins)', () async {
      final ok = await salaryRepo.setSalaryForMonth('2026-06', 80000);
      expect(ok, isTrue);
      expect(await database.pendingSyncItems('salary'), isEmpty);
    });

    test('offline write is queued durably, then drains on reconnect', () async {
      api.failMethods.add('POST');
      final ok = await salaryRepo.setSalaryForMonth('2026-06', 80000);
      expect(ok, isFalse, reason: 'inline push failed → queued');

      // Persisted to the durable outbox (survives an app kill).
      final queued = await database.pendingSyncItems('salary');
      expect(queued, hasLength(1));
      expect(queued.single.entityId, '2026-06');

      // Reconnect → drain pushes it and clears the queue.
      api.failMethods.remove('POST');
      final drained = await salaryRepo.drainSyncQueue();
      expect(drained, 1);
      expect(await database.pendingSyncItems('salary'), isEmpty);
      expect(api.posts.where((p) => p.path.contains('salary')), isNotEmpty);
    });

    test('re-saving the same month offline collapses to ONE queued entry',
        () async {
      api.failMethods.add('POST');
      await salaryRepo.setSalaryForMonth('2026-06', 50000);
      await salaryRepo.setSalaryForMonth('2026-06', 90000);

      final queued = await database.pendingSyncItems('salary');
      expect(queued, hasLength(1), reason: 'latest write replaces the prior');
    });

    test('clearing salary purges queued writes (no resurrection)', () async {
      api.failMethods.add('POST');
      await salaryRepo.setSalaryForMonth('2026-06', 50000);
      expect(await database.pendingSyncItems('salary'), hasLength(1));

      api.failMethods.remove('POST');
      await salaryRepo.clearSalaryHistory();
      expect(await database.pendingSyncItems('salary'), isEmpty,
          reason: 'a stale queued upsert must not resurrect a cleared salary');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  //  NukeReport model
  // ═══════════════════════════════════════════════════════════════════════════

  group('NukeReport', () {
    const lines = [
      NukeLine(label: 'Expenses', emoji: '💸', count: 5, cloudSynced: true),
      NukeLine(label: 'Empty', emoji: '📦', count: 0, cloudSynced: false),
      NukeLine(label: 'Local', emoji: '📰', count: 3),
    ];
    const report = NukeReport(
      scope: NukeScope.full,
      lines: lines,
      fullySynced: false,
      elapsedMs: 42,
    );

    test('totalCleared sums every line (including zero-count)', () {
      expect(report.totalCleared, 8);
    });

    test('nonEmptyLines drops zero-count rows only', () {
      expect(report.nonEmptyLines.map((l) => l.label), ['Expenses', 'Local']);
    });
  });
}
