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

  /// ISO-8601 UTC timestamp of the last local OR remote write to this row. Used
  /// for last-write-wins cross-device merge in [ExpenseRepository.syncFromServer]
  /// — a server row only overwrites the local copy when its [updatedAt] is newer.
  /// NULL on rows created before the v10 migration (treated as "oldest").
  TextColumn get updatedAt => text().nullable()();

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

/// Live price-watch products. Identity for future cloud merge is
/// [identityKey] (`store:productId`), not the local UUID.
class WatchProducts extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get url => text()();
  TextColumn get canonicalUrl => text()();
  TextColumn get store => text()();
  TextColumn get productId => text().nullable()();
  TextColumn get imageUrl => text().withDefault(const Constant(''))();
  RealColumn get currentPrice => real()();
  RealColumn get basePrice => real()();
  TextColumn get lastChecked => text()();
  TextColumn get createdAt => text()();
  RealColumn get targetPrice => real().nullable()();
  BoolColumn get notifyOnDecrease =>
      boolean().withDefault(const Constant(true))();
  BoolColumn get notifyOnIncrease =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get notifyOnTarget =>
      boolean().withDefault(const Constant(true))();
  IntColumn get checkIntervalMinutes =>
      integer().withDefault(const Constant(60))();
  BoolColumn get isPaused => boolean().withDefault(const Constant(false))();
  BoolColumn get isPinned => boolean().withDefault(const Constant(false))();
  BoolColumn get manuallyPaused =>
      boolean().withDefault(const Constant(false))();
  TextColumn get pausedAt => text().nullable()();
  TextColumn get pinnedAt => text().nullable()();
  RealColumn get pendingPrice => real().nullable()();
  TextColumn get pendingPriceAt => text().nullable()();
  IntColumn get consecutiveFailures =>
      integer().withDefault(const Constant(0))();
  TextColumn get lastCheckError => text().nullable()();
  TextColumn get availability => text().nullable()();
  TextColumn get currencyCode => text().withDefault(const Constant('INR'))();
  TextColumn get lastSource => text().withDefault(const Constant(''))();
  IntColumn get lastScore => integer().withDefault(const Constant(0))();

  /// `store:productId` (or `store:url:…` until the SKU is known). Same
  /// SKU on two phones merges on this key, not the local UUID.
  TextColumn get identityKey => text().withDefault(const Constant(''))();

  /// ISO-8601 UTC of the last local write. Last-write-wins when a cloud
  /// catalog exists. NULL on rows created before the v12 migration.
  TextColumn get updatedAt => text().nullable()();

  /// Bumped on every local mutation so a later sync can collapse upserts.
  IntColumn get rev => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
        {canonicalUrl},
      ];
}

class WatchPriceHistory extends Table {
  TextColumn get id => text()();
  TextColumn get productId => text()();
  RealColumn get price => real()();
  TextColumn get checkedAt => text()();
  TextColumn get source => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {id};
}

class WatchAlerts extends Table {
  TextColumn get id => text()();
  TextColumn get productId => text()();
  TextColumn get productName => text()();
  TextColumn get imageUrl => text().withDefault(const Constant(''))();
  RealColumn get oldPrice => real()();
  RealColumn get newPrice => real()();
  TextColumn get reason => text()();
  TextColumn get createdAt => text()();
  BoolColumn get isRead => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Cloud-ready delete markers. Local delete writes one of these even while
/// [NoopWatchSync] drains nothing.
class WatchTombstones extends Table {
  TextColumn get identityKey => text()();
  TextColumn get deletedAt => text()();

  @override
  Set<Column> get primaryKey => {identityKey};
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
    WatchProducts,
    WatchPriceHistory,
    WatchAlerts,
    WatchTombstones,
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
  int get schemaVersion => 12;

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
      'Watch': await countOf('watch_products'),
    };
  }

  // ── Durable sync queue ──────────────────────────────────────────────────
  // A persisted outbox so offline writes survive an app kill and auto-push on
  // reconnect (true offline-first), unlike pure inline retry which is lost once
  // the in-memory retries are exhausted.

  /// Enqueue (or replace) a pending server write. Keyed on
  /// (entityType, entityId, action) so re-saving the same entity while offline
  /// collapses to a single latest payload instead of stacking duplicates.
  Future<void> enqueueSync({
    required String entityType,
    required String entityId,
    required String action,
    required String payload,
  }) async {
    await transaction(() async {
      await (delete(syncQueue)
            ..where((t) =>
                t.entityType.equals(entityType) &
                t.entityId.equals(entityId) &
                t.action.equals(action)))
          .go();
      await into(syncQueue).insert(
        SyncQueueCompanion.insert(
          entityType: entityType,
          entityId: entityId,
          action: action,
          payload: payload,
          createdAt: DateTime.now().toUtc().toIso8601String(),
        ),
      );
    });
  }

  /// All un-synced queued writes for a given entity type, oldest first.
  Future<List<SyncQueueData>> pendingSyncItems(String entityType) {
    return (select(syncQueue)
          ..where((t) => t.entityType.equals(entityType) & t.synced.equals(false))
          ..orderBy([(t) => OrderingTerm(expression: t.createdAt)]))
        .get();
  }

  /// Remove a queued write once it has been pushed successfully.
  Future<void> deleteSyncItem(int id) =>
      (delete(syncQueue)..where((t) => t.id.equals(id))).go();

  /// Drop every queued write for an entity type — used when that domain is
  /// cleared/nuked so a stale queued upsert can't resurrect the data.
  Future<void> purgeSyncByType(String entityType) =>
      (delete(syncQueue)..where((t) => t.entityType.equals(entityType))).go();

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
      if (from < 10) {
        // Cross-device last-write-wins merge needs a per-row updatedAt. Pre-
        // existing rows get NULL (treated as "oldest"); since every local
        // expense was already pushed to the server when created, the first
        // post-upgrade pull simply re-applies identical server data — no loss.
        await migrator.addColumn(expenses, expenses.updatedAt);
      }
      if (from < 11) {
        await migrator.createTable(watchProducts);
        await migrator.createTable(watchPriceHistory);
        await migrator.createTable(watchAlerts);
      }
      if (from < 12) {
        if (!await _hasColumn('watch_products', 'identity_key')) {
          await customStatement(
            "ALTER TABLE watch_products ADD COLUMN identity_key TEXT NOT NULL DEFAULT ''",
          );
        }
        if (!await _hasColumn('watch_products', 'updated_at')) {
          await customStatement(
            'ALTER TABLE watch_products ADD COLUMN updated_at TEXT NULL',
          );
        }
        if (!await _hasColumn('watch_products', 'rev')) {
          await customStatement(
            'ALTER TABLE watch_products ADD COLUMN rev INTEGER NOT NULL DEFAULT 0',
          );
        }
        await migrator.createTable(watchTombstones);
        await customStatement(
          "UPDATE watch_products SET identity_key = store || ':' || "
          "COALESCE(NULLIF(product_id, ''), canonical_url) "
          "WHERE identity_key IS NULL OR identity_key = ''",
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
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_watch_history_product '
        'ON watch_price_history (product_id, checked_at)',
      );
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_watch_alerts_product '
        'ON watch_alerts (product_id, created_at)',
      );
      await customStatement(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_watch_identity '
        'ON watch_products (identity_key)',
      );
    },
  );

  Future<bool> _hasColumn(String table, String column) async {
    final rows = await customSelect('PRAGMA table_info($table)').get();
    return rows.any((r) => r.read<String>('name') == column);
  }
}
