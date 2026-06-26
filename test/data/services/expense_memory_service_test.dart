// Tests for the memory layer (continuously-updated rollup) against a REAL
// in-memory Drift DB. Verifies O(1) incremental deltas (add/update/delete +
// category moves), pruning, full recompute, and the derived MemoryFacts
// snapshot (lifetime/month/trend/top-category math).

import 'package:ai_nexus/data/local/database/app_database.dart' as db;
import 'package:ai_nexus/data/services/expense_memory_service.dart';
import 'package:ai_nexus/domain/entities/expense_entities.dart' as domain;
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

domain.Expense _exp({
  required String id,
  required double amount,
  required String category,
  required String date,
  String description = 'x',
}) =>
    domain.Expense(
      id: id,
      amount: amount,
      description: description,
      category: category,
      bank: 'HDFC',
      cardType: 'CC',
      date: date,
      isManualCategory: false,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late db.AppDatabase database;
  late ExpenseMemoryService memory;
  // Fixed "now" so month math is deterministic.
  final now = DateTime(2026, 6, 26, 12);

  setUp(() {
    database = db.AppDatabase.forTesting(NativeDatabase.memory());
    memory = ExpenseMemoryService(database);
  });

  tearDown(() async => database.close());

  group('applyDelta', () {
    test('add accumulates into the (month, category) bucket', () async {
      await memory.applyDelta(
          newExpense: _exp(id: '1', amount: 100, category: 'Food', date: '2026-06-10T09:00:00'));
      await memory.applyDelta(
          newExpense: _exp(id: '2', amount: 250, category: 'Food', date: '2026-06-12T09:00:00'));

      final facts = await memory.snapshot(now: now);
      expect(facts.currentMonthTotal, 350);
      expect(facts.lifetimeCount, 2);
      expect(facts.topCategoriesCurrentMonth.first.category, 'Food');
      expect(facts.topCategoriesCurrentMonth.first.total, 350);
    });

    test('delete decrements and prunes the bucket at zero count', () async {
      final e = _exp(id: '1', amount: 100, category: 'Food', date: '2026-06-10T09:00:00');
      await memory.applyDelta(newExpense: e);
      await memory.applyDelta(oldExpense: e);

      final rows = await database.select(database.expenseMonthlyCategory).get();
      expect(rows, isEmpty, reason: 'bucket pruned when count hits 0');
      final facts = await memory.snapshot(now: now);
      expect(facts.lifetimeCount, 0);
      expect(facts.isEmpty, isTrue);
    });

    test('update moves spend across categories within the same month',
        () async {
      final oldE = _exp(id: '1', amount: 100, category: 'Food', date: '2026-06-10T09:00:00');
      await memory.applyDelta(newExpense: oldE);
      final newE = oldE.copyWith(category: 'Shopping', amount: 120);
      await memory.applyDelta(oldExpense: oldE, newExpense: newE);

      final facts = await memory.snapshot(now: now);
      final cats = {
        for (final c in facts.topCategoriesCurrentMonth) c.category: c.total
      };
      expect(cats.containsKey('Food'), isFalse, reason: 'old category emptied');
      expect(cats['Shopping'], 120);
      expect(facts.lifetimeCount, 1);
    });

    test('malformed date is ignored (never corrupts the rollup)', () async {
      await memory.applyDelta(
          newExpense: _exp(id: 'bad', amount: 99, category: 'Food', date: ''));
      final rows = await database.select(database.expenseMonthlyCategory).get();
      expect(rows, isEmpty);
    });
  });

  group('snapshot facts', () {
    test('month-over-month + lifetime + averages are correct', () async {
      // May (previous month): 400; June (current): 900 across two categories.
      await memory.applyDelta(
          newExpense: _exp(id: 'a', amount: 400, category: 'Bills', date: '2026-05-05T10:00:00'));
      await memory.applyDelta(
          newExpense: _exp(id: 'b', amount: 600, category: 'Food', date: '2026-06-03T10:00:00'));
      await memory.applyDelta(
          newExpense: _exp(id: 'c', amount: 300, category: 'Travel', date: '2026-06-20T10:00:00'));

      final f = await memory.snapshot(now: now);
      expect(f.currentMonthTotal, 900);
      expect(f.previousMonthTotal, 400);
      expect(f.momDelta, 500);
      expect(f.lifetimeTotal, 1300);
      expect(f.monthsTracked, 2);
      expect(f.avgMonthlyTotal, closeTo(650, 0.01));
      // Current month top category is Food (600 > 300).
      expect(f.topCategoriesCurrentMonth.first.category, 'Food');
      // Trend is chronological, oldest first.
      expect(f.monthlyTrend.map((t) => t.month).toList(), ['2026-05', '2026-06']);
    });
  });

  group('recompute', () {
    test('rebuilds the rollup exactly from the expenses table', () async {
      // Insert rows directly (bypassing applyDelta) then recompute.
      await database.into(database.expenses).insert(db.ExpensesCompanion.insert(
            id: '1',
            amount: 500,
            description: 'a',
            category: 'Food',
            bank: 'HDFC',
            cardType: 'CC',
            date: '2026-06-01T10:00:00',
            isManualCategory: const Value(false),
          ));
      await database.into(database.expenses).insert(db.ExpensesCompanion.insert(
            id: '2',
            amount: 250,
            description: 'b',
            category: 'Food',
            bank: 'HDFC',
            cardType: 'CC',
            date: '2026-06-02T10:00:00',
            isManualCategory: const Value(false),
          ));

      // Stale rollup should be fully replaced.
      await memory.applyDelta(
          newExpense: _exp(id: 'stale', amount: 9999, category: 'Bills', date: '2026-06-01T10:00:00'));
      await memory.recompute();

      final f = await memory.snapshot(now: now);
      expect(f.currentMonthTotal, 750);
      expect(f.lifetimeCount, 2);
      expect(f.topCategoriesCurrentMonth.length, 1);
      expect(f.topCategoriesCurrentMonth.first.category, 'Food');
    });
  });
}
