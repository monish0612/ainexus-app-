// Integration tests for the `excludeNonSpend` flag on ExpenseRepository
// aggregations. Runs the REAL repository over an in-memory Drift DB and proves
// that Investment- and Loan-category transactions are kept OUT of spending
// figures (rangeSummary / categoryBreakdown / timeBreakdown / getExpensesPage)
// while remaining fully queryable when a view is explicitly scoped to them.

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ai_nexus/core/network/api_client.dart';
import 'package:ai_nexus/data/local/database/app_database.dart' as db;
import 'package:ai_nexus/data/repositories/expense_repository.dart';
import 'package:ai_nexus/domain/entities/expense_entities.dart';

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

Future<ExpenseRepository> _repo(db.AppDatabase database) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  return ExpenseRepository(database, _FakeApi(), prefs);
}

Expense _exp({
  required String id,
  required double amount,
  required String category,
  required String date,
  String cardType = 'CC',
}) =>
    Expense(
      id: id,
      amount: amount,
      description: id,
      category: category,
      bank: cardType == 'Cash' ? 'CASH' : 'HDFC',
      cardType: cardType,
      date: date,
      isManualCategory: false,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late db.AppDatabase database;
  late ExpenseRepository repo;

  setUp(() async {
    database = db.AppDatabase.forTesting(NativeDatabase.memory());
    repo = await _repo(database);
    // June 2026: 10k Food + 5k Transport (spend = 15k),
    // plus a 50k Investment on a credit card (must NOT count as spend).
    await repo.addExpense(_exp(
        id: 'food', amount: 10000, category: 'Food', date: '2026-06-03T10:00:00.000'));
    await repo.addExpense(_exp(
        id: 'transport',
        amount: 5000,
        category: 'Transport',
        date: '2026-06-10T10:00:00.000'));
    await repo.addExpense(_exp(
        id: 'invest',
        amount: 50000,
        category: kInvestmentCategory,
        date: '2026-06-15T10:00:00.000'));
  });
  tearDown(() async => database.close());

  test('rangeSummary excludes investment from spend total/count', () async {
    final spend = await repo.rangeSummary(excludeNonSpend: true);
    expect(spend.total, 15000);
    expect(spend.count, 2);

    // Without the flag, the raw total includes the investment.
    final raw = await repo.rangeSummary();
    expect(raw.total, 65000);
    expect(raw.count, 3);
  });

  test('rangeSummary scoped to Investment still returns the investment',
      () async {
    final inv = await repo.rangeSummary(category: kInvestmentCategory);
    expect(inv.total, 50000);
    expect(inv.count, 1);
  });

  test('categoryBreakdown drops the Investment bucket when excluded', () async {
    final cats = await repo.categoryBreakdown(excludeNonSpend: true);
    final names = cats.map((c) => c.category).toList();
    expect(names, isNot(contains(kInvestmentCategory)));
    expect(cats.fold<double>(0, (s, c) => s + c.total), 15000);
  });

  test('timeBreakdown month bucket excludes investment', () async {
    final buckets = await repo.timeBreakdown(
      monthly: true,
      excludeNonSpend: true,
    );
    final june = buckets.firstWhere((b) => b.bucket == '2026-06');
    expect(june.total, 15000);
    expect(june.count, 2);
  });

  test('getExpensesPage hides investments when excluded, shows when scoped',
      () async {
    final spendPage = await repo.getExpensesPage(
      excludeNonSpend: true,
      limit: 50,
      offset: 0,
    );
    expect(spendPage.any((e) => isInvestmentCategory(e.category)), isFalse);
    expect(spendPage.length, 2);

    final invPage = await repo.getExpensesPage(
      category: kInvestmentCategory,
      limit: 50,
      offset: 0,
    );
    expect(invPage.length, 1);
    expect(invPage.single.amount, 50000);
  });

  // ── Adversarial + scaling ─────────────────────────────────────────────────

  test('a portfolio-only DB shows zero spend but a real investment total',
      () async {
    final db2 = db.AppDatabase.forTesting(NativeDatabase.memory());
    final r2 = await _repo(db2);
    addTearDown(() async => db2.close());
    await r2.addExpense(_exp(
        id: 'i1', amount: 10000, category: kInvestmentCategory, date: '2026-06-01T10:00:00.000'));
    await r2.addExpense(_exp(
        id: 'i2', amount: 20000, category: kInvestmentCategory, date: '2026-06-02T10:00:00.000'));

    final spend = await r2.rangeSummary(excludeNonSpend: true);
    expect(spend.total, 0);
    expect(spend.count, 0);

    final inv = await r2.rangeSummary(category: kInvestmentCategory);
    expect(inv.total, 30000);
    expect(inv.count, 2);
  });

  test('a malformed-date investment is still excluded by category', () async {
    // The exclusion is category-based, so even a row whose date can't parse
    // never leaks into spend totals.
    await repo.addExpense(_exp(
        id: 'bad', amount: 9999, category: kInvestmentCategory, date: 'not-a-date'));
    final spend = await repo.rangeSummary(excludeNonSpend: true);
    expect(spend.total, 15000); // unchanged from setUp's 10k + 5k
    expect(spend.count, 2);
  });

  test('a negative-amount investment never offsets spend', () async {
    // A correction entry (negative) under Investment must not subtract from
    // the spend total either.
    await repo.addExpense(_exp(
        id: 'neg', amount: -5000, category: kInvestmentCategory, date: '2026-06-09T10:00:00.000'));
    final spend = await repo.rangeSummary(excludeNonSpend: true);
    expect(spend.total, 15000);
    expect(spend.count, 2);
  });

  test('date-range + excludeInvestment compose correctly', () async {
    // Add a July spend + July investment; query June only.
    await repo.addExpense(_exp(
        id: 'jul-food', amount: 1234, category: 'Food', date: '2026-07-05T10:00:00.000'));
    await repo.addExpense(_exp(
        id: 'jul-inv', amount: 9999, category: kInvestmentCategory, date: '2026-07-06T10:00:00.000'));

    final june = await repo.rangeSummary(
      startIso: '2026-06-01T00:00:00.000',
      endIso: '2026-07-01T00:00:00.000',
      excludeNonSpend: true,
    );
    expect(june.total, 15000);
    expect(june.count, 2);
  });

  test('scales to 5k rows: exclusion stays correct and fast (SQL aggregate)',
      () async {
    final db2 = db.AppDatabase.forTesting(NativeDatabase.memory());
    final r2 = await _repo(db2);
    addTearDown(() async => db2.close());

    // 4000 spend rows of ₹10 each (=40,000) + 1000 investment rows of ₹100
    // each (=100,000). The investment must be invisible to spend aggregates.
    await db2.batch((b) {
      for (var i = 0; i < 4000; i++) {
        b.insert(
          db2.expenses,
          db.ExpensesCompanion.insert(
            id: 'spend-$i',
            amount: 10,
            description: 'd',
            category: 'Food',
            bank: 'HDFC',
            cardType: 'CC',
            date: '2026-06-${(i % 27 + 1).toString().padLeft(2, '0')}T10:00:00.000',
          ),
        );
      }
      for (var i = 0; i < 1000; i++) {
        b.insert(
          db2.expenses,
          db.ExpensesCompanion.insert(
            id: 'inv-$i',
            amount: 100,
            description: 'd',
            category: kInvestmentCategory,
            bank: 'HDFC',
            cardType: 'CC',
            date: '2026-06-${(i % 27 + 1).toString().padLeft(2, '0')}T10:00:00.000',
          ),
        );
      }
    });

    final sw = Stopwatch()..start();
    final spend = await r2.rangeSummary(excludeNonSpend: true);
    final cats = await r2.categoryBreakdown(excludeNonSpend: true);
    sw.stop();

    expect(spend.total, 40000);
    expect(spend.count, 4000);
    expect(cats.any((c) => c.category == kInvestmentCategory), isFalse);
    // SQL aggregation over 5k rows should be comfortably sub-second.
    expect(sw.elapsedMilliseconds, lessThan(1500));
  });

  // ── Loan exclusion (mirrors Investment) ───────────────────────────────────

  test('a large loan repayment never touches the spend/budget total', () async {
    // The core scenario: budget for the month is small, a 50k home-loan EMI is
    // logged, and it must NOT be consumed by the month's spend figure.
    await repo.addExpense(_exp(
        id: 'homeloan',
        amount: 50000,
        category: kLoanCategory,
        date: '2026-06-20T10:00:00.000'));

    final spend = await repo.rangeSummary(excludeNonSpend: true);
    expect(spend.total, 15000); // unchanged from setUp's 10k + 5k
    expect(spend.count, 2);
  });

  test('rangeSummary scoped to Loan still returns the loan', () async {
    await repo.addExpense(_exp(
        id: 'homeloan',
        amount: 50000,
        category: kLoanCategory,
        date: '2026-06-20T10:00:00.000'));

    final loans = await repo.rangeSummary(category: kLoanCategory);
    expect(loans.total, 50000);
    expect(loans.count, 1);
  });

  test('categoryBreakdown drops the Loan bucket when excluded', () async {
    await repo.addExpense(_exp(
        id: 'homeloan',
        amount: 50000,
        category: kLoanCategory,
        date: '2026-06-20T10:00:00.000'));

    final cats = await repo.categoryBreakdown(excludeNonSpend: true);
    final names = cats.map((c) => c.category).toList();
    expect(names, isNot(contains(kLoanCategory)));
    expect(names, isNot(contains(kInvestmentCategory)));
    expect(cats.fold<double>(0, (s, c) => s + c.total), 15000);
  });

  test('getExpensesPage hides loans when excluded, shows when scoped',
      () async {
    await repo.addExpense(_exp(
        id: 'homeloan',
        amount: 50000,
        category: kLoanCategory,
        date: '2026-06-20T10:00:00.000'));

    final spendPage = await repo.getExpensesPage(
      excludeNonSpend: true,
      limit: 50,
      offset: 0,
    );
    expect(spendPage.any((e) => isLoanCategory(e.category)), isFalse);
    expect(spendPage.any((e) => isInvestmentCategory(e.category)), isFalse);
    expect(spendPage.length, 2);

    final loanPage = await repo.getExpensesPage(
      category: kLoanCategory,
      limit: 50,
      offset: 0,
    );
    expect(loanPage.length, 1);
    expect(loanPage.single.amount, 50000);
  });
}
