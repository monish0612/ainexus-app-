import 'dart:math' as math;

import 'package:drift/drift.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_endpoints.dart';
import '../../core/services/telegram_logger.dart';
import '../../domain/entities/expense_entities.dart' as domain;
import '../local/database/app_database.dart' as db;
import '../services/expense_memory_service.dart';

/// Ordering options for [ExpenseRepository.getExpensesPage]. Newest-first is
/// the default; amount ordering powers AI queries like "highest expense".
enum ExpenseSort { dateDesc, dateAsc, amountDesc, amountAsc }

/// Visualization the AI search may request. [none] renders the plain list.
enum ExpenseChart { none, category, daily, monthly }

/// A single aggregated time bucket (day or month) for chart visualizations.
typedef ExpenseBucket = ({String bucket, double total, int count});

class ExpenseRepository {
  ExpenseRepository(this._db, this._api, this._prefs);

  final db.AppDatabase _db;
  final ApiClient _api;
  final SharedPreferences _prefs;

  /// Continuously-updated aggregate cache used by the AI insight engine.
  /// Owned internally (only needs the DB) so the public constructor stays
  /// unchanged and existing call sites/tests keep working.
  late final ExpenseMemoryService _memory = ExpenseMemoryService(_db);

  /// Compact, billions-scale-safe snapshot of all spending for the AI
  /// recommendation engine. Derived from the small rollup, so it is instant.
  Future<MemoryFacts> memorySnapshot({DateTime? now}) =>
      _memory.snapshot(now: now);

  /// Best-effort: keep the memory layer from breaking a real expense write.
  /// The rollup is a derived cache, so a failure here is logged and ignored —
  /// it can always be rebuilt via [_memory.recompute].
  Future<void> _safeApplyMemory({
    domain.Expense? oldExpense,
    domain.Expense? newExpense,
  }) async {
    try {
      await _memory.applyDelta(oldExpense: oldExpense, newExpense: newExpense);
    } catch (e) {
      TLog.w('ExpenseRepo', 'Memory delta failed (non-fatal)', error: e);
    }
  }

  Future<void> _safeRecomputeMemory() async {
    try {
      await _memory.recompute();
    } catch (e) {
      TLog.w('ExpenseRepo', 'Memory recompute failed (non-fatal)', error: e);
    }
  }

  static const _uuid = Uuid();

  static const _pendingClearExpensesKey = 'pending_clear_expenses';
  static const _pendingClearBudgetKey = 'pending_clear_budget';
  static const _pendingClearLearningsKey = 'pending_clear_learnings';

  Stream<List<domain.Expense>> watchExpenses() {
    return (_db.select(_db.expenses)
          ..orderBy([
            (t) => OrderingTerm(expression: t.date, mode: OrderingMode.desc),
          ]))
        .watch()
        .map((rows) => rows.map(_rowToExpense).toList());
  }

  // ── Sync retry helpers ──────────────────────────────────────────────────

  Future<void> _syncPostWithRetry(
    String endpoint, {
    required Map<String, dynamic> data,
    int maxAttempts = 3,
  }) async {
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        await _api.post<Object?>(endpoint, data: data);
        return;
      } catch (e) {
        if (attempt == maxAttempts) rethrow;
        TLog.d('ExpenseRepo', 'POST retry $attempt/$maxAttempts → $endpoint');
        await Future<void>.delayed(Duration(milliseconds: 400 * attempt));
      }
    }
  }

  Future<void> _syncDeleteWithRetry(
    String endpoint, {
    int maxAttempts = 3,
  }) async {
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        await _api.delete<Object?>(endpoint);
        return;
      } catch (e) {
        if (attempt == maxAttempts) rethrow;
        TLog.d('ExpenseRepo', 'DELETE retry $attempt/$maxAttempts → $endpoint');
        await Future<void>.delayed(Duration(milliseconds: 400 * attempt));
      }
    }
  }

  /// Returns `true` if server sync succeeded, `false` if it failed.
  Future<bool> addExpense(domain.Expense expense) async {
    try {
      await _db.into(_db.expenses).insert(_expenseToCompanion(expense));
      TLog.i('ExpenseRepo',
          '💰 Saved: ₹${expense.amount.toStringAsFixed(0)} | ${expense.description} | ${expense.category} | ${expense.bank}/${expense.cardType}');
    } catch (e) {
      TLog.e('ExpenseRepo', 'Local insert failed', error: e);
      rethrow;
    }

    await _safeApplyMemory(newExpense: expense);

    try {
      await _syncPostWithRetry(ApiEndpoints.expenses, data: expense.toJson());
      TLog.i('ExpenseRepo',
          '☁️ Synced add: ₹${expense.amount.toStringAsFixed(0)} | ${expense.description}');
      return true;
    } catch (e) {
      TLog.w('ExpenseRepo',
          'Expense sync (add) failed after retries: ₹${expense.amount.toStringAsFixed(0)} | ${expense.description}',
          error: e);
      return false;
    }
  }

  Future<bool> updateExpense(domain.Expense expense) async {
    domain.Expense? previous;
    try {
      final oldRow = await (_db.select(_db.expenses)
            ..where((t) => t.id.equals(expense.id)))
          .getSingleOrNull();
      previous = oldRow == null ? null : _rowToExpense(oldRow);
    } catch (_) {
      previous = null; // memory will self-heal on next recompute if needed
    }

    try {
      await (_db.update(_db.expenses)..where((t) => t.id.equals(expense.id)))
          .write(_expenseToUpdateCompanion(expense));
      TLog.i('ExpenseRepo',
          '✏️ Updated: ₹${expense.amount.toStringAsFixed(0)} | ${expense.description} | ${expense.category}');
    } catch (e) {
      TLog.e('ExpenseRepo', 'Local update failed', error: e);
      rethrow;
    }

    await _safeApplyMemory(oldExpense: previous, newExpense: expense);

    try {
      await _syncPostWithRetry(ApiEndpoints.expenses, data: expense.toJson());
      TLog.i('ExpenseRepo',
          '☁️ Synced update: ₹${expense.amount.toStringAsFixed(0)} | ${expense.description}');
      return true;
    } catch (e) {
      TLog.w('ExpenseRepo',
          'Expense sync (update) failed after retries: ₹${expense.amount.toStringAsFixed(0)}',
          error: e);
      return false;
    }
  }

  Future<bool> deleteExpense(String id) async {
    domain.Expense? previous;
    try {
      final oldRow =
          await (_db.select(_db.expenses)..where((t) => t.id.equals(id)))
              .getSingleOrNull();
      previous = oldRow == null ? null : _rowToExpense(oldRow);
    } catch (_) {
      previous = null;
    }

    try {
      await (_db.delete(_db.expenses)..where((t) => t.id.equals(id))).go();
      TLog.i('ExpenseRepo', '🗑️ Deleted expense: $id');
    } catch (e) {
      TLog.e('ExpenseRepo', 'Local delete failed', error: e);
      rethrow;
    }

    if (previous != null) await _safeApplyMemory(oldExpense: previous);

    try {
      await _syncDeleteWithRetry(ApiEndpoints.expense(id));
      TLog.i('ExpenseRepo', '☁️ Synced delete: $id');
      return true;
    } catch (e) {
      TLog.w('ExpenseRepo', 'Expense sync (delete) failed after retries: $id',
          error: e);
      return false;
    }
  }

  /// Cheap `COUNT(*)` of budget-history rows — used by the nuke easter egg to
  /// report exactly how much was wiped, without loading any rows into memory.
  Future<int> budgetHistoryCount() async {
    final countExp = _db.budgetEntries.id.count();
    final q = _db.selectOnly(_db.budgetEntries)..addColumns([countExp]);
    final row = await q.getSingle();
    return row.read(countExp) ?? 0;
  }

  Future<double> getBudget() async {
    final row = await (_db.select(_db.budgetEntries)
          ..orderBy([
            (t) => OrderingTerm(expression: t.setAt, mode: OrderingMode.desc),
          ])
          ..limit(1))
        .getSingleOrNull();
    return row?.amount ?? 0;
  }

  Future<bool> setBudget(double amount) async {
    final id = _uuid.v4();
    final setAt = DateTime.now().toUtc().toIso8601String();
    try {
      await _db.into(_db.budgetEntries).insert(
            db.BudgetEntriesCompanion.insert(
              id: id,
              amount: amount,
              setAt: setAt,
            ),
          );
      TLog.i('ExpenseRepo', '📊 Budget set: ₹${amount.toStringAsFixed(0)}');
    } catch (e) {
      TLog.e('ExpenseRepo', 'Local budget insert failed', error: e);
      rethrow;
    }

    try {
      await _syncPostWithRetry(
        ApiEndpoints.budget,
        data: <String, dynamic>{'id': id, 'amount': amount, 'setAt': setAt},
      );
      TLog.i('ExpenseRepo', '☁️ Synced budget: ₹${amount.toStringAsFixed(0)}');
      return true;
    } catch (e) {
      TLog.w('ExpenseRepo', 'Budget sync failed after retries', error: e);
      return false;
    }
  }

  /// Pull budget entries from server and merge into local DB.
  Future<int> syncBudgetFromServer() async {
    try {
      final response = await _api.get<Object?>(ApiEndpoints.budgetHistory);
      final data = response.data;
      if (data is! List) return 0;

      final localRows = await _db.select(_db.budgetEntries).get();
      final localIds = localRows.map((r) => r.id).toSet();
      var inserted = 0;

      for (final item in data) {
        if (item is! Map) continue;
        final id = item['id']?.toString() ?? '';
        if (id.isEmpty || localIds.contains(id)) continue;

        final amount = (item['amount'] is num)
            ? (item['amount'] as num).toDouble()
            : double.tryParse(item['amount']?.toString() ?? '') ?? 0;
        final setAt = item['setAt']?.toString() ?? item['set_at']?.toString() ?? '';
        if (setAt.isEmpty) continue;

        await _db.into(_db.budgetEntries).insertOnConflictUpdate(
              db.BudgetEntriesCompanion.insert(
                id: id,
                amount: amount,
                setAt: setAt,
              ),
            );
        inserted++;
      }

      if (inserted > 0) TLog.i('ExpenseRepo', 'Synced $inserted budget entries from server');
      return inserted;
    } catch (e) {
      TLog.w('ExpenseRepo', 'Budget pull sync failed: $e', error: e);
      return 0;
    }
  }

  // ── Easter-egg clear operations ──────────────────────────────────────────

  /// Clear all budget history (local + server).
  /// Returns `true` if server sync succeeded.
  Future<bool> clearBudgetHistory() async {
    try {
      await _db.delete(_db.budgetEntries).go();
      TLog.i('ExpenseRepo', 'Budget history cleared (local)');
    } catch (e) {
      TLog.e('ExpenseRepo', 'Failed to clear budget history locally', error: e);
      rethrow;
    }

    final serverOk = await _serverDeleteWithRetry(
      endpoint: ApiEndpoints.budgetHistory,
      label: 'budget history',
      verifyEndpoint: ApiEndpoints.budgetHistory,
    );

    if (!serverOk) {
      await _prefs.setBool(_pendingClearBudgetKey, true);
      TLog.w('ExpenseRepo', 'Flagged pending clear for budget history');
    }
    return serverOk;
  }

  /// Clear all expenses (local + server).
  /// Returns `true` if server sync succeeded.
  Future<bool> clearAllExpenses() async {
    try {
      await _db.delete(_db.expenses).go();
      TLog.i('ExpenseRepo', 'All expenses cleared (local)');
    } catch (e) {
      TLog.e('ExpenseRepo', 'Failed to clear expenses locally', error: e);
      rethrow;
    }

    // Memory layer is derived from expenses — rebuild it (now empty).
    await _safeRecomputeMemory();

    final serverOk = await _serverDeleteWithRetry(
      endpoint: ApiEndpoints.expenses,
      label: 'expenses',
      verifyEndpoint: ApiEndpoints.expenses,
    );

    if (!serverOk) {
      await _prefs.setBool(_pendingClearExpensesKey, true);
      TLog.w('ExpenseRepo', 'Flagged pending clear for expenses');
    }
    return serverOk;
  }

  /// Count of stored category-learning rules — nuke telemetry.
  Future<int> learningsCount() async {
    final countExp = _db.categoryLearnings.keyword.count();
    final q = _db.selectOnly(_db.categoryLearnings)..addColumns([countExp]);
    final row = await q.getSingle();
    return row.read(countExp) ?? 0;
  }

  /// Clear all learned keyword→category rules (local + server). Returns `true`
  /// if the server cleared. Used by the full-app "nuke" so the learnings don't
  /// silently re-hydrate from the cloud on the next categorize call.
  Future<bool> clearLearnings() async {
    try {
      await _db.delete(_db.categoryLearnings).go();
      TLog.i('ExpenseRepo', 'Category learnings cleared (local)');
    } catch (e) {
      TLog.e('ExpenseRepo', 'Failed to clear learnings locally', error: e);
      rethrow;
    }

    final serverOk = await _serverDeleteWithRetry(
      endpoint: ApiEndpoints.categoryLearnings,
      label: 'category learnings',
      verifyEndpoint: ApiEndpoints.categoryLearnings,
    );

    if (!serverOk) {
      await _prefs.setBool(_pendingClearLearningsKey, true);
      TLog.w('ExpenseRepo', 'Flagged pending clear for category learnings');
    }
    return serverOk;
  }

  /// DELETE with 3 retries + exponential backoff, then verify via GET.
  Future<bool> _serverDeleteWithRetry({
    required String endpoint,
    required String label,
    required String verifyEndpoint,
    int maxAttempts = 3,
  }) async {
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        await _api.delete<Object?>(endpoint);
        TLog.i('ExpenseRepo', '$label cleared on server (attempt $attempt)');

        final verified = await _verifyEmpty(verifyEndpoint, label);
        if (verified) return true;

        TLog.w('ExpenseRepo', '$label verify failed — server still has data');
      } catch (e) {
        TLog.w('ExpenseRepo',
            '$label server clear attempt $attempt/$maxAttempts failed',
            error: e);
      }

      if (attempt < maxAttempts) {
        final delay = Duration(
          milliseconds: math.min(1000 * math.pow(2, attempt - 1).toInt(), 8000),
        );
        await Future<void>.delayed(delay);
      }
    }
    return false;
  }

  /// GET the endpoint and check that the response list is empty.
  Future<bool> _verifyEmpty(String endpoint, String label) async {
    try {
      final resp = await _api.get<Object?>(endpoint);
      final data = resp.data;
      final isEmpty = data is List
          ? data.isEmpty
          : (data is Map && (data['expenses'] is List)
              ? (data['expenses'] as List).isEmpty
              : (data is Map && (data['history'] is List)
                  ? (data['history'] as List).isEmpty
                  : true));
      TLog.i('ExpenseRepo', '$label verify: empty=$isEmpty');
      return isEmpty;
    } catch (e) {
      TLog.w('ExpenseRepo', '$label verify GET failed', error: e);
      return false;
    }
  }

  /// Call on app start/resume to retry any pending clears that failed earlier.
  Future<void> retryPendingClears() async {
    final pendingExpenses = _prefs.getBool(_pendingClearExpensesKey) ?? false;
    final pendingBudget = _prefs.getBool(_pendingClearBudgetKey) ?? false;
    final pendingLearnings = _prefs.getBool(_pendingClearLearningsKey) ?? false;

    if (!pendingExpenses && !pendingBudget && !pendingLearnings) return;

    TLog.i('ExpenseRepo', 'Retrying pending clears '
        '(expenses=$pendingExpenses, budget=$pendingBudget, '
        'learnings=$pendingLearnings)');

    if (pendingExpenses) {
      final ok = await _serverDeleteWithRetry(
        endpoint: ApiEndpoints.expenses,
        label: 'expenses (retry)',
        verifyEndpoint: ApiEndpoints.expenses,
      );
      if (ok) {
        await _prefs.remove(_pendingClearExpensesKey);
        TLog.i('ExpenseRepo', 'Pending expenses clear resolved');
      }
    }

    if (pendingBudget) {
      final ok = await _serverDeleteWithRetry(
        endpoint: ApiEndpoints.budgetHistory,
        label: 'budget history (retry)',
        verifyEndpoint: ApiEndpoints.budgetHistory,
      );
      if (ok) {
        await _prefs.remove(_pendingClearBudgetKey);
        TLog.i('ExpenseRepo', 'Pending budget clear resolved');
      }
    }

    if (pendingLearnings) {
      final ok = await _serverDeleteWithRetry(
        endpoint: ApiEndpoints.categoryLearnings,
        label: 'category learnings (retry)',
        verifyEndpoint: ApiEndpoints.categoryLearnings,
      );
      if (ok) {
        await _prefs.remove(_pendingClearLearningsKey);
        TLog.i('ExpenseRepo', 'Pending learnings clear resolved');
      }
    }
  }

  Stream<List<domain.BudgetHistoryEntry>> watchBudgetHistory() {
    return (_db.select(_db.budgetEntries)
          ..orderBy([
            (t) => OrderingTerm(expression: t.setAt, mode: OrderingMode.desc),
          ]))
        .watch()
        .map(
          (rows) => rows
              .map(
                (r) => domain.BudgetHistoryEntry(
                  id: r.id,
                  amount: r.amount,
                  setAt: r.setAt,
                ),
              )
              .toList(),
        );
  }

  Future<Map<String, String>> getLearnings() async {
    final rows = await _db.select(_db.categoryLearnings).get();
    return {for (final r in rows) r.keyword: r.category};
  }

  Future<void> saveLearning(String keyword, String category) async {
    await _db.into(_db.categoryLearnings).insertOnConflictUpdate(
          db.CategoryLearningsCompanion(
            keyword: Value(keyword),
            category: Value(category),
          ),
        );
  }

  /// Sync a single learning to the server (fire-and-forget).
  Future<bool> syncLearning(String keyword, String category) async {
    try {
      await _api.post<Object?>(
        ApiEndpoints.categoryLearnings,
        data: <String, dynamic>{'keyword': keyword, 'category': category},
      );
      return true;
    } catch (e) {
      TLog.w('ExpenseRepo', 'Learning sync failed: $e', error: e);
      return false;
    }
  }

  /// Pull learnings from server and merge into local DB.
  Future<int> syncLearningsFromServer() async {
    try {
      final response = await _api.get<Object?>(ApiEndpoints.categoryLearnings);
      final data = response.data;
      if (data is! List) return 0;

      var merged = 0;
      for (final item in data) {
        if (item is! Map) continue;
        final keyword = item['keyword']?.toString() ?? '';
        final category = item['category']?.toString() ?? '';
        if (keyword.isEmpty || category.isEmpty) continue;

        await _db.into(_db.categoryLearnings).insertOnConflictUpdate(
              db.CategoryLearningsCompanion(
                keyword: Value(keyword),
                category: Value(category),
              ),
            );
        merged++;
      }

      if (merged > 0) TLog.i('ExpenseRepo', 'Synced $merged learnings from server');
      return merged;
    } catch (e) {
      TLog.w('ExpenseRepo', 'Learning pull sync failed: $e', error: e);
      return 0;
    }
  }

  /// Push all local learnings to server in batch.
  Future<bool> pushAllLearnings() async {
    try {
      final rows = await _db.select(_db.categoryLearnings).get();
      if (rows.isEmpty) return true;

      final learnings = rows
          .map((r) => <String, String>{'keyword': r.keyword, 'category': r.category})
          .toList();

      await _api.post<Object?>(
        ApiEndpoints.categoryLearningsBatch,
        data: <String, dynamic>{'learnings': learnings},
      );
      return true;
    } catch (e) {
      TLog.w('ExpenseRepo', 'Batch learning push failed: $e', error: e);
      return false;
    }
  }

  /// Pull expenses from server and merge into local DB.
  Future<int> syncFromServer() async {
    try {
      final response = await _api.get<Object?>(ApiEndpoints.expenses);
      final data = response.data;
      if (data is! List) return 0;

      final localRows = await _db.select(_db.expenses).get();
      final localIds = localRows.map((r) => r.id).toSet();
      var inserted = 0;

      for (final item in data) {
        if (item is! Map) continue;
        final id = item['id']?.toString() ?? '';
        if (id.isEmpty || localIds.contains(id)) continue;

        final expense = domain.Expense(
          id: id,
          amount: (item['amount'] is num) ? (item['amount'] as num).toDouble() : 0,
          description: item['description']?.toString() ?? '',
          category: item['category']?.toString() ?? '',
          bank: item['bank']?.toString() ?? '',
          cardType: item['cardType']?.toString() ?? item['card_type']?.toString() ?? '',
          date: item['date']?.toString() ?? '',
          isManualCategory: item['isManualCategory'] == true || item['is_manual_category'] == true,
          comments: item['comments']?.toString() ?? '',
        );

        await _db.into(_db.expenses).insertOnConflictUpdate(
              _expenseToCompanion(expense),
            );
        inserted++;
      }

      if (inserted > 0) {
        TLog.i('ExpenseRepo', 'Synced $inserted expenses from server');
        // Bulk inserts bypass the per-write delta hooks; rebuild the rollup
        // once so the memory layer reflects the freshly-pulled rows.
        await _safeRecomputeMemory();
      }
      return inserted;
    } catch (e) {
      TLog.w('ExpenseRepo', 'Expense pull sync failed: $e', error: e);
      return 0;
    }
  }

  domain.Expense _rowToExpense(db.Expense row) {
    return domain.Expense(
      id: row.id,
      amount: row.amount,
      description: row.description,
      category: row.category,
      bank: row.bank,
      cardType: row.cardType,
      date: row.date,
      isManualCategory: row.isManualCategory,
      comments: row.comments,
    );
  }

  db.ExpensesCompanion _expenseToCompanion(domain.Expense e) {
    return db.ExpensesCompanion.insert(
      id: e.id,
      amount: e.amount,
      description: e.description,
      category: e.category,
      bank: e.bank,
      cardType: e.cardType,
      date: e.date,
      isManualCategory: Value(e.isManualCategory),
      comments: Value(e.comments),
    );
  }

  db.ExpensesCompanion _expenseToUpdateCompanion(domain.Expense e) {
    return db.ExpensesCompanion(
      id: Value(e.id),
      amount: Value(e.amount),
      description: Value(e.description),
      category: Value(e.category),
      bank: Value(e.bank),
      cardType: Value(e.cardType),
      date: Value(e.date),
      isManualCategory: Value(e.isManualCategory),
      comments: Value(e.comments),
    );
  }

  // ── Timeframe drill-down (paginated, DB-level — stays fluid at 1M+ rows) ──

  /// One page of expenses whose `date` is `>= startIso` (and `< endIso` when
  /// provided), ordered newest-first. Filtering + ordering + LIMIT/OFFSET all
  /// run in SQLite (indexed on `date`) so we never load the whole history into
  /// memory.
  Future<List<domain.Expense>> getExpensesPage({
    String? startIso,
    String? endIso,
    String? category,
    String? search,
    List<String> searchTerms = const [],
    ExpenseSort sort = ExpenseSort.dateDesc,
    bool excludeInvestment = false,
    required int limit,
    required int offset,
  }) async {
    try {
      final q = _db.select(_db.expenses)
        ..orderBy(_orderingFor(sort))
        ..limit(limit, offset: offset);
      _applyRangeFilters(q, startIso, endIso, category, search, searchTerms,
          excludeInvestment: excludeInvestment);
      final rows = await q.get();
      return rows.map(_rowToExpense).toList();
    } catch (e) {
      TLog.e('ExpenseRepo', 'getExpensesPage failed '
          '(start=$startIso offset=$offset)', error: e);
      rethrow;
    }
  }

  /// Aggregate count + total spend for a timeframe — computed in SQL so it is
  /// instant regardless of history size.
  Future<({int count, double total})> rangeSummary({
    String? startIso,
    String? endIso,
    String? category,
    String? search,
    List<String> searchTerms = const [],
    bool excludeInvestment = false,
  }) async {
    try {
      final countExp = _db.expenses.id.count();
      final totalExp = _db.expenses.amount.sum();
      final q = _db.selectOnly(_db.expenses)..addColumns([countExp, totalExp]);
      _applyRangeFiltersJoin(q, startIso, endIso, category, search, searchTerms,
          excludeInvestment: excludeInvestment);
      final row = await q.getSingle();
      return (
        count: row.read(countExp) ?? 0,
        total: (row.read(totalExp) ?? 0).toDouble(),
      );
    } catch (e) {
      TLog.w('ExpenseRepo', 'rangeSummary failed (start=$startIso)', error: e);
      return (count: 0, total: 0.0);
    }
  }

  /// Reactive month-to-date total for a 'YYYY-MM' key, computed as a SQL
  /// `SUM(amount)` over the indexed `date` range — never loads rows into
  /// memory, so it stays O(log n) + aggregation even with millions of rows and
  /// re-emits automatically whenever any expense in that month changes. Powers
  /// the salary stats so they don't depend on the full in-memory expense list.
  Stream<double> watchMonthTotal(String monthKey) {
    final (start, end) = _monthBounds(monthKey);
    final totalExp = _db.expenses.amount.sum();
    final q = _db.selectOnly(_db.expenses)..addColumns([totalExp]);
    q.where(_db.expenses.date.isBiggerOrEqualValue(start));
    q.where(_db.expenses.date.isSmallerThanValue(end));
    // Investments are wealth, not consumption — they must never reduce the
    // month's "spent" figure that drives the salary savings math.
    q.where(_db.expenses.category.equals(domain.kInvestmentCategory).not());
    return q.watchSingle().map((row) => (row.read(totalExp) ?? 0).toDouble());
  }

  /// Reactive per-month total spend across ALL months, keyed by 'YYYY-MM'.
  /// Derived from the compact memory rollup (one row per month/category) rather
  /// than the raw `expenses` table, so it is constant-cost regardless of how
  /// many expenses exist and re-emits whenever any month's spend changes.
  /// Powers the lifetime savings / runway stats that need spend paired with
  /// each recorded salary month.
  Stream<Map<String, double>> watchMonthlySpendTotals() {
    final monthCol = _db.expenseMonthlyCategory.month;
    final totalCol = _db.expenseMonthlyCategory.total.sum();
    final q = _db.selectOnly(_db.expenseMonthlyCategory)
      ..addColumns([monthCol, totalCol])
      // Exclude the Investment rollup row — investments are savings, not spend,
      // so they must not count against lifetime savings / runway stats.
      ..where(_db.expenseMonthlyCategory.category
          .equals(domain.kInvestmentCategory)
          .not())
      ..groupBy([monthCol]);
    return q.watch().map((rows) {
      final out = <String, double>{};
      for (final r in rows) {
        final m = r.read(monthCol);
        if (m == null || m.isEmpty) continue;
        out[m] = (r.read(totalCol) ?? 0).toDouble();
      }
      return out;
    });
  }

  /// Reactive per-month spend for a single card type (e.g. 'CC'), keyed by
  /// 'YYYY-MM'. Grouped in SQL via `substr(date,1,7)` over the indexed `date`
  /// column with a `card_type` filter, so only the (small) set of distinct
  /// months is materialized — scales to large histories and re-emits whenever
  /// any matching expense changes. Powers the credit-card repayment forecast
  /// (this month's CC spend = next month's bill; last month's = the bill due
  /// now).
  Stream<Map<String, double>> watchMonthlyCardSpendTotals(String cardType) {
    const bucketExp = CustomExpression<String>('substr(expenses.date, 1, 7)');
    final totalExp = _db.expenses.amount.sum();
    final q = _db.selectOnly(_db.expenses)
      ..addColumns([bucketExp, totalExp])
      ..where(_db.expenses.cardType.equals(cardType))
      ..groupBy([bucketExp]);
    return q.watch().map((rows) {
      final out = <String, double>{};
      for (final r in rows) {
        final m = r.read(bucketExp);
        if (m == null || m.isEmpty) continue;
        out[m] = (r.read(totalExp) ?? 0).toDouble();
      }
      return out;
    });
  }

  /// Inclusive start ('YYYY-MM-01') and exclusive end (first day of next month)
  /// date-prefix bounds for a 'YYYY-MM' key. Lexicographic on the ISO date
  /// strings, which is correct because they share the fixed 'YYYY-MM-DD…' shape.
  (String, String) _monthBounds(String monthKey) {
    final parts = monthKey.split('-');
    final y = int.tryParse(parts.isNotEmpty ? parts[0] : '') ??
        DateTime.now().year;
    final m = parts.length > 1 ? (int.tryParse(parts[1]) ?? 1) : 1;
    final start =
        '${y.toString().padLeft(4, '0')}-${m.toString().padLeft(2, '0')}-01';
    final ny = m == 12 ? y + 1 : y;
    final nm = m == 12 ? 1 : m + 1;
    final end =
        '${ny.toString().padLeft(4, '0')}-${nm.toString().padLeft(2, '0')}-01';
    return (start, end);
  }

  /// Per-category totals for a timeframe (newest-first by spend), in SQL.
  Future<List<({String category, double total, int count})>> categoryBreakdown({
    String? startIso,
    String? endIso,
    String? search,
    List<String> searchTerms = const [],
    bool excludeInvestment = false,
  }) async {
    try {
      final totalExp = _db.expenses.amount.sum();
      final countExp = _db.expenses.id.count();
      final q = _db.selectOnly(_db.expenses)
        ..addColumns([_db.expenses.category, totalExp, countExp])
        ..groupBy([_db.expenses.category])
        ..orderBy([OrderingTerm(expression: totalExp, mode: OrderingMode.desc)]);
      _applyRangeFiltersJoin(q, startIso, endIso, null, search, searchTerms,
          excludeInvestment: excludeInvestment);
      final rows = await q.get();
      return rows
          .map((r) => (
                category: r.read(_db.expenses.category) ?? 'Others',
                total: (r.read(totalExp) ?? 0).toDouble(),
                count: r.read(countExp) ?? 0,
              ))
          .toList();
    } catch (e) {
      TLog.w('ExpenseRepo', 'categoryBreakdown failed', error: e);
      return const [];
    }
  }

  /// Ordering clause(s) for a [ExpenseSort]. A secondary `id` term keeps
  /// pagination deterministic when the primary key (e.g. amount) ties.
  List<OrderClauseGenerator<db.$ExpensesTable>> _orderingFor(ExpenseSort sort) {
    switch (sort) {
      case ExpenseSort.dateAsc:
        return [
          (t) => OrderingTerm(expression: t.date, mode: OrderingMode.asc),
          (t) => OrderingTerm(expression: t.id, mode: OrderingMode.asc),
        ];
      case ExpenseSort.amountDesc:
        return [
          (t) => OrderingTerm(expression: t.amount, mode: OrderingMode.desc),
          (t) => OrderingTerm(expression: t.date, mode: OrderingMode.desc),
          (t) => OrderingTerm(expression: t.id, mode: OrderingMode.asc),
        ];
      case ExpenseSort.amountAsc:
        return [
          (t) => OrderingTerm(expression: t.amount, mode: OrderingMode.asc),
          (t) => OrderingTerm(expression: t.date, mode: OrderingMode.desc),
          (t) => OrderingTerm(expression: t.id, mode: OrderingMode.asc),
        ];
      case ExpenseSort.dateDesc:
        return [
          (t) => OrderingTerm(expression: t.date, mode: OrderingMode.desc),
          (t) => OrderingTerm(expression: t.id, mode: OrderingMode.asc),
        ];
    }
  }

  /// Per-time-bucket totals (day or month) for chart visualizations, computed
  /// entirely in SQL via `GROUP BY substr(date, ...)`. Buckets are returned in
  /// chronological order. Scales to very large histories — only the (small)
  /// set of distinct buckets is materialized, never the rows themselves.
  Future<List<ExpenseBucket>> timeBreakdown({
    required bool monthly,
    String? startIso,
    String? endIso,
    String? category,
    String? search,
    List<String> searchTerms = const [],
    bool excludeInvestment = false,
  }) async {
    try {
      // ISO dates are 'YYYY-MM-DDThh:mm:ss…' so substr(1,10)=day, (1,7)=month.
      final bucketExp =
          CustomExpression<String>('substr(expenses.date, 1, ${monthly ? 7 : 10})');
      final totalExp = _db.expenses.amount.sum();
      final countExp = _db.expenses.id.count();
      final q = _db.selectOnly(_db.expenses)
        ..addColumns([bucketExp, totalExp, countExp])
        ..groupBy([bucketExp])
        ..orderBy([OrderingTerm(expression: bucketExp, mode: OrderingMode.asc)]);
      _applyRangeFiltersJoin(q, startIso, endIso, category, search, searchTerms,
          excludeInvestment: excludeInvestment);
      final rows = await q.get();
      return rows
          .map((r) => (
                bucket: r.read(bucketExp) ?? '',
                total: (r.read(totalExp) ?? 0).toDouble(),
                count: r.read(countExp) ?? 0,
              ))
          .where((b) => b.bucket.isNotEmpty)
          .toList();
    } catch (e) {
      TLog.w('ExpenseRepo', 'timeBreakdown failed (monthly=$monthly)', error: e);
      return const [];
    }
  }

  void _applyRangeFilters(
    SimpleSelectStatement<db.$ExpensesTable, db.Expense> q,
    String? startIso,
    String? endIso,
    String? category,
    String? search,
    List<String> searchTerms, {
    bool excludeInvestment = false,
  }) {
    if (startIso != null) {
      q.where((t) => t.date.isBiggerOrEqualValue(startIso));
    }
    if (endIso != null) {
      q.where((t) => t.date.isSmallerThanValue(endIso));
    }
    if (category != null && category.isNotEmpty) {
      q.where((t) => t.category.equals(category));
    }
    if (excludeInvestment) {
      q.where((t) => t.category.equals(domain.kInvestmentCategory).not());
    }
    // User's editable text (AND) — narrows within the result set.
    final searchExpr = _searchExpr(search);
    if (searchExpr != null) q.where((_) => searchExpr);
    // Semantic OR-group from AI query expansion — a row must match ANY term.
    final anyExpr = _searchAnyExpr(searchTerms);
    if (anyExpr != null) q.where((_) => anyExpr);
  }

  void _applyRangeFiltersJoin(
    JoinedSelectStatement q,
    String? startIso,
    String? endIso,
    String? category,
    String? search,
    List<String> searchTerms, {
    bool excludeInvestment = false,
  }) {
    final t = _db.expenses;
    if (startIso != null) q.where(t.date.isBiggerOrEqualValue(startIso));
    if (endIso != null) q.where(t.date.isSmallerThanValue(endIso));
    if (category != null && category.isNotEmpty) {
      q.where(t.category.equals(category));
    }
    if (excludeInvestment) {
      q.where(t.category.equals(domain.kInvestmentCategory).not());
    }
    final searchExpr = _searchExpr(search);
    if (searchExpr != null) q.where(searchExpr);
    final anyExpr = _searchAnyExpr(searchTerms);
    if (anyExpr != null) q.where(anyExpr);
  }

  /// SQL fragment matching a single term (case-insensitive contains) against
  /// description / category / comments.
  ///
  /// LIKE wildcards (`%`, `_`) and the escape char (`\`) in the user's input
  /// are escaped so they match literally (e.g. searching "50%" finds only rows
  /// containing "50%", not every row with "50"). The needle is embedded as a
  /// single-quote-escaped SQL string literal — SQLite-safe, no injection — and
  /// an explicit `ESCAPE '\'` clause makes the wildcard-escaping take effect.
  String _termLikeSql(String rawTerm) {
    final escaped = rawTerm
        .replaceAll('\\', r'\\')
        .replaceAll('%', r'\%')
        .replaceAll('_', r'\_')
        .replaceAll("'", "''");
    final lit = "'%$escaped%'";
    return '(expenses.description LIKE $lit ESCAPE \'\\\' '
        'OR expenses.category LIKE $lit ESCAPE \'\\\' '
        'OR expenses.comments LIKE $lit ESCAPE \'\\\')';
  }

  /// Single editable search term (the user's text box).
  Expression<bool>? _searchExpr(String? search) {
    final raw = search?.trim() ?? '';
    if (raw.isEmpty) return null;
    return CustomExpression<bool>(_termLikeSql(raw));
  }

  /// Semantic OR-group: a row matches if it contains ANY of [terms] (each term
  /// matched literally across the three text columns). Powers AI query
  /// expansion ("anything related to my car" → car/fuel/garage/service/…).
  /// Results are always real DB rows — the model only supplies the terms, so it
  /// can never fabricate an expense.
  Expression<bool>? _searchAnyExpr(List<String> terms) {
    final cleaned = <String>{};
    for (final t in terms) {
      final v = t.trim();
      if (v.isNotEmpty) cleaned.add(v);
    }
    if (cleaned.isEmpty) return null;
    final parts = cleaned.map(_termLikeSql).join(' OR ');
    return CustomExpression<bool>('($parts)');
  }
}
