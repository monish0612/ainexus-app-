import 'package:ai_nexus/core/network/api_client.dart';
import 'package:ai_nexus/data/local/database/app_database.dart' as db;
import 'package:ai_nexus/data/repositories/expense_repository.dart';
import 'package:ai_nexus/domain/entities/expense_entities.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Proves add / edit / delete (and date moves) write the home-screen widget
/// snapshot before the repository call returns.
class _FakeApi extends ApiClient {
  _FakeApi();

  Response<T> _resp<T>(String path, Object? data) => Response<T>(
        requestOptions: RequestOptions(path: path),
        data: data as T?,
        statusCode: 200,
      );

  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
  }) async =>
      _resp<T>(path, const <dynamic>[]);

  @override
  Future<Response<T>> post<T>(
    String path, {
    Object? data,
    Options? options,
    CancelToken? cancelToken,
  }) async =>
      _resp<T>(path, <String, dynamic>{'ok': true});

  @override
  Future<Response<T>> put<T>(String path, {Object? data}) async =>
      _resp<T>(path, <String, dynamic>{});

  @override
  Future<Response<T>> delete<T>(String path) async =>
      _resp<T>(path, <String, dynamic>{'ok': true});
}

Expense _exp({
  required String id,
  required double amount,
  required String date,
  String category = 'Food',
}) =>
    Expense(
      id: id,
      amount: amount,
      description: id,
      category: category,
      bank: 'CASH',
      cardType: 'Cash',
      date: date,
      isManualCategory: false,
    );

String _iso(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}T12:00:00.000';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('app.ainexus.ai_nexus/expense_widget');
  late db.AppDatabase database;
  late ExpenseRepository repo;

  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => null);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    database = db.AppDatabase.forTesting(NativeDatabase.memory());
    repo = ExpenseRepository(database, _FakeApi(), prefs);
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    try {
      await database.close();
    } on Object {
      // Already closed by the rethrow test.
    }
  });

  test(
      'add, amount edit, category edit, date edit, and delete update the widget',
      () async {
    final now = DateTime.now();
    final today = _iso(now);
    final lastMonth = _iso(DateTime(now.year, now.month - 1, 12));

    await repo.addExpense(_exp(id: 'e1', amount: 250, date: today));
    var prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('expense_widget_today_total'), '250.00');
    expect(prefs.getString('expense_widget_month_spent'), '250.00');
    expect(prefs.getInt('expense_widget_today_count'), 1);
    expect(prefs.getString('expense_widget_top_cat_name'), 'Food');
    expect(prefs.getString('expense_widget_pie'), contains('Food'));

    await repo.updateExpense(
      _exp(id: 'e1', amount: 80, date: today, category: 'Shopping'),
    );
    prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('expense_widget_today_total'), '80.00');
    expect(prefs.getString('expense_widget_month_spent'), '80.00');
    expect(prefs.getString('expense_widget_top_cat_name'), 'Shopping');
    expect(prefs.getString('expense_widget_pie'), contains('Shopping'));
    expect(prefs.getString('expense_widget_pie'), isNot(contains('Food')));

    await repo.updateExpense(
      _exp(id: 'e1', amount: 80, date: lastMonth, category: 'Shopping'),
    );
    prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('expense_widget_today_total'), '0.00');
    expect(prefs.getString('expense_widget_month_spent'), '0.00');
    expect(prefs.getInt('expense_widget_today_count'), 0);
    expect(prefs.getInt('expense_widget_month_count'), 0);
    expect(prefs.getString('expense_widget_pie'), '');

    await repo.deleteExpense('e1');
    prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('expense_widget_today_total'), '0.00');
    expect(prefs.getInt('expense_widget_today_count'), 0);
    expect(prefs.getString('expense_widget_month_spent'), '0.00');
    expect(prefs.getString('expense_widget_pie'), '');
  });

  test('widget snapshot ignores expenses older than the month bound', () async {
    final now = DateTime.now();
    final today = _iso(now);
    final ancient = _iso(DateTime(now.year - 1, now.month, 3));

    await repo.addExpense(_exp(id: 'old', amount: 9999, date: ancient));
    await repo.addExpense(_exp(id: 'e1', amount: 40, date: today));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('expense_widget_today_total'), '40.00');
    expect(prefs.getString('expense_widget_month_spent'), '40.00');
    expect(prefs.getInt('expense_widget_month_count'), 1);
    expect(prefs.getString('expense_widget_pie'), isNot(contains('9999')));
  });

  test('range aggregates rethrow after a SQL failure', () async {
    await database.customStatement('DROP TABLE expenses');
    await expectLater(repo.rangeSummary(), throwsA(isA<Object>()));
    await expectLater(repo.categoryBreakdown(), throwsA(isA<Object>()));
    await expectLater(
        repo.timeBreakdown(monthly: true), throwsA(isA<Object>()));
  });
}
