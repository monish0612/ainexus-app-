// Tests for the "nuke" full-reset DB primitives:
//   • AppDatabase.wipeAllRows() — clears every table's ROWS while preserving
//     the schema (tables/columns survive, so the app keeps working).
//   • AppDatabase.dataRowCounts() — accurate pre-wipe telemetry.
//
// Runs against a REAL in-memory Drift DB so the SQL (DELETE per table,
// COUNT(*) per table) is exercised exactly as in production.

import 'package:ai_nexus/data/local/database/app_database.dart' as db;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late db.AppDatabase database;

  setUp(() {
    database = db.AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
  });

  Future<void> seed() async {
    await database.into(database.expenses).insert(
          db.ExpensesCompanion.insert(
            id: 'e1',
            amount: 250,
            description: 'Lunch',
            category: 'Food',
            bank: 'HDFC',
            cardType: 'CC',
            date: '2026-06-26T10:00:00.000Z',
          ),
        );
    await database.into(database.budgetEntries).insert(
          db.BudgetEntriesCompanion.insert(
            id: 'b1',
            amount: 5000,
            setAt: '2026-06-01T00:00:00.000Z',
          ),
        );
    await database.into(database.salaryEntries).insert(
          db.SalaryEntriesCompanion.insert(
            month: '2026-06',
            id: 's1',
            amount: 80000,
            setAt: '2026-06-01T00:00:00.000Z',
          ),
        );
    await database.into(database.savedWords).insert(
          db.SavedWordsCompanion.insert(
            id: 'w1',
            word: 'ephemeral',
            definition: 'lasting a very short time',
            pronunciation: '',
            partOfSpeech: 'adj',
            savedAt: '2026-06-26T10:00:00.000Z',
          ),
        );
    await database.into(database.categoryLearnings).insert(
          db.CategoryLearningsCompanion.insert(
            keyword: 'swiggy',
            category: 'Food',
          ),
        );
  }

  test('dataRowCounts reports real per-table counts before a wipe', () async {
    await seed();
    final counts = await database.dataRowCounts();
    expect(counts['Expenses'], 1);
    expect(counts['Budget history'], 1);
    expect(counts['Salary'], 1);
    expect(counts['Saved words'], 1);
    expect(counts['Learnings'], 1);
    expect(counts['News'], 0);
  });

  test('wipeAllRows clears every table but preserves the schema', () async {
    await seed();

    await database.wipeAllRows();

    // Every data table is empty…
    final after = await database.dataRowCounts();
    expect(after.values.every((c) => c == 0), isTrue,
        reason: 'all rows removed across every table');

    // …and the schema still works — we can insert again with no migration.
    await database.into(database.expenses).insert(
          db.ExpensesCompanion.insert(
            id: 'e2',
            amount: 99,
            description: 'Coffee',
            category: 'Food',
            bank: 'ICICI',
            cardType: 'UPI',
            date: '2026-06-27T09:00:00.000Z',
          ),
        );
    final rows = await database.select(database.expenses).get();
    expect(rows.length, 1, reason: 'table is reusable post-wipe');
    expect(rows.single.id, 'e2');
  });

  test('wipeAllRows on an already-empty DB is a no-op (idempotent)', () async {
    await database.wipeAllRows();
    final counts = await database.dataRowCounts();
    expect(counts.values.every((c) => c == 0), isTrue);
  });
}
