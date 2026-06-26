// Integration tests for ExpenseRepository.watchMonthlyCardSpendTotals — the
// SQL aggregation that powers the credit-card repayment forecast. Runs the REAL
// repository over an in-memory Drift DB and proves it:
//   • sums ONLY the requested card type ('CC'), excluding DB/Cash;
//   • groups correctly by 'YYYY-MM' across multiple months;
//   • re-emits reactively when a new CC expense lands;
//   • returns an empty map when there's no matching activity.

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
  required String cardType,
  required String date,
}) =>
    Expense(
      id: id,
      amount: amount,
      description: id,
      category: 'Others',
      bank: cardType == 'Cash' ? 'CASH' : 'HDFC',
      cardType: cardType,
      date: date,
      isManualCategory: false,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late db.AppDatabase database;

  setUp(() {
    database = db.AppDatabase.forTesting(NativeDatabase.memory());
  });
  tearDown(() async => database.close());

  test('sums only CC expenses, grouped by month, ignoring DB/Cash', () async {
    final repo = await _repo(database);
    // June: 2 CC (15k + 10k) + 1 DB (5k) + 1 Cash (2k) → CC June = 25k.
    await repo.addExpense(
        _exp(id: 'j-cc1', amount: 15000, cardType: 'CC', date: '2026-06-03T10:00:00.000'));
    await repo.addExpense(
        _exp(id: 'j-cc2', amount: 10000, cardType: 'CC', date: '2026-06-18T10:00:00.000'));
    await repo.addExpense(
        _exp(id: 'j-db', amount: 5000, cardType: 'DB', date: '2026-06-10T10:00:00.000'));
    await repo.addExpense(
        _exp(id: 'j-cash', amount: 2000, cardType: 'Cash', date: '2026-06-12T10:00:00.000'));
    // May: 1 CC (12k).
    await repo.addExpense(
        _exp(id: 'm-cc', amount: 12000, cardType: 'CC', date: '2026-05-20T10:00:00.000'));

    final totals = await repo.watchMonthlyCardSpendTotals('CC').first;
    expect(totals['2026-06'], 25000);
    expect(totals['2026-05'], 12000);
    // DB/Cash never leak in.
    expect(totals.values.fold<double>(0, (a, b) => a + b), 37000);
  });

  test('re-emits when a new CC expense is added', () async {
    final repo = await _repo(database);
    await repo.addExpense(
        _exp(id: 'cc1', amount: 8000, cardType: 'CC', date: '2026-06-05T10:00:00.000'));

    final stream = repo.watchMonthlyCardSpendTotals('CC');
    expect((await stream.first)['2026-06'], 8000);

    await repo.addExpense(
        _exp(id: 'cc2', amount: 4000, cardType: 'CC', date: '2026-06-09T10:00:00.000'));

    // The reactive query re-emits the updated month total.
    final updated = await stream.firstWhere(
      (m) => (m['2026-06'] ?? 0) >= 12000,
    );
    expect(updated['2026-06'], 12000);
  });

  test('empty map when there is no CC activity', () async {
    final repo = await _repo(database);
    await repo.addExpense(
        _exp(id: 'db', amount: 5000, cardType: 'DB', date: '2026-06-10T10:00:00.000'));
    final totals = await repo.watchMonthlyCardSpendTotals('CC').first;
    expect(totals, isEmpty);
  });
}
