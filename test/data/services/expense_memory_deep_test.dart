// DEEP end-to-end correctness tests for the memory layer driven through the
// REAL ExpenseRepository write paths (add/update/delete/sync/clear) over an
// in-memory Drift DB.
//
// The headline invariant: after ANY sequence of writes, the incrementally
// maintained rollup must EXACTLY equal a from-scratch recompute (incremental
// == authoritative). This is what guarantees the AI insight context can never
// silently drift, no matter how the data was mutated.
//
// Also proves the cross-device story: device B that only pulls expenses from
// the server (syncFromServer) ends up with byte-identical memory facts to the
// device A that authored them — i.e. the feature is consistent across devices
// even though the rollup itself is never synced.

import 'dart:math';

import 'package:ai_nexus/core/network/api_client.dart';
import 'package:ai_nexus/data/local/database/app_database.dart' as db;
import 'package:ai_nexus/data/repositories/expense_repository.dart';
import 'package:ai_nexus/data/services/expense_memory_service.dart';
import 'package:ai_nexus/domain/entities/expense_entities.dart' as domain;
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Captures POSTed expense JSON so a "second device" can replay them via GET.
class _SyncFakeApi extends ApiClient {
  _SyncFakeApi();

  final List<Map<String, dynamic>> serverExpenses = <Map<String, dynamic>>[];
  bool failPost = false;

  Response<T> _r<T>(String p, Object? d) => Response<T>(
      requestOptions: RequestOptions(path: p), data: d as T?, statusCode: 200);

  @override
  Future<Response<T>> get<T>(String path,
      {Map<String, dynamic>? queryParameters}) async {
    if (path.endsWith('/expenses')) {
      return _r<T>(path, List<Map<String, dynamic>>.from(serverExpenses));
    }
    return _r<T>(path, const <dynamic>[]);
  }

  @override
  Future<Response<T>> post<T>(String path,
      {Object? data, Options? options, CancelToken? cancelToken}) async {
    if (failPost) {
      throw DioException(
          requestOptions: RequestOptions(path: path),
          type: DioExceptionType.connectionError);
    }
    if (path.endsWith('/expenses') && data is Map) {
      // Upsert by id, mirroring server semantics.
      final m = Map<String, dynamic>.from(data);
      serverExpenses.removeWhere((e) => e['id'] == m['id']);
      serverExpenses.add(m);
    }
    return _r<T>(path, <String, dynamic>{'ok': true});
  }

  @override
  Future<Response<T>> delete<T>(String path) async => _r<T>(path, <String, dynamic>{'ok': true});
}

Future<Map<String, ({double total, int count})>> _readRollup(
    db.AppDatabase d) async {
  final rows = await d.select(d.expenseMonthlyCategory).get();
  return {
    for (final r in rows) '${r.month}|${r.category}': (total: r.total, count: r.count),
  };
}

void _expectRollupsEqual(
  Map<String, ({double total, int count})> a,
  Map<String, ({double total, int count})> b, {
  String reason = '',
}) {
  expect(a.keys.toSet(), b.keys.toSet(), reason: 'bucket keys differ. $reason');
  for (final k in a.keys) {
    expect(a[k]!.count, b[k]!.count, reason: 'count mismatch for $k. $reason');
    expect(a[k]!.total, closeTo(b[k]!.total, 0.001),
        reason: 'total mismatch for $k. $reason');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const cats = ['Food', 'Grocery', 'Transport', 'Shopping', 'Bills', 'Travel'];
  const months = ['2026-01', '2026-02', '2026-03', '2026-04', '2026-05', '2026-06'];

  late db.AppDatabase database;
  late _SyncFakeApi api;
  late ExpenseRepository repo;
  late ExpenseMemoryService memory;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    database = db.AppDatabase.forTesting(NativeDatabase.memory());
    api = _SyncFakeApi();
    repo = ExpenseRepository(database, api, prefs);
    memory = ExpenseMemoryService(database);
  });

  tearDown(() async => database.close());

  domain.Expense mk(String id, double amt, String cat, String month) =>
      domain.Expense(
        id: id,
        amount: amt,
        description: 'tx-$id',
        category: cat,
        bank: 'HDFC',
        cardType: 'CC',
        date: '$month-15T10:00:00',
        isManualCategory: false,
      );

  group('incremental == authoritative (the core invariant)', () {
    test('randomized fuzz of 400 mixed ops keeps the rollup exact', () async {
      final rng = Random(20260626);
      final live = <String, domain.Expense>{};
      var nextId = 0;

      for (var i = 0; i < 400; i++) {
        final roll = rng.nextDouble();
        if (live.isEmpty || roll < 0.6) {
          // ADD
          final id = 'e${nextId++}';
          final e = mk(
            id,
            (rng.nextInt(50000) + 1) / 10, // 0.1 .. 5000.0
            cats[rng.nextInt(cats.length)],
            months[rng.nextInt(months.length)],
          );
          live[id] = e;
          await repo.addExpense(e);
        } else if (roll < 0.85) {
          // UPDATE (may change amount, category and/or month)
          final id = live.keys.elementAt(rng.nextInt(live.length));
          final updated = mk(
            id,
            (rng.nextInt(50000) + 1) / 10,
            cats[rng.nextInt(cats.length)],
            months[rng.nextInt(months.length)],
          );
          live[id] = updated;
          await repo.updateExpense(updated);
        } else {
          // DELETE
          final id = live.keys.elementAt(rng.nextInt(live.length));
          live.remove(id);
          await repo.deleteExpense(id);
        }
      }

      final incremental = await _readRollup(database);

      // No degenerate buckets must survive incremental maintenance.
      for (final entry in incremental.entries) {
        expect(entry.value.count, greaterThan(0),
            reason: 'zero/negative-count bucket should be pruned: ${entry.key}');
        expect(entry.value.total, greaterThanOrEqualTo(0),
            reason: 'negative total leaked: ${entry.key}');
      }

      // Authoritative rebuild from the expenses table.
      await memory.recompute();
      final authoritative = await _readRollup(database);

      _expectRollupsEqual(incremental, authoritative,
          reason: 'incremental drifted from a GROUP BY rebuild');

      // Cross-check against the live model's own aggregation.
      final expected = <String, ({double total, int count})>{};
      for (final e in live.values) {
        final key = '${e.date.substring(0, 7)}|${e.category}';
        final prev = expected[key] ?? (total: 0.0, count: 0);
        expected[key] = (total: prev.total + e.amount, count: prev.count + 1);
      }
      _expectRollupsEqual(incremental, expected,
          reason: 'rollup disagrees with the independent ground-truth model');
    });
  });

  group('cross-device consistency (sync -> rebuild)', () {
    test('device B pulls expenses and rebuilds identical memory facts',
        () async {
      // Device A authors a spread of expenses (also pushed to the fake server).
      final authored = <domain.Expense>[
        mk('a1', 1200, 'Food', '2026-05'),
        mk('a2', 800, 'Food', '2026-06'),
        mk('a3', 450, 'Travel', '2026-06'),
        mk('a4', 300, 'Bills', '2026-04'),
        mk('a5', 999.5, 'Grocery', '2026-06'),
      ];
      for (final e in authored) {
        await repo.addExpense(e);
      }
      final now = DateTime(2026, 6, 26, 12);
      final factsA = await memory.snapshot(now: now);

      // Device B: brand-new DB, only the server pull (no incremental writes).
      final dbB = db.AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(dbB.close);
      final prefsB = await SharedPreferences.getInstance();
      final repoB = ExpenseRepository(dbB, api, prefsB);
      final pulled = await repoB.syncFromServer();
      expect(pulled, authored.length, reason: 'all rows pulled from server');

      final factsB = await ExpenseMemoryService(dbB).snapshot(now: now);

      expect(factsB.lifetimeTotal, closeTo(factsA.lifetimeTotal, 0.001));
      expect(factsB.lifetimeCount, factsA.lifetimeCount);
      expect(factsB.currentMonthTotal, closeTo(factsA.currentMonthTotal, 0.001));
      expect(factsB.previousMonthTotal, closeTo(factsA.previousMonthTotal, 0.001));
      expect(factsB.monthsTracked, factsA.monthsTracked);
      expect(
        factsB.topCategoriesCurrentMonth.map((c) => '${c.category}:${c.total}'),
        factsA.topCategoriesCurrentMonth.map((c) => '${c.category}:${c.total}'),
      );
      expect(
        factsB.monthlyTrend.map((t) => '${t.month}:${t.total}'),
        factsA.monthlyTrend.map((t) => '${t.month}:${t.total}'),
      );
    });
  });

  group('resilience', () {
    test('a backend outage never breaks the local write or its memory delta',
        () async {
      api.failPost = true; // every sync POST throws
      final ok = await repo.addExpense(mk('x1', 500, 'Food', '2026-06'));
      expect(ok, isFalse, reason: 'server sync failed');

      final facts = await memory.snapshot(now: DateTime(2026, 6, 26));
      expect(facts.lifetimeCount, 1, reason: 'local write + memory still applied');
      expect(facts.currentMonthTotal, 500);
    });

    test('clearAllExpenses empties the rollup', () async {
      await repo.addExpense(mk('c1', 100, 'Food', '2026-06'));
      await repo.addExpense(mk('c2', 200, 'Travel', '2026-06'));
      expect((await _readRollup(database)).isNotEmpty, isTrue);

      await repo.clearAllExpenses();
      expect((await _readRollup(database)).isEmpty, isTrue,
          reason: 'derived rollup cleared with the expenses');
    });

    test('memorySnapshot exposed on the repository matches the service',
        () async {
      await repo.addExpense(mk('m1', 700, 'Shopping', '2026-06'));
      final now = DateTime(2026, 6, 26);
      final viaRepo = await repo.memorySnapshot(now: now);
      final viaService = await memory.snapshot(now: now);
      expect(viaRepo.lifetimeTotal, viaService.lifetimeTotal);
      expect(viaRepo.currentMonthTotal, viaService.currentMonthTotal);
    });
  });
}
