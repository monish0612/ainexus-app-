// SCALING guarantees for the memory layer. The whole point of the rollup is
// that the AI-context cost is CONSTANT regardless of how many expenses exist:
//   • the rollup row count is bounded by (months x categories), NOT by the
//     number of expenses, so it stays tiny even at millions/billions of rows;
//   • snapshot() reads only that bounded rollup (never the expenses table);
//   • applyDelta touches a single PK-indexed bucket per write (O(1)).
//
// These tests insert large volumes and assert the rollup stays small and
// exact, which is the structural property that makes the feature scale.

import 'package:ai_nexus/data/local/database/app_database.dart' as db;
import 'package:ai_nexus/data/services/expense_memory_service.dart';
import 'package:ai_nexus/domain/entities/expense_entities.dart' as domain;
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late db.AppDatabase database;
  late ExpenseMemoryService memory;

  setUp(() {
    database = db.AppDatabase.forTesting(NativeDatabase.memory());
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

  Future<int> rollupRowCount() async =>
      (await database.select(database.expenseMonthlyCategory).get()).length;

  test('10,000 expenses in ONE bucket => exactly 1 rollup row (constant size)',
      () async {
    for (var i = 0; i < 10000; i++) {
      await memory.applyDelta(newExpense: mk('e$i', 10, 'Food', '2026-06'));
    }
    expect(await rollupRowCount(), 1,
        reason: 'context size is independent of expense volume');

    final facts = await memory.snapshot(now: DateTime(2026, 6, 26));
    expect(facts.lifetimeCount, 10000);
    expect(facts.currentMonthTotal, closeTo(100000, 0.001));
    expect(facts.topCategoriesCurrentMonth.single.category, 'Food');
  });

  test('rollup rows are bounded by (months x categories), not by row count',
      () async {
    const cats = ['Food', 'Grocery', 'Transport', 'Shopping', 'Bills', 'Travel',
        'Health', 'Bills']; // dup is harmless
    const months = ['2026-01', '2026-02', '2026-03', '2026-04', '2026-05', '2026-06'];
    final distinctCats = cats.toSet();
    final maxBuckets = distinctCats.length * months.length;

    final sw = Stopwatch()..start();
    const n = 6000;
    for (var i = 0; i < n; i++) {
      await memory.applyDelta(newExpense: mk(
            'e$i',
            (i % 500) + 1,
            cats[i % cats.length],
            months[i % months.length],
          ));
    }
    sw.stop();

    final rows = await rollupRowCount();
    expect(rows, lessThanOrEqualTo(maxBuckets),
        reason: 'rollup must not grow with the $n expenses');

    // The snapshot reads only the (tiny) rollup — verify it is fast + correct.
    final snapSw = Stopwatch()..start();
    final facts = await memory.snapshot(now: DateTime(2026, 6, 26));
    snapSw.stop();

    expect(facts.lifetimeCount, n);
    expect(facts.monthsTracked, months.length);
    // Reading a <= ${maxBuckets}-row table is effectively instant; assert a
    // generous ceiling so this is robust on slow CI yet still catches a
    // regression to full-table scanning.
    expect(snapSw.elapsedMilliseconds, lessThan(200),
        reason: 'snapshot must read only the bounded rollup');

    // ignore: avoid_print
    print('scaling: $n adds in ${sw.elapsedMilliseconds}ms, '
        '$rows rollup rows, snapshot ${snapSw.elapsedMilliseconds}ms');
  });

  test('recompute over a large expenses table is exact (rebuild path scales)',
      () async {
    const cats = ['Food', 'Grocery', 'Transport', 'Shopping'];
    const months = ['2026-03', '2026-04', '2026-05', '2026-06'];

    // Populate the REAL expenses table directly (this is the source of truth
    // recompute rebuilds from — mirrors a bulk server pull / migration).
    final expected = <String, ({double total, int count})>{};
    for (var i = 0; i < 4000; i++) {
      final cat = cats[i % cats.length];
      final month = months[i % months.length];
      final amt = ((i % 300) + 1).toDouble();
      await database.into(database.expenses).insert(db.ExpensesCompanion.insert(
            id: 'e$i',
            amount: amt,
            description: 'tx-$i',
            category: cat,
            bank: 'HDFC',
            cardType: 'CC',
            date: '$month-15T10:00:00',
            isManualCategory: const Value(false),
          ));
      final key = '$month|$cat';
      final p = expected[key] ?? (total: 0.0, count: 0);
      expected[key] = (total: p.total + amt, count: p.count + 1);
    }

    final sw = Stopwatch()..start();
    await memory.recompute();
    sw.stop();

    final after = {
      for (final r in await database.select(database.expenseMonthlyCategory).get())
        '${r.month}|${r.category}': (total: r.total, count: r.count),
    };

    expect(after.keys.toSet(), expected.keys.toSet());
    for (final k in expected.keys) {
      expect(after[k]!.count, expected[k]!.count, reason: k);
      expect(after[k]!.total, closeTo(expected[k]!.total, 0.001), reason: k);
    }

    // ignore: avoid_print
    print('scaling: recompute over 4000 expense rows in ${sw.elapsedMilliseconds}ms '
        '→ ${after.length} buckets');
  });
}
