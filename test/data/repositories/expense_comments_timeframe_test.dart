// Deep integration tests for the two new Expense capabilities:
//   1. Optional "comments" field — persisted locally, sent on sync, and read
//      back from the server payload.
//   2. The Spending-Analysis drill-down data layer — DB-level paginated range
//      queries, range summary aggregation, category breakdown and search,
//      which must stay correct/fluid for very large histories.
//
// These run the REAL [ExpenseRepository] against a REAL in-memory Drift DB with
// a controllable fake [ApiClient]. Nothing is mocked at the repository boundary.

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

  final List<String> calls = <String>[];
  final List<Object?> postBodies = <Object?>[];
  Object? getResponse;

  Response<T> _resp<T>(String path, Object? data) => Response<T>(
        requestOptions: RequestOptions(path: path),
        data: data as T?,
        statusCode: 200,
      );

  @override
  Future<Response<T>> get<T>(String path,
      {Map<String, dynamic>? queryParameters, CancelToken? cancelToken}) async {
    calls.add('GET $path');
    return _resp<T>(path, getResponse ?? <dynamic>[]);
  }

  @override
  Future<Response<T>> post<T>(String path,
      {Object? data, Options? options, CancelToken? cancelToken}) async {
    calls.add('POST $path');
    postBodies.add(data);
    return _resp<T>(path, <String, dynamic>{'ok': true});
  }

  @override
  Future<Response<T>> put<T>(String path, {Object? data}) async {
    calls.add('PUT $path');
    return _resp<T>(path, <String, dynamic>{});
  }

  @override
  Future<Response<T>> delete<T>(String path) async {
    calls.add('DELETE $path');
    return _resp<T>(path, <String, dynamic>{'ok': true});
  }
}

Expense _expense(
  String id, {
  required double amount,
  String description = 'desc',
  String category = 'Food',
  String date = '2026-06-25T10:00:00.000',
  String comments = '',
}) {
  return Expense(
    id: id,
    amount: amount,
    description: description,
    category: category,
    bank: 'HDFC',
    cardType: 'CC',
    date: date,
    isManualCategory: false,
    comments: comments,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late db.AppDatabase database;
  late _FakeApi api;
  late ExpenseRepository repo;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    database = db.AppDatabase.forTesting(NativeDatabase.memory());
    api = _FakeApi();
    repo = ExpenseRepository(database, api, prefs);
  });

  tearDown(() async {
    await database.close();
  });

  group('comments persistence', () {
    test('addExpense stores comments locally and sends them on sync', () async {
      final synced = await repo.addExpense(
        _expense('e1', amount: 120, comments: 'split with Riya'),
      );
      expect(synced, isTrue);

      final rows = await database.select(database.expenses).get();
      expect(rows.single.comments, 'split with Riya');

      final body = api.postBodies.last as Map<String, dynamic>;
      expect(body['comments'], 'split with Riya');
    });

    test('updateExpense overwrites comments', () async {
      await repo.addExpense(_expense('e1', amount: 50, comments: 'old note'));
      await repo.updateExpense(
        _expense('e1', amount: 50, comments: 'reimburse from office'),
      );
      final rows = await database.select(database.expenses).get();
      expect(rows.single.comments, 'reimburse from office');
    });

    test('syncFromServer reads comments from server payload', () async {
      api.getResponse = <Map<String, dynamic>>[
        {
          'id': 's1',
          'amount': 99,
          'description': 'Cloud bill',
          'category': 'Bills',
          'bank': 'ICICI',
          'cardType': 'CC',
          'date': '2026-06-20T08:00:00.000',
          'isManualCategory': false,
          'comments': 'cancel before renewal',
        },
      ];
      final inserted = await repo.syncFromServer();
      expect(inserted, 1);
      final rows = await database.select(database.expenses).get();
      expect(rows.single.comments, 'cancel before renewal');
    });
  });

  group('timeframe drill-down queries', () {
    Future<void> seed() async {
      // 5 expenses across distinct dates + categories.
      await repo.addExpense(_expense('a', amount: 100,
          category: 'Food', date: '2026-06-25T10:00:00.000'));
      await repo.addExpense(_expense('b', amount: 200,
          category: 'Food', date: '2026-06-24T10:00:00.000'));
      await repo.addExpense(_expense('c', amount: 300,
          category: 'Transport', date: '2026-06-10T10:00:00.000'));
      await repo.addExpense(_expense('d', amount: 400,
          category: 'Bills', date: '2026-05-01T10:00:00.000',
          description: 'Electricity', comments: 'meter reading 4521'));
      await repo.addExpense(_expense('e', amount: 500,
          category: 'Food', date: '2026-01-01T10:00:00.000'));
    }

    test('getExpensesPage respects range + newest-first + pagination', () async {
      await seed();
      // Range starting 2026-06-01 → a, b, c (3 rows).
      final page1 = await repo.getExpensesPage(
        startIso: '2026-06-01T00:00:00.000',
        limit: 2,
        offset: 0,
      );
      expect(page1.map((e) => e.id), ['a', 'b']); // desc by date
      final page2 = await repo.getExpensesPage(
        startIso: '2026-06-01T00:00:00.000',
        limit: 2,
        offset: 2,
      );
      expect(page2.map((e) => e.id), ['c']);
    });

    test('rangeSummary aggregates count + total in SQL', () async {
      await seed();
      final all = await repo.rangeSummary();
      expect(all.count, 5);
      expect(all.total, 1500);

      final june = await repo.rangeSummary(startIso: '2026-06-01T00:00:00.000');
      expect(june.count, 3);
      expect(june.total, 600); // 100 + 200 + 300
    });

    test('categoryBreakdown groups by category, sorted by spend', () async {
      await seed();
      final cats = await repo.categoryBreakdown();
      expect(cats.first.category, 'Food'); // 100+200+500 = 800 (largest)
      expect(cats.first.total, 800);
      final foodRow = cats.firstWhere((c) => c.category == 'Food');
      expect(foodRow.count, 3);
    });

    test('search matches description, category and comments', () async {
      await seed();
      final byComment = await repo.getExpensesPage(
        search: 'meter reading',
        limit: 50,
        offset: 0,
      );
      expect(byComment.map((e) => e.id), ['d']);

      final byDesc = await repo.getExpensesPage(
        search: 'Electric',
        limit: 50,
        offset: 0,
      );
      expect(byDesc.map((e) => e.id), ['d']);

      final byCategory = await repo.getExpensesPage(
        search: 'Transport',
        limit: 50,
        offset: 0,
      );
      expect(byCategory.map((e) => e.id), ['c']);
    });

    test('category filter narrows the page', () async {
      await seed();
      final food = await repo.getExpensesPage(
        category: 'Food',
        limit: 50,
        offset: 0,
      );
      expect(food.map((e) => e.id), ['a', 'b', 'e']);
    });
  });

  group('search edge cases (LIKE wildcards / quotes — literal match)', () {
    test('percent sign is matched literally, not as a wildcard', () async {
      await repo.addExpense(_expense('p1', amount: 10,
          description: 'Sale', comments: '50% cashback'));
      await repo.addExpense(_expense('p2', amount: 20,
          description: 'fifty', comments: '50 rupees flat'));
      final res = await repo.getExpensesPage(
        search: '50%',
        limit: 50,
        offset: 0,
      );
      expect(res.map((e) => e.id), ['p1']);
    });

    test('underscore is matched literally, not as a single-char wildcard',
        () async {
      await repo.addExpense(_expense('u1', amount: 10,
          description: 'code a_b', comments: ''));
      await repo.addExpense(_expense('u2', amount: 20,
          description: 'code aXb', comments: ''));
      final res = await repo.getExpensesPage(
        search: 'a_b',
        limit: 50,
        offset: 0,
      );
      expect(res.map((e) => e.id), ['u1']);
    });

    test('single quote / apostrophe is safe and matches', () async {
      await repo.addExpense(_expense('q1', amount: 10,
          description: "Mom's gift", comments: ''));
      await repo.addExpense(_expense('q2', amount: 20,
          description: 'something else', comments: ''));
      final res = await repo.getExpensesPage(
        search: "Mom's",
        limit: 50,
        offset: 0,
      );
      expect(res.map((e) => e.id), ['q1']);
    });

    test('search is case-insensitive across comments', () async {
      await repo.addExpense(_expense('c1', amount: 10,
          description: 'lunch', comments: 'Reimburse From OFFICE'));
      final res = await repo.getExpensesPage(
        search: 'office',
        limit: 50,
        offset: 0,
      );
      expect(res.map((e) => e.id), ['c1']);
    });

    test('rangeSummary honours the same literal search', () async {
      await repo.addExpense(_expense('s1', amount: 100,
          description: 'A', comments: '10% tax'));
      await repo.addExpense(_expense('s2', amount: 200,
          description: 'B', comments: '10 items'));
      final summary = await repo.rangeSummary(search: '10%');
      expect(summary.count, 1);
      expect(summary.total, 100);
    });

    test('whitespace-only search is treated as no filter', () async {
      await repo.addExpense(_expense('w1', amount: 10));
      await repo.addExpense(_expense('w2', amount: 20));
      final res = await repo.getExpensesPage(
        search: '   ',
        limit: 50,
        offset: 0,
      );
      expect(res.length, 2);
    });
  });

  group('getExpensesPage sort (powers AI "highest/lowest" queries)', () {
    Future<void> seedAmounts() async {
      await repo.addExpense(_expense('a', amount: 500,
          date: '2026-06-20T10:00:00.000'));
      await repo.addExpense(_expense('b', amount: 1200,
          date: '2026-06-21T10:00:00.000'));
      await repo.addExpense(_expense('c', amount: 50,
          date: '2026-06-22T10:00:00.000'));
      await repo.addExpense(_expense('d', amount: 1200,
          date: '2026-06-23T10:00:00.000'));
    }

    test('amountDesc returns highest first', () async {
      await seedAmounts();
      final res = await repo.getExpensesPage(
        sort: ExpenseSort.amountDesc,
        limit: 50,
        offset: 0,
      );
      expect(res.first.amount, 1200);
      expect(res.last.amount, 50);
      // Ties (b,d=1200) broken by date desc → d before b.
      expect(res.take(2).map((e) => e.id), ['d', 'b']);
    });

    test('amountAsc returns lowest first', () async {
      await seedAmounts();
      final res = await repo.getExpensesPage(
        sort: ExpenseSort.amountAsc,
        limit: 50,
        offset: 0,
      );
      expect(res.first.amount, 50);
      expect(res.first.id, 'c');
    });

    test('amount sort is stable across paginated pages', () async {
      await seedAmounts();
      final p1 = await repo.getExpensesPage(
        sort: ExpenseSort.amountDesc,
        limit: 2,
        offset: 0,
      );
      final p2 = await repo.getExpensesPage(
        sort: ExpenseSort.amountDesc,
        limit: 2,
        offset: 2,
      );
      expect([...p1, ...p2].map((e) => e.id), ['d', 'b', 'a', 'c']);
    });

    test('dateAsc returns oldest first', () async {
      await seedAmounts();
      final res = await repo.getExpensesPage(
        sort: ExpenseSort.dateAsc,
        limit: 50,
        offset: 0,
      );
      expect(res.map((e) => e.id), ['a', 'b', 'c', 'd']);
    });

    test('default sort stays newest-first (date desc)', () async {
      await seedAmounts();
      final res = await repo.getExpensesPage(limit: 50, offset: 0);
      expect(res.map((e) => e.id), ['d', 'c', 'b', 'a']);
    });
  });

  group('timeBreakdown (powers "visualize" charts, SQL-aggregated)', () {
    test('daily buckets group by day, chronological, with totals + counts',
        () async {
      await repo.addExpense(_expense('a', amount: 100,
          date: '2026-06-20T09:00:00.000'));
      await repo.addExpense(_expense('b', amount: 50,
          date: '2026-06-20T18:00:00.000'));
      await repo.addExpense(_expense('c', amount: 200,
          date: '2026-06-22T10:00:00.000'));
      final buckets = await repo.timeBreakdown(monthly: false);
      expect(buckets.map((b) => b.bucket), ['2026-06-20', '2026-06-22']);
      expect(buckets.first.total, 150); // 100 + 50 on the same day
      expect(buckets.first.count, 2);
      expect(buckets.last.total, 200);
    });

    test('monthly buckets group by YYYY-MM', () async {
      await repo.addExpense(_expense('a', amount: 100,
          date: '2026-05-31T09:00:00.000'));
      await repo.addExpense(_expense('b', amount: 300,
          date: '2026-06-01T09:00:00.000'));
      await repo.addExpense(_expense('c', amount: 200,
          date: '2026-06-28T09:00:00.000'));
      final buckets = await repo.timeBreakdown(monthly: true);
      expect(buckets.map((b) => b.bucket), ['2026-05', '2026-06']);
      expect(buckets.last.total, 500);
      expect(buckets.last.count, 2);
    });

    test('respects date range, category and search filters', () async {
      await repo.addExpense(_expense('a', amount: 100, category: 'Food',
          date: '2026-06-10T09:00:00.000', comments: 'goa trip'));
      await repo.addExpense(_expense('b', amount: 80, category: 'Travel',
          date: '2026-06-10T09:00:00.000', comments: 'goa trip'));
      await repo.addExpense(_expense('c', amount: 70, category: 'Food',
          date: '2026-06-11T09:00:00.000', comments: 'home'));
      final goa = await repo.timeBreakdown(monthly: false, search: 'goa');
      expect(goa.length, 1);
      expect(goa.first.total, 180);
      final food = await repo.timeBreakdown(
        monthly: false,
        category: 'Food',
        search: 'goa',
      );
      expect(food.length, 1);
      expect(food.first.total, 100);
    });

    test('empty history yields no buckets', () async {
      final buckets = await repo.timeBreakdown(monthly: false);
      expect(buckets, isEmpty);
    });
  });

  group('semantic search (searchTerms OR-group) — query expansion', () {
    // Mirrors "anything related to my car" → [car, fuel, garage, insurance].
    Future<void> seedCarish() async {
      await repo.addExpense(_expense('petrol', amount: 2000,
          description: 'Petrol pump fill', category: 'Fuel'));
      await repo.addExpense(_expense('garage', amount: 3500,
          description: 'Car service', category: 'Transport',
          comments: 'left it at the garage'));
      await repo.addExpense(_expense('ins', amount: 8000,
          description: 'Annual premium', category: 'Insurance',
          comments: 'car insurance renewal'));
      await repo.addExpense(_expense('lunch', amount: 250,
          description: 'Lunch', category: 'Food', comments: 'with team'));
      await repo.addExpense(_expense('movie', amount: 500,
          description: 'Movie night', category: 'Entertainment'));
    }

    test('matches a row if it contains ANY term (desc/category/comments)',
        () async {
      await seedCarish();
      final res = await repo.getExpensesPage(
        searchTerms: ['fuel', 'garage', 'insurance'],
        limit: 50,
        offset: 0,
      );
      // petrol(category Fuel), garage(comment), ins(comment "car insurance")
      expect(res.map((e) => e.id).toSet(), {'petrol', 'garage', 'ins'});
      expect(res.map((e) => e.id), isNot(contains('lunch')));
      expect(res.map((e) => e.id), isNot(contains('movie')));
    });

    test('NEVER fabricates: no matching terms → empty result', () async {
      await seedCarish();
      final res = await repo.getExpensesPage(
        searchTerms: ['spaceship', 'helicopter'],
        limit: 50,
        offset: 0,
      );
      expect(res, isEmpty);
    });

    test('single search (AND) combines with the semantic OR-group', () async {
      await seedCarish();
      // Must contain "car" AND (one of fuel/garage/insurance).
      final res = await repo.getExpensesPage(
        search: 'car',
        searchTerms: ['fuel', 'garage', 'insurance'],
        limit: 50,
        offset: 0,
      );
      // "Car service" matches search=car AND garage-term(comment "garage").
      // "car insurance renewal" matches search=car AND insurance-term.
      // petrol has no "car" anywhere → excluded by the AND.
      expect(res.map((e) => e.id).toSet(), {'garage', 'ins'});
    });

    test('category filter further narrows the semantic group', () async {
      await seedCarish();
      final res = await repo.getExpensesPage(
        category: 'Insurance',
        searchTerms: ['fuel', 'garage', 'insurance'],
        limit: 50,
        offset: 0,
      );
      expect(res.map((e) => e.id), ['ins']);
    });

    test('blank / whitespace terms are ignored (no accidental match-all)',
        () async {
      await seedCarish();
      final res = await repo.getExpensesPage(
        searchTerms: ['  ', '', 'garage'],
        limit: 50,
        offset: 0,
      );
      expect(res.map((e) => e.id), ['garage']);
    });

    test('all-blank terms behave as no filter', () async {
      await seedCarish();
      final res = await repo.getExpensesPage(
        searchTerms: ['   ', ''],
        limit: 50,
        offset: 0,
      );
      expect(res.length, 5);
    });

    test('terms are matched literally (wildcards/quotes are safe)', () async {
      await repo.addExpense(_expense('p', amount: 10,
          description: 'sale', comments: '10% car wash'));
      await repo.addExpense(_expense('q', amount: 20,
          description: 'sale', comments: '10 km drive'));
      final res = await repo.getExpensesPage(
        searchTerms: ['10%'],
        limit: 50,
        offset: 0,
      );
      expect(res.map((e) => e.id), ['p']);
    });

    test('rangeSummary aggregates the semantic group correctly', () async {
      await seedCarish();
      final summary = await repo.rangeSummary(
        searchTerms: ['fuel', 'garage', 'insurance'],
      );
      expect(summary.count, 3);
      expect(summary.total, 2000 + 3500 + 8000);
    });

    test('categoryBreakdown respects the semantic group', () async {
      await seedCarish();
      final cats = await repo.categoryBreakdown(
        searchTerms: ['fuel', 'garage', 'insurance'],
      );
      expect(cats.map((c) => c.category).toSet(),
          {'Fuel', 'Transport', 'Insurance'});
    });
  });
}
