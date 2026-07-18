// Verifies the v9 → v10 Drift migration that introduces `expenses.updated_at`.
//
// We hand-build a v9-shaped database on disk (expenses table WITHOUT the
// updated_at column, user_version = 9, with a seeded row), then open it through
// the real [AppDatabase] (schemaVersion 10). Drift must run `onUpgrade` and
// `ALTER TABLE expenses ADD COLUMN updated_at` — preserving the existing row
// (with a NULL updatedAt) and accepting new writes that carry a timestamp.

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
// sqlite3 is drift's own transitive engine; used here only to forge a v9 DB.
// ignore: depend_on_referenced_packages
import 'package:sqlite3/sqlite3.dart' as sqlite;

import 'package:ai_nexus/data/local/database/app_database.dart' as db;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late File file;

  setUp(() {
    final dir = Directory.systemTemp.createTempSync('ai_nexus_mig_v9');
    file = File('${dir.path}/app.db');
  });

  tearDown(() {
    try {
      if (file.existsSync()) file.deleteSync();
      file.parent.deleteSync(recursive: true);
    } catch (_) {}
  });

  void buildV9(File f) {
    final raw = sqlite.sqlite3.open(f.path);
    // v9 expenses shape: everything EXCEPT updated_at (snake_case, as drift
    // generates). PK on id; comments added in v7, defaults to ''.
    raw.execute('''
      CREATE TABLE expenses (
        id TEXT NOT NULL,
        amount REAL NOT NULL,
        description TEXT NOT NULL,
        category TEXT NOT NULL,
        bank TEXT NOT NULL,
        card_type TEXT NOT NULL,
        date TEXT NOT NULL,
        is_manual_category INTEGER NOT NULL DEFAULT 0,
        comments TEXT NOT NULL DEFAULT '',
        PRIMARY KEY (id)
      );
    ''');
    raw.execute('''
      INSERT INTO expenses
        (id, amount, description, category, bank, card_type, date,
         is_manual_category, comments)
      VALUES
        ('legacy-1', 123.5, 'old coffee', 'Food', 'HDFC', 'CC',
         '2026-06-01T09:00:00.000', 0, 'pre-migration note');
    ''');
    raw.execute('PRAGMA user_version = 9;');
    raw.dispose();
  }

  test('adds updated_at, preserves the legacy row, and is queryable at v10',
      () async {
    buildV9(file);

    final database = db.AppDatabase.forTesting(NativeDatabase(file));
    addTearDown(() async => database.close());

    // Opening triggers onUpgrade(9 → 10). The legacy row must survive intact,
    // with a NULL updatedAt (treated as "oldest" by the merge).
    final legacy = await (database.select(database.expenses)
          ..where((t) => t.id.equals('legacy-1')))
        .getSingleOrNull();

    expect(legacy, isNotNull);
    expect(legacy!.amount, 123.5);
    expect(legacy.comments, 'pre-migration note');
    expect(legacy.updatedAt, isNull);

    // The new column accepts writes (proves the ALTER actually landed).
    await database.into(database.expenses).insert(
          db.ExpensesCompanion.insert(
            id: 'post-1',
            amount: 50,
            description: 'new tea',
            category: 'Food',
            bank: 'ICICI',
            cardType: 'DB',
            date: '2026-06-27T09:00:00.000',
            updatedAt: const Value('2026-06-27T03:30:00.000Z'),
          ),
        );

    final fresh = await (database.select(database.expenses)
          ..where((t) => t.id.equals('post-1')))
        .getSingleOrNull();
    expect(fresh, isNotNull);
    expect(fresh!.updatedAt, '2026-06-27T03:30:00.000Z');

    // Schema is fully at v10.
    expect(database.schemaVersion, 10);
  });

  test('updated_at column is exposed in the live PRAGMA after upgrade',
      () async {
    buildV9(file);
    final database = db.AppDatabase.forTesting(NativeDatabase(file));
    addTearDown(() async => database.close());

    final cols = await database
        .customSelect('PRAGMA table_info(expenses)')
        .get();
    final names = cols.map((r) => r.read<String>('name')).toSet();
    expect(names.contains('updated_at'), isTrue);
    expect(names.contains('comments'), isTrue);
  });
}
