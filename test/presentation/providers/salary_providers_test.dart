// Deep integration + scaling tests for the salary providers wired over a REAL
// in-memory Drift DB and the REAL repositories (only the network ApiClient is
// faked). Proves:
//   • salaryStatsProvider correctly blends salary + budget + DB-aggregated spend
//   • the DB-aggregated month spend is reactive and excludes other months
//   • previous-month selection (for hike %) picks the most-recent older month
//   • watchMonthTotal stays correct and fast on a large (25k row) history.

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ai_nexus/core/di/injection.dart';
import 'package:ai_nexus/core/network/api_client.dart';
import 'package:ai_nexus/data/local/database/app_database.dart' as db;
import 'package:ai_nexus/domain/entities/expense_entities.dart';
import 'package:ai_nexus/presentation/providers/salary_providers.dart';
import 'package:ai_nexus/presentation/screens/expense/expense_screen.dart'
    show budgetHistoryStreamProvider;

class _FakeApi extends ApiClient {
  _FakeApi();
  Response<T> _r<T>(String p, Object? d) => Response<T>(
      requestOptions: RequestOptions(path: p), data: d as T?, statusCode: 200);
  @override
  Future<Response<T>> get<T>(String path,
          {Map<String, dynamic>? queryParameters}) async =>
      _r<T>(path, <dynamic>[]);
  @override
  Future<Response<T>> post<T>(String path,
          {Object? data, Options? options, CancelToken? cancelToken}) async =>
      _r<T>(path, <String, dynamic>{'ok': true});
  @override
  Future<Response<T>> put<T>(String path, {Object? data}) async =>
      _r<T>(path, <String, dynamic>{});
  @override
  Future<Response<T>> delete<T>(String path) async =>
      _r<T>(path, <String, dynamic>{'ok': true});
}

String _monthKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late db.AppDatabase database;
  late ProviderContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    database = db.AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(database),
      apiClientProvider.overrideWithValue(_FakeApi()),
      sharedPreferencesProvider.overrideWithValue(prefs),
    ]);
  });

  tearDown(() async {
    container.dispose();
    await database.close();
  });

  Future<void> warmUp() async {
    // Subscribe so the plain salaryStatsProvider sees live stream values.
    container.listen(salaryStatsProvider, (_, __) {});
    await container.read(salaryHistoryStreamProvider.future);
    await container.read(budgetHistoryStreamProvider.future);
    await container.read(currentMonthSpentProvider.future);
  }

  test('stats blend salary + budget + DB-aggregated current-month spend',
      () async {
    final now = DateTime.now();
    final cur = _monthKey(now);

    await container
        .read(salaryRepositoryProvider)
        .setSalaryForMonth(cur, 100000);
    await container.read(expenseRepositoryProvider).setBudget(60000);

    final exp = container.read(expenseRepositoryProvider);
    // 20k this month (counts), 5k LAST month (must be excluded).
    await exp.addExpense(Expense(
      id: 'cur1',
      amount: 20000,
      description: 'rent',
      category: 'Bills',
      bank: 'HDFC',
      cardType: 'CC',
      date: '$cur-10T10:00:00.000',
      isManualCategory: false,
    ));
    final lastMonth = _monthKey(DateTime(now.year, now.month - 1, 15));
    await exp.addExpense(Expense(
      id: 'old1',
      amount: 5000,
      description: 'old',
      category: 'Food',
      bank: 'HDFC',
      cardType: 'CC',
      date: '$lastMonth-15T10:00:00.000',
      isManualCategory: false,
    ));

    await warmUp();
    // Allow the reactive aggregate to settle after the inserts.
    await container.read(currentMonthSpentProvider.future);

    final stats = container.read(salaryStatsProvider);
    expect(stats.salary, 100000);
    expect(stats.budget, 60000);
    expect(stats.spent, 20000, reason: 'only current month counted');
    expect(stats.savedPct, 80);
    expect(stats.budgetUsedPct, closeTo(33.33, 0.1));
    expect(stats.isOverBudget, isFalse);
    expect(stats.healthScore, greaterThan(0));
  });

  test('previous-month selection picks the most-recent older month (hike %)',
      () async {
    final now = DateTime.now();
    final cur = _monthKey(now);
    final prev1 = _monthKey(DateTime(now.year, now.month - 1, 1));
    final prev2 = _monthKey(DateTime(now.year, now.month - 2, 1));

    final salary = container.read(salaryRepositoryProvider);
    await salary.setSalaryForMonth(prev2, 80000);
    await salary.setSalaryForMonth(prev1, 90000);
    await salary.setSalaryForMonth(cur, 100000);

    await warmUp();
    final stats = container.read(salaryStatsProvider);
    expect(stats.previousSalary, 90000, reason: 'most recent older month');
    expect(stats.hikePct, closeTo(11.111, 0.01));
    expect(stats.monthsRecorded, 3);
    expect(stats.highestSalary, 100000);
    expect(stats.totalRecorded, 270000);
  });

  test('no salary entered → empty-ish stats, no divide-by-zero', () async {
    await warmUp();
    final stats = container.read(salaryStatsProvider);
    expect(stats.hasSalary, isFalse);
    expect(stats.salary, 0);
    expect(stats.spentPct, 0);
    expect(stats.healthScore, 0);
  });

  test('currentMonthSpent is reactive — re-emits when a new expense lands',
      () async {
    final now = DateTime.now();
    final cur = _monthKey(now);
    await warmUp();
    expect(container.read(currentMonthSpentProvider).valueOrNull ?? 0, 0);

    // Wait for the watch() to push the new aggregate after the insert.
    final completer = Completer<double>();
    final sub = container.listen(currentMonthSpentProvider, (_, next) {
      next.whenData((v) {
        if (v == 1234 && !completer.isCompleted) completer.complete(v);
      });
    });

    await container.read(expenseRepositoryProvider).addExpense(Expense(
          id: 'r1',
          amount: 1234,
          description: 'snacks',
          category: 'Food',
          bank: 'CASH',
          cardType: 'Cash',
          date: '$cur-05T08:00:00.000',
          isManualCategory: false,
        ));

    final updated =
        await completer.future.timeout(const Duration(seconds: 3));
    sub.close();
    expect(updated, 1234);
  });

  test('credit-card forecast flows end-to-end through salaryStatsProvider',
      () async {
    final now = DateTime.now();
    final cur = _monthKey(now);
    final lastMonth = _monthKey(DateTime(now.year, now.month - 1, 15));

    await container.read(salaryRepositoryProvider).setSalaryForMonth(cur, 100000);

    final exp = container.read(expenseRepositoryProvider);
    // This month: ₹25k on CC (→ next month's bill) + ₹8k on DB (must NOT count).
    await exp.addExpense(Expense(
      id: 'cc-now',
      amount: 25000,
      description: 'laptop',
      category: 'Electronics',
      bank: 'HDFC',
      cardType: 'CC',
      date: '$cur-08T10:00:00.000',
      isManualCategory: false,
    ));
    await exp.addExpense(Expense(
      id: 'db-now',
      amount: 8000,
      description: 'groceries',
      category: 'Grocery',
      bank: 'HDFC',
      cardType: 'DB',
      date: '$cur-09T10:00:00.000',
      isManualCategory: false,
    ));
    // Last month: ₹18k on CC → the bill due (and repaid) THIS month.
    await exp.addExpense(Expense(
      id: 'cc-last',
      amount: 18000,
      description: 'flights',
      category: 'Travel',
      bank: 'HDFC',
      cardType: 'CC',
      date: '$lastMonth-20T10:00:00.000',
      isManualCategory: false,
    ));

    // Subscribe so the CC stream provider stays alive + settles.
    container.listen(ccMonthlyTotalsProvider, (_, __) {});
    await warmUp();
    await container.read(ccMonthlyTotalsProvider.future);

    final stats = container.read(salaryStatsProvider);
    expect(stats.ccSpentThisMonth, 25000, reason: 'only this-month CC charges');
    expect(stats.ccDueThisMonth, 18000, reason: 'last-month CC bill due now');
    expect(stats.forecastNextMonthTakeHome, 75000); // 100k - 25k
    expect(stats.effectiveTakeHomeThisMonth, 82000); // 100k - 18k
    expect(stats.ccPctOfSalary, closeTo(25, 0.0001));
    expect(stats.hasCreditCardActivity, isTrue);
  });

  test('credit-card stream is reactive — forecast updates when a CC swipe lands',
      () async {
    final now = DateTime.now();
    final cur = _monthKey(now);
    await container.read(salaryRepositoryProvider).setSalaryForMonth(cur, 50000);

    container.listen(ccMonthlyTotalsProvider, (_, __) {});
    container.listen(salaryStatsProvider, (_, __) {});
    await warmUp();
    await container.read(ccMonthlyTotalsProvider.future);
    expect(container.read(salaryStatsProvider).ccSpentThisMonth, 0);

    final completer = Completer<double>();
    final sub = container.listen(ccMonthlyTotalsProvider, (_, next) {
      next.whenData((m) {
        final v = m[cur] ?? 0;
        if (v >= 12000 && !completer.isCompleted) completer.complete(v);
      });
    });

    await container.read(expenseRepositoryProvider).addExpense(Expense(
          id: 'cc-live',
          amount: 12000,
          description: 'tv',
          category: 'Electronics',
          bank: 'HDFC',
          cardType: 'CC',
          date: '$cur-11T10:00:00.000',
          isManualCategory: false,
        ));

    await completer.future.timeout(const Duration(seconds: 3));
    sub.close();
    // The blended stats now reflect the new card bill → reduced forecast.
    final stats = container.read(salaryStatsProvider);
    expect(stats.ccSpentThisMonth, 12000);
    expect(stats.forecastNextMonthTakeHome, 38000); // 50k - 12k
  });

  test('watchMonthTotal stays correct + fast on a 25k-row history', () async {
    final now = DateTime.now();
    final cur = _monthKey(now);
    final other = _monthKey(DateTime(now.year - 1, now.month, 1));

    // Bulk-insert directly for speed: 1,000 current-month rows of ₹10 (= ₹10k)
    // plus 24,000 rows in a different month/year that must be excluded.
    await database.batch((b) {
      b.insertAll(database.expenses, [
        for (var i = 0; i < 1000; i++)
          db.ExpensesCompanion.insert(
            id: 'cur_$i',
            amount: 10,
            description: 'c',
            category: 'Food',
            bank: 'HDFC',
            cardType: 'CC',
            date: '$cur-12T10:00:00.000',
            comments: const Value(''),
          ),
        for (var i = 0; i < 24000; i++)
          db.ExpensesCompanion.insert(
            id: 'oth_$i',
            amount: 999,
            description: 'o',
            category: 'Shopping',
            bank: 'HDFC',
            cardType: 'CC',
            date: '$other-12T10:00:00.000',
            comments: const Value(''),
          ),
      ]);
    });

    final sw = Stopwatch()..start();
    final total = await container
        .read(expenseRepositoryProvider)
        .watchMonthTotal(cur)
        .first;
    sw.stop();

    expect(total, 10000, reason: 'only the 1,000 current-month rows');
    expect(sw.elapsedMilliseconds, lessThan(2000),
        reason: 'index-backed SQL aggregate, no rows in memory');
  });
}
