import 'dart:convert';
import 'dart:math' as math;

import 'package:drift/drift.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_endpoints.dart';
import '../../core/services/telegram_logger.dart';
import '../../domain/entities/salary_entities.dart';
import '../local/database/app_database.dart' as db;

/// Offline-first store for monthly in-hand salary. One row per 'YYYY-MM'
/// (the table's primary key), so re-entering a month upserts — this is the
/// monthly "reset" the user enters on the 1st. Writes go local-first then sync
/// to the backend with retry; pulls merge server history back in.
class SalaryRepository {
  SalaryRepository(this._db, this._api, this._prefs);

  final db.AppDatabase _db;
  final ApiClient _api;
  final SharedPreferences _prefs;

  static const _uuid = Uuid();
  static const _pendingClearKey = 'pending_clear_salary';

  /// Durable sync-queue discriminator for salary upserts.
  static const _syncEntityType = 'salary';
  static const _syncActionUpsert = 'upsert';

  // ── Reads ────────────────────────────────────────────────────────────────

  /// All recorded months, newest month first.
  Stream<List<SalaryEntry>> watchSalaries() {
    return (_db.select(_db.salaryEntries)
          ..orderBy([
            (t) => OrderingTerm(expression: t.month, mode: OrderingMode.desc),
          ]))
        .watch()
        .map((rows) => rows.map(_rowToEntry).toList());
  }

  Future<List<SalaryEntry>> getSalaries() async {
    final rows = await (_db.select(_db.salaryEntries)
          ..orderBy([
            (t) => OrderingTerm(expression: t.month, mode: OrderingMode.desc),
          ]))
        .get();
    return rows.map(_rowToEntry).toList();
  }

  Future<SalaryEntry?> getSalaryForMonth(String month) async {
    final row = await (_db.select(_db.salaryEntries)
          ..where((t) => t.month.equals(month)))
        .getSingleOrNull();
    return row == null ? null : _rowToEntry(row);
  }

  Future<SalaryEntry?> getCurrentMonthSalary() =>
      getSalaryForMonth(monthKeyOf(DateTime.now()));

  /// Cheap `COUNT(*)` of recorded salary months — used by the nuke easter egg
  /// for its "wiped N salary entries" telemetry.
  Future<int> salaryCount() async {
    final countExp = _db.salaryEntries.id.count();
    final q = _db.selectOnly(_db.salaryEntries)..addColumns([countExp]);
    final row = await q.getSingle();
    return row.read(countExp) ?? 0;
  }

  // ── Writes ───────────────────────────────────────────────────────────────

  /// Upsert the in-hand salary for [month] ('YYYY-MM'). Reuses the existing
  /// row id when present so server records stay stable across edits.
  Future<bool> setSalaryForMonth(String month, double amount) async {
    final existing = await getSalaryForMonth(month);
    final id = existing?.id ?? _uuid.v4();
    final setAt = DateTime.now().toUtc().toIso8601String();

    try {
      await _db.into(_db.salaryEntries).insertOnConflictUpdate(
            db.SalaryEntriesCompanion.insert(
              id: id,
              month: month,
              amount: amount,
              setAt: setAt,
            ),
          );
      TLog.i('SalaryRepo',
          '💰 Salary set for $month: ₹${amount.toStringAsFixed(0)}');
    } catch (e) {
      TLog.e('SalaryRepo', 'Local salary upsert failed', error: e);
      rethrow;
    }

    final payload = <String, dynamic>{
      'id': id,
      'month': month,
      'amount': amount,
      'setAt': setAt,
    };

    try {
      await _syncPostWithRetry(ApiEndpoints.salary, data: payload);
      TLog.i('SalaryRepo', '☁️ Synced salary $month');
      // Inline push won — drop any stale queued copy for this month.
      await _dequeueUpsert(month);
      return true;
    } catch (e) {
      // Inline retries exhausted (likely offline). Persist the write to the
      // durable sync queue so it auto-pushes on the next launch/reconnect —
      // the entry is no longer lost once the in-memory retries give up.
      TLog.w('SalaryRepo',
          'Salary sync failed after retries — queued for offline retry',
          error: e);
      try {
        await _db.enqueueSync(
          entityType: _syncEntityType,
          entityId: month,
          action: _syncActionUpsert,
          payload: jsonEncode(payload),
        );
      } catch (qe) {
        TLog.e('SalaryRepo', 'Failed to enqueue salary for offline retry',
            error: qe);
      }
      return false;
    }
  }

  /// Push every queued (offline) salary upsert. Call on app start/resume so a
  /// salary entered while offline reaches the cloud once connectivity returns.
  /// Returns the number of entries successfully drained.
  Future<int> drainSyncQueue() async {
    final items = await _db.pendingSyncItems(_syncEntityType);
    if (items.isEmpty) return 0;
    TLog.i('SalaryRepo', 'Draining ${items.length} queued salary write(s)');

    var drained = 0;
    for (final item in items) {
      try {
        final data = jsonDecode(item.payload) as Map<String, dynamic>;
        await _api.post<Object?>(ApiEndpoints.salary, data: data);
        await _db.deleteSyncItem(item.id);
        drained++;
        TLog.i('SalaryRepo', '☁️ Drained queued salary ${item.entityId}');
      } catch (e) {
        TLog.w('SalaryRepo',
            'Queued salary ${item.entityId} still failing — kept for next drain',
            error: e);
      }
    }
    return drained;
  }

  Future<void> _dequeueUpsert(String month) async {
    try {
      final queued = await _db.pendingSyncItems(_syncEntityType);
      for (final q in queued) {
        if (q.entityId == month && q.action == _syncActionUpsert) {
          await _db.deleteSyncItem(q.id);
        }
      }
    } catch (_) {/* best-effort cleanup */}
  }

  /// Pull salary entries from the server and merge into local DB. Server is the
  /// source of truth for a month when its [setAt] is newer than the local copy.
  Future<int> syncSalaryFromServer() async {
    try {
      final response = await _api.get<Object?>(ApiEndpoints.salaryHistory);
      final raw = response.data;
      final list = raw is List
          ? raw
          : (raw is Map && raw['history'] is List
              ? raw['history'] as List
              : const []);
      if (list.isEmpty) return 0;

      final localRows = await _db.select(_db.salaryEntries).get();
      final localByMonth = {for (final r in localRows) r.month: r};

      var merged = 0;
      for (final item in list) {
        if (item is! Map) continue;
        final month = item['month']?.toString() ?? '';
        if (month.isEmpty) continue;

        final amount = (item['amount'] is num)
            ? (item['amount'] as num).toDouble()
            : double.tryParse(item['amount']?.toString() ?? '') ?? double.nan;
        // Reject NaN/Infinity (a bad row must never abort the whole sync or
        // corrupt the column with a non-finite value).
        if (!amount.isFinite || amount < 0) {
          TLog.w('SalaryRepo', 'Skipping salary row with bad amount ($month)');
          continue;
        }
        final setAt = item['setAt']?.toString() ??
            item['set_at']?.toString() ??
            '';
        if (setAt.isEmpty) continue;
        final id = item['id']?.toString() ??
            localByMonth[month]?.id ??
            _uuid.v4();

        final local = localByMonth[month];
        // Skip when our local copy is the same or newer (last-write-wins).
        if (local != null && local.setAt.compareTo(setAt) >= 0) continue;

        try {
          await _db.into(_db.salaryEntries).insertOnConflictUpdate(
                db.SalaryEntriesCompanion.insert(
                  id: id,
                  month: month,
                  amount: amount,
                  setAt: setAt,
                ),
              );
          merged++;
        } catch (e) {
          // One malformed row can't sink the rest of the merge.
          TLog.w('SalaryRepo', 'Salary row merge failed ($month)', error: e);
        }
      }

      if (merged > 0) {
        TLog.i('SalaryRepo', 'Synced $merged salary entries from server');
      }
      return merged;
    } catch (e) {
      TLog.w('SalaryRepo', 'Salary pull sync failed: $e', error: e);
      return 0;
    }
  }

  /// Clear all salary history (local + server). Returns true if server cleared.
  Future<bool> clearSalaryHistory() async {
    try {
      await _db.delete(_db.salaryEntries).go();
      // Drop any queued offline upserts too, else a pending write would
      // resurrect a salary row right after the clear.
      await _db.purgeSyncByType(_syncEntityType);
      TLog.i('SalaryRepo', 'Salary history cleared (local)');
    } catch (e) {
      TLog.e('SalaryRepo', 'Failed to clear salary history locally', error: e);
      rethrow;
    }

    final serverOk = await _serverDeleteWithRetry();
    if (!serverOk) {
      await _prefs.setBool(_pendingClearKey, true);
      TLog.w('SalaryRepo', 'Flagged pending clear for salary history');
    }
    return serverOk;
  }

  Future<void> retryPendingClear() async {
    if (!(_prefs.getBool(_pendingClearKey) ?? false)) return;
    TLog.i('SalaryRepo', 'Retrying pending salary clear');
    final ok = await _serverDeleteWithRetry();
    if (ok) {
      await _prefs.remove(_pendingClearKey);
      TLog.i('SalaryRepo', 'Pending salary clear resolved');
    }
  }

  // ── Internal helpers ───────────────────────────────────────────────────────

  SalaryEntry _rowToEntry(db.SalaryEntry row) => SalaryEntry(
        id: row.id,
        month: row.month,
        amount: row.amount,
        setAt: row.setAt,
      );

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
        TLog.d('SalaryRepo', 'POST retry $attempt/$maxAttempts → $endpoint');
        await Future<void>.delayed(Duration(milliseconds: 400 * attempt));
      }
    }
  }

  Future<bool> _serverDeleteWithRetry({int maxAttempts = 3}) async {
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        await _api.delete<Object?>(ApiEndpoints.salaryHistory);
        TLog.i('SalaryRepo', 'Salary cleared on server (attempt $attempt)');
        return true;
      } catch (e) {
        TLog.w('SalaryRepo',
            'Salary server clear attempt $attempt/$maxAttempts failed',
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
}
