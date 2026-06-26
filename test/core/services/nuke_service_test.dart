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
import 'package:ai_nexus/data/local/database/app_database.dart' as db;
import 'package:ai_nexus/data/repositories/expense_repository.dart';
import 'package:ai_nexus/data/repositories/salary_repository.dart';
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

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    database = db.AppDatabase.forTesting(NativeDatabase.memory());
    api = _FakeApi();
    expenseRepo = ExpenseRepository(database, api, prefs);
    salaryRepo = SalaryRepository(database, api, prefs);
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

      final report = await ExpenseNukeService(expenseRepo, salaryRepo).nuke();

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

      final report = await ExpenseNukeService(expenseRepo, salaryRepo).nuke();

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
      final report = await ExpenseNukeService(expenseRepo, salaryRepo).nuke();
      expect(report.totalCleared, 0);
      expect(report.nonEmptyLines, isEmpty);
      // Deleting an empty server still "succeeds", so it reads as synced.
      expect(report.fullySynced, isTrue);
    });

    test('survives a catastrophic local failure without crashing', () async {
      await addExpense('e1', 100);
      await database.close(); // every DB op now throws

      // Must NOT throw — the service guards every step.
      final report = await ExpenseNukeService(expenseRepo, salaryRepo).nuke();
      expect(report.scope, NukeScope.expense);
      // Local deletes failed → guarded → not synced, but no crash.
      expect(report.fullySynced, isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  //  AppNukeService (full reset)
  // ═══════════════════════════════════════════════════════════════════════════

  group('AppNukeService', () {
    test('wipes EVERY local table + syncs financial cloud', () async {
      await addExpense('e1', 100);
      await addExpense('e2', 200);
      await addBudget('b1', 5000);
      await addSalary('2026-06', 80000);
      await addSavedWord('w1');
      await addSavedWord('w2');
      await addLearning('swiggy');

      final report =
          await AppNukeService(database, expenseRepo, salaryRepo).nuke();

      expect(report.scope, NukeScope.full);

      // Financial domains: real counts + confirmed cloud sync.
      expect(lineFor(report, 'Expenses').count, 2);
      expect(lineFor(report, 'Expenses').cloudSynced, isTrue);
      expect(lineFor(report, 'Budget history').count, 1);
      expect(lineFor(report, 'Salary').count, 1);

      // Local-only domains: real counts + no cloud badge (null).
      expect(lineFor(report, 'Saved words').count, 2);
      expect(lineFor(report, 'Saved words').cloudSynced, isNull);
      expect(lineFor(report, 'Learnings').count, 1);
      expect(lineFor(report, 'Learnings').cloudSynced, isNull);

      expect(report.fullySynced, isTrue);

      // EVERY data table is now empty — schema preserved.
      final after = await database.dataRowCounts();
      expect(after.values.every((c) => c == 0), isTrue,
          reason: 'full nuke leaves zero rows across all tables');

      // The DB is still usable (no table was dropped).
      await addExpense('e3', 9);
      expect((await database.select(database.expenses).get()).length, 1);
    });

    test('offline: local fully wiped, financial cloud QUEUED + pending flags',
        () async {
      await addExpense('e1', 100);
      await addBudget('b1', 5000);
      await addSalary('2026-06', 80000);
      await addSavedWord('w1');
      api.failMethods.add('DELETE');

      final report =
          await AppNukeService(database, expenseRepo, salaryRepo).nuke();

      // Local wipe is independent of the cloud and always lands.
      final after = await database.dataRowCounts();
      expect(after.values.every((c) => c == 0), isTrue);

      // Financial lines queued; local-only lines unaffected (null).
      expect(lineFor(report, 'Expenses').cloudSynced, isFalse);
      expect(lineFor(report, 'Budget history').cloudSynced, isFalse);
      expect(lineFor(report, 'Salary').cloudSynced, isFalse);
      expect(lineFor(report, 'Saved words').cloudSynced, isNull);
      expect(report.fullySynced, isFalse);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('pending_clear_expenses'), isTrue);
      expect(prefs.getBool('pending_clear_budget'), isTrue);
      expect(prefs.getBool('pending_clear_salary'), isTrue);
    });

    test('full nuke on a pristine DB reports nothing + stays synced', () async {
      final report =
          await AppNukeService(database, expenseRepo, salaryRepo).nuke();
      expect(report.totalCleared, 0);
      expect(report.nonEmptyLines, isEmpty);
      expect(report.fullySynced, isTrue);
    });

    test('idempotent — a second full nuke immediately after is a clean no-op',
        () async {
      await addExpense('e1', 100);
      await AppNukeService(database, expenseRepo, salaryRepo).nuke();
      final second =
          await AppNukeService(database, expenseRepo, salaryRepo).nuke();
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

      final report =
          await AppNukeService(database, expenseRepo, salaryRepo).nuke();

      expect(lineFor(report, 'Expenses').count, 2000);
      final after = await database.dataRowCounts();
      expect(after['Expenses'], 0, reason: 'all 2000 rows removed');
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
