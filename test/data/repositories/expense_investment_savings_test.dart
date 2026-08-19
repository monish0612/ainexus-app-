// Tests that investments are treated as WEALTH (not consumption) by the
// savings-facing aggregations, while the credit-card BILL forecast still
// includes them (an investment bought on a CC is genuine debt you must repay):
//
//   • watchMonthTotal           → excludes investment (drives salary "spent")
//   • watchMonthlySpendTotals   → excludes investment (lifetime savings/runway)
//   • watchMonthlyCardSpendTotals → INCLUDES investment (CC repayment forecast)
//
// Plus pure MemoryFacts tests proving the AI-context rollup never counts an
// investment as spend.

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ai_nexus/core/network/api_client.dart';
import 'package:ai_nexus/data/local/database/app_database.dart' as db;
import 'package:ai_nexus/data/repositories/expense_repository.dart';
import 'package:ai_nexus/data/services/expense_memory_service.dart';
import 'package:ai_nexus/domain/entities/expense_entities.dart';

class _FakeApi extends ApiClient {
  _FakeApi();
  Response<T> _r<T>(String p, Object? d) => Response<T>(
      requestOptions: RequestOptions(path: p), data: d as T?, statusCode: 200);
  @override
  Future<Response<T>> get<T>(String path,
          {Map<String, dynamic>? queryParameters, CancelToken? cancelToken}) async =>
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

  group('savings streams', () {
    late db.AppDatabase database;
    late ExpenseRepository repo;

    setUp(() async {
      database = db.AppDatabase.forTesting(NativeDatabase.memory());
      repo = await _repo(database);
      await repo.addExpense(_exp(
          id: 'food', amount: 10000, category: 'Food', date: '2026-06-03T10:00:00.000'));
      await repo.addExpense(_exp(
          id: 'transport', amount: 5000, category: 'Transport', date: '2026-06-10T10:00:00.000'));
      await repo.addExpense(_exp(
          id: 'invest', amount: 50000, category: kInvestmentCategory, date: '2026-06-15T10:00:00.000'));
    });
    tearDown(() async => database.close());

    test('watchMonthTotal excludes investment from the month spend', () async {
      final total = await repo.watchMonthTotal('2026-06').first;
      expect(total, 15000);
    });

    test('watchMonthlySpendTotals excludes investment from rollup totals',
        () async {
      final totals = await repo.watchMonthlySpendTotals().first;
      expect(totals['2026-06'], 15000);
    });

    test('watchMonthlyCardSpendTotals INCLUDES investment (CC bill is debt)',
        () async {
      final cc = await repo.watchMonthlyCardSpendTotals('CC').first;
      // Investment on a credit card is still money owed to the bank next month.
      expect(cc['2026-06'], 65000);
    });
  });

  group('MemoryFacts excludes investment', () {
    // now = mid-June 2026, so '2026-06' is the current month.
    final now = DateTime(2026, 6, 15);

    final buckets = <MemoryBucket>[
      (month: '2026-06', category: 'Food', total: 10000, count: 1),
      (month: '2026-06', category: kInvestmentCategory, total: 50000, count: 1),
      (month: '2026-05', category: 'Food', total: 8000, count: 1),
    ];

    test('lifetimeTotal counts only consumption (no investment)', () {
      final f = MemoryFacts.fromBuckets(buckets, now: now);
      expect(f.lifetimeTotal, 18000);
      expect(f.lifetimeCount, 2);
    });

    test('current + previous month totals exclude investment', () {
      final f = MemoryFacts.fromBuckets(buckets, now: now);
      expect(f.currentMonthTotal, 10000);
      expect(f.previousMonthTotal, 8000);
    });

    test('top categories never surface Investment', () {
      final f = MemoryFacts.fromBuckets(buckets, now: now);
      expect(
        f.topCategoriesAllTime.any((c) => c.category == kInvestmentCategory),
        isFalse,
      );
      expect(f.topCategoriesAllTime.first.category, 'Food');
      expect(f.topCategoriesAllTime.first.total, 18000);
    });

    test('monthly trend totals exclude investment', () {
      final f = MemoryFacts.fromBuckets(buckets, now: now);
      final june = f.monthlyTrend.firstWhere((m) => m.month == '2026-06');
      expect(june.total, 10000);
    });

    test('an investment-only month is effectively zero spend', () {
      final f = MemoryFacts.fromBuckets(
        [(month: '2026-06', category: kInvestmentCategory, total: 99999, count: 3)],
        now: now,
      );
      expect(f.lifetimeTotal, 0);
      expect(f.currentMonthTotal, 0);
      expect(f.topCategoriesAllTime, isEmpty);
    });
  });
}
