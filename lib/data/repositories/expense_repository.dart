import 'dart:math' as math;

import 'package:drift/drift.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_endpoints.dart';
import '../../core/services/telegram_logger.dart';
import '../../domain/entities/expense_entities.dart' as domain;
import '../local/database/app_database.dart' as db;

class ExpenseRepository {
  ExpenseRepository(this._db, this._api, this._prefs);

  final db.AppDatabase _db;
  final ApiClient _api;
  final SharedPreferences _prefs;

  static const _uuid = Uuid();

  static const _pendingClearExpensesKey = 'pending_clear_expenses';
  static const _pendingClearBudgetKey = 'pending_clear_budget';

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
    try {
      await (_db.update(_db.expenses)..where((t) => t.id.equals(expense.id)))
          .write(_expenseToUpdateCompanion(expense));
      TLog.i('ExpenseRepo',
          '✏️ Updated: ₹${expense.amount.toStringAsFixed(0)} | ${expense.description} | ${expense.category}');
    } catch (e) {
      TLog.e('ExpenseRepo', 'Local update failed', error: e);
      rethrow;
    }

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
    try {
      await (_db.delete(_db.expenses)..where((t) => t.id.equals(id))).go();
      TLog.i('ExpenseRepo', '🗑️ Deleted expense: $id');
    } catch (e) {
      TLog.e('ExpenseRepo', 'Local delete failed', error: e);
      rethrow;
    }

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

    if (!pendingExpenses && !pendingBudget) return;

    TLog.i('ExpenseRepo', 'Retrying pending clears '
        '(expenses=$pendingExpenses, budget=$pendingBudget)');

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
        );

        await _db.into(_db.expenses).insertOnConflictUpdate(
              _expenseToCompanion(expense),
            );
        inserted++;
      }

      if (inserted > 0) TLog.i('ExpenseRepo', 'Synced $inserted expenses from server');
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
    );
  }
}
