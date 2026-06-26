import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import 'connection/connection.dart' as connection;

part 'app_database.g.dart';

class Expenses extends Table {
  TextColumn get id => text()();
  RealColumn get amount => real()();
  TextColumn get description => text()();
  TextColumn get category => text()();
  TextColumn get bank => text()();
  TextColumn get cardType => text()();
  TextColumn get date => text()();
  BoolColumn get isManualCategory =>
      boolean().withDefault(const Constant(false))();

  /// Optional free-form note/reminder attached at log time (manual, voice, or
  /// PDF/scan flows). NULL/'' = no comment. Local-only-friendly: synced when the
  /// backend supports it, otherwise preserved locally.
  TextColumn get comments => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {id};
}

class BudgetEntries extends Table {
  TextColumn get id => text()();
  RealColumn get amount => real()();
  TextColumn get setAt => text()();

  @override
  Set<Column> get primaryKey => {id};
}

/// One in-hand salary entry per calendar month. [month] is the canonical
/// 'YYYY-MM' key and is the primary key, so re-entering a month's salary simply
/// upserts (the monthly "reset" the user wants). [setAt] is an ISO-8601 UTC
/// timestamp of when it was entered/updated.
class SalaryEntries extends Table {
  TextColumn get id => text()();
  TextColumn get month => text()();
  RealColumn get amount => real()();
  TextColumn get setAt => text()();

  @override
  Set<Column> get primaryKey => {month};
}

/// Continuously-updated rollup of spend per (month, category) — the "memory
/// layer". Instead of scanning the (potentially huge) `expenses` table to build
/// AI context, we maintain these compact aggregates incrementally on every
/// write, so a "facts" snapshot for the recommendation engine is constant-cost
/// regardless of how many base rows exist (scales to billions).
///
/// [month] is the 'YYYY-MM' prefix of an expense `date`; [category] the
/// expense category. [total] is the summed amount and [count] the number of
/// expenses in that bucket. The memory service prunes buckets once their
/// [count] reaches 0. This is intentionally local-only (never synced): it is a
/// derived cache that can always be rebuilt from `expenses`.
class ExpenseMonthlyCategory extends Table {
  TextColumn get month => text()();
  TextColumn get category => text()();
  RealColumn get total => real().withDefault(const Constant(0))();
  IntColumn get count => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {month, category};
}

class NewsArticles extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get excerpt => text()();
  TextColumn get source => text()();
  TextColumn get category => text()();
  TextColumn get imageUrl => text()();
  IntColumn get readTime => integer()();
  TextColumn get date => text()();
  TextColumn get blocksJson => text()();
  BoolColumn get isSaved => boolean().withDefault(const Constant(false))();
  BoolColumn get isRead => boolean().withDefault(const Constant(false))();

  /// AI-generated 1-2 sentence quick summary used by the For You "Summarize"
  /// action. NULL = not yet summarized. Cached forever per article so re-opening
  /// the summary reader is instant for already-processed items.
  TextColumn get summaryShort => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class CloudFiles extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get type => text()();
  IntColumn get sizeBytes => integer()();
  TextColumn get uploadDate => text()();
  BoolColumn get isStarred => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

class SavedWords extends Table {
  TextColumn get id => text()();
  TextColumn get word => text()();
  TextColumn get definition => text()();
  TextColumn get pronunciation => text()();
  TextColumn get partOfSpeech => text()();
  TextColumn get savedAt => text()();
  TextColumn get responseJson => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {id};
}

class SyncQueue extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  TextColumn get action => text()();
  TextColumn get payload => text()();
  TextColumn get createdAt => text()();
  BoolColumn get synced => boolean().withDefault(const Constant(false))();
}

class ArticleChatMessages extends Table {
  TextColumn get id => text()();
  TextColumn get articleId => text()();
  TextColumn get role => text()();
  TextColumn get msgText => text()();
  TextColumn get model => text().withDefault(const Constant(''))();
  TextColumn get sourcesJson => text().withDefault(const Constant('[]'))();
  TextColumn get createdAt => text()();

  @override
  Set<Column> get primaryKey => {id};
}

class ArticleChatSummaries extends Table {
  TextColumn get articleId => text()();
  TextColumn get summaryText => text()();
  IntColumn get pairsCovered => integer()();
  TextColumn get updatedAt => text()();

  @override
  Set<Column> get primaryKey => {articleId};
}

class CategoryLearnings extends Table {
  TextColumn get keyword => text()();
  TextColumn get category => text()();

  @override
  Set<Column> get primaryKey => {keyword};
}

/// Persistent snapshot of an InsightAI search or URL summary the user has
/// explicitly bookmarked. The full DTO is stored as JSON in [responseJson]
/// keyed by [responseType] so the on-disk shape can absorb future result
/// kinds (e.g. deep research) without a schema migration.
class SavedSearches extends Table {
  TextColumn get id => text()();

  /// 'url' for URL-summarize entries, 'query' for text search entries.
  TextColumn get kind => text()();

  /// The original input text (URL or query).
  TextColumn get query => text()();

  /// Display title derived at save time (URL hostname or first 80 chars).
  TextColumn get title => text()();

  /// Discriminator for [responseJson]: 'summarizer' | 'grounded' | 'tavily'.
  TextColumn get responseType => text()();

  /// Full serialized response DTO. Kept opaque at the DB layer so result
  /// shape evolution doesn't require migrations.
  TextColumn get responseJson => text()();

  TextColumn get model => text().withDefault(const Constant(''))();
  TextColumn get provider => text().withDefault(const Constant(''))();
  TextColumn get mode => text().withDefault(const Constant(''))();

  /// ISO-8601 UTC timestamp.
  TextColumn get savedAt => text()();

  /// ISO-8601 UTC timestamp; bumped whenever a follow-up message is appended
  /// so the History list can sort by activity.
  TextColumn get updatedAt => text()();

  /// Reserved for future filter / cleanup logic. Defaults to true on save.
  BoolColumn get pinned => boolean().withDefault(const Constant(true))();

  /// Soft-delete tombstone — set when the user deletes locally; the row is
  /// hard-deleted only after the remote DELETE is acknowledged. Lets sync
  /// be eventual-consistent without losing remote rows on transient errors.
  TextColumn get deletedAt => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Mirror of [ArticleChatMessages] keyed on [searchId] instead of articleId.
/// Same shape so the wire format and persistence semantics are identical to
/// the proven article-chats path.
class SavedSearchChatMessages extends Table {
  TextColumn get id => text()();
  TextColumn get searchId => text()();
  TextColumn get role => text()();
  TextColumn get msgText => text()();
  TextColumn get model => text().withDefault(const Constant(''))();
  TextColumn get sourcesJson => text().withDefault(const Constant('[]'))();
  TextColumn get createdAt => text()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Mirror of [ArticleChatSummaries] keyed on [searchId].
class SavedSearchChatSummaries extends Table {
  TextColumn get searchId => text()();
  TextColumn get summaryText => text()();
  IntColumn get pairsCovered => integer()();
  TextColumn get updatedAt => text()();

  @override
  Set<Column> get primaryKey => {searchId};
}

@DriftDatabase(
  tables: [
    Expenses,
    BudgetEntries,
    SalaryEntries,
    ExpenseMonthlyCategory,
    NewsArticles,
    CloudFiles,
    SavedWords,
    SyncQueue,
    CategoryLearnings,
    ArticleChatMessages,
    ArticleChatSummaries,
    SavedSearches,
    SavedSearchChatMessages,
    SavedSearchChatSummaries,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(connection.openAppConnection());

  AppDatabase.background() : super(connection.openBackgroundConnection());

  /// Test-only constructor that lets unit tests inject an in-memory
  /// [QueryExecutor]. Production code paths must continue to use
  /// [AppDatabase] / [AppDatabase.background] so the platform-specific
  /// connection factories stay the source of truth.
  @visibleForTesting
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 9;

  /// Atomically deletes **every row from every table** while leaving the
  /// schema (tables, columns, indexes) fully intact. Powers the "nuke" easter
  /// egg full-reset: the app returns to a pristine first-launch data state
  /// without a destructive migration. Wrapped in a single transaction so the
  /// wipe is all-or-nothing — a failure mid-way rolls back rather than leaving
  /// the DB half-cleared.
  Future<void> wipeAllRows() async {
    await transaction(() async {
      for (final table in allTables) {
        await delete(table).go();
      }
    });
  }

  /// Cheap `COUNT(*)` of the user-facing data tables, keyed by a friendly
  /// label. Used by the nuke "what was cleared" window so it can report real
  /// numbers. Derived caches / queues (memory rollup, sync queue, chat
  /// mirrors) are intentionally excluded — they aren't user content.
  Future<Map<String, int>> dataRowCounts() async {
    Future<int> countOf(String tableName) async {
      final row = await customSelect('SELECT COUNT(*) AS c FROM $tableName')
          .getSingleOrNull();
      return row?.read<int>('c') ?? 0;
    }

    return {
      'Expenses': await countOf('expenses'),
      'Budget history': await countOf('budget_entries'),
      'Salary': await countOf('salary_entries'),
      'News': await countOf('news_articles'),
      'Saved words': await countOf('saved_words'),
      'Cloud files': await countOf('cloud_files'),
      'Saved searches': await countOf('saved_searches'),
      'Learnings': await countOf('category_learnings'),
    };
  }

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (migrator, from, to) async {
      if (from < 2) {
        await migrator.addColumn(savedWords, savedWords.responseJson);
      }
      if (from < 3) {
        await migrator.createTable(articleChatMessages);
      }
      if (from < 4) {
        await migrator.createTable(articleChatSummaries);
      }
      if (from < 5) {
        await migrator.addColumn(newsArticles, newsArticles.summaryShort);
      }
      if (from < 6) {
        await migrator.createTable(savedSearches);
        await migrator.createTable(savedSearchChatMessages);
        await migrator.createTable(savedSearchChatSummaries);
      }
      if (from < 7) {
        await migrator.addColumn(expenses, expenses.comments);
      }
      if (from < 8) {
        await migrator.createTable(salaryEntries);
      }
      if (from < 9) {
        // Memory layer: create the rollup table and backfill it once from the
        // existing expenses in a single GROUP BY (one-time cost). From here on
        // it is maintained incrementally by ExpenseMemoryService on each write.
        await migrator.createTable(expenseMonthlyCategory);
        await customStatement(
          'INSERT INTO expense_monthly_category (month, category, total, count) '
          'SELECT substr(date, 1, 7) AS month, category, '
          'SUM(amount) AS total, COUNT(id) AS count '
          'FROM expenses '
          'WHERE date IS NOT NULL AND length(date) >= 7 '
          'GROUP BY substr(date, 1, 7), category',
        );
      }
    },
    beforeOpen: (details) async {
      // Index the expenses date column so timeframe drill-down range queries
      // (ORDER BY date DESC + range filter) stay fluid even with very large
      // histories. IF NOT EXISTS keeps this idempotent on every open.
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_expenses_date ON expenses (date)',
      );
    },
  );
}
