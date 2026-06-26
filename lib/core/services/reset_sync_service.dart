import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import '../../data/local/database/app_database.dart';
import '../network/api_client.dart';
import '../network/api_endpoints.dart';
import 'nuke_report.dart';
import 'telegram_logger.dart';

/// Cross-device propagation for the "nuke" reset.
///
/// The per-domain cloud pulls are additive (insert-only) — they never delete a
/// local row just because it vanished from the server. So when device A nukes
/// the cloud, device B keeps showing its old local copy. This service closes
/// that gap with a tiny **global reset epoch**:
///
///   • The initiating device, after clearing the cloud, bumps a server-side
///     generation counter ([recordReset]).
///   • EVERY device, on launch/resume (and before it pushes/pulls), compares
///     the server epoch to the one it last applied ([applyRemoteResetIfNeeded]);
///     if the server is ahead, it wipes the matching scope LOCALLY.
///
/// Two independent monotonic counters (full / expense) make the scopes safe in
/// any interleaving — a full reset always subsumes an expense reset on the
/// client. The wipe here is strictly LOCAL: the cloud was already cleared by the
/// initiating device, so re-issuing cloud deletes would be redundant.
class ResetSyncService {
  ResetSyncService(this._db, this._api, this._prefs);

  final AppDatabase _db;
  final ApiClient _api;
  final SharedPreferences _prefs;

  static const _tag = 'ResetSync';
  static const _kFullApplied = 'reset_full_gen_applied';
  static const _kExpenseApplied = 'reset_expense_gen_applied';
  static const _kPendingBumpFull = 'reset_pending_bump_full';
  static const _kPendingBumpExpense = 'reset_pending_bump_expense';

  Future<bool>? _inFlight;

  int get _localFull => _prefs.getInt(_kFullApplied) ?? 0;
  int get _localExpense => _prefs.getInt(_kExpenseApplied) ?? 0;

  // ── Initiating device ──────────────────────────────────────────────────────

  /// Record a reset the user just performed on THIS device: bump the server
  /// epoch so other devices wipe themselves, and adopt the new generation
  /// locally so this device doesn't re-wipe. Best-effort — if offline, a
  /// pending flag self-heals on the next [applyRemoteResetIfNeeded].
  Future<bool> recordReset(NukeScope scope) async {
    final ok = await _bump(scope);
    if (!ok) {
      await _prefs.setBool(
        scope == NukeScope.full ? _kPendingBumpFull : _kPendingBumpExpense,
        true,
      );
      TLog.w(_tag, 'Reset epoch bump ($scope) queued — retries on next sync');
    }
    return ok;
  }

  Future<bool> _bump(NukeScope scope) async {
    try {
      final resp = await _api.post<Object?>(
        ApiEndpoints.dataReset,
        data: <String, dynamic>{
          'scope': scope == NukeScope.full ? 'full' : 'expense',
        },
      );
      final m = _asMap(resp.data);
      final full = _int(m?['fullGen']);
      final expense = _int(m?['expenseGen']);
      // Adopt server generation so this device is considered up-to-date and
      // won't wipe itself on the next apply pass.
      await _prefs.setInt(_kFullApplied, full);
      await _prefs.setInt(_kExpenseApplied, expense);
      await _prefs.remove(
        scope == NukeScope.full ? _kPendingBumpFull : _kPendingBumpExpense,
      );
      TLog.i(_tag, 'Reset epoch bumped: full=$full expense=$expense ($scope)');
      return true;
    } catch (e) {
      TLog.w(_tag, 'Reset epoch bump failed ($scope)', error: e);
      return false;
    }
  }

  // ── Every device ───────────────────────────────────────────────────────────

  /// Compare the server epoch to what we've applied and wipe the matching scope
  /// LOCALLY if we're behind. Coalesces concurrent callers (app launch + screen
  /// mounts firing together) into a single round-trip; concurrent callers await
  /// the same in-flight pass. Returns `true` only for the caller that performed
  /// the wipe.
  Future<bool> applyRemoteResetIfNeeded() {
    final pending = _inFlight;
    if (pending != null) return pending.then((_) => false);
    final f = _run();
    _inFlight = f;
    return f.whenComplete(() => _inFlight = null);
  }

  Future<bool> _run() async {
    // Finish any bump this device queued while offline before reading the epoch.
    await _retryPendingBumps();

    Map<String, dynamic>? m;
    try {
      final resp = await _api.get<Object?>(ApiEndpoints.dataReset);
      m = _asMap(resp.data);
    } catch (_) {
      // Offline / backend down — nothing to do; we re-check next launch/resume.
      return false;
    }
    if (m == null) return false;

    final serverFull = _int(m['fullGen']);
    final serverExpense = _int(m['expenseGen']);

    if (serverFull > _localFull) {
      TLog.w(
        _tag,
        '☢️ Remote FULL reset detected (server=$serverFull > local=$_localFull) '
        '— wiping ALL local data to match the cloud',
      );
      try {
        await _db.wipeAllRows();
      } catch (e, st) {
        TLog.e(_tag, 'Local full wipe (remote reset) failed', error: e, st: st);
        return false;
      }
      await _prefs.setInt(_kFullApplied, serverFull);
      // A full reset subsumes any expense reset.
      if (serverExpense > _localExpense) {
        await _prefs.setInt(_kExpenseApplied, serverExpense);
      }
      TLog.i(_tag, 'Local data wiped to match remote reset (full=$serverFull)');
      return true;
    }

    if (serverExpense > _localExpense) {
      TLog.w(
        _tag,
        '☢️ Remote EXPENSE reset detected (server=$serverExpense > '
        'local=$_localExpense) — clearing local financial data',
      );
      try {
        await _wipeFinancialLocal();
      } catch (e, st) {
        TLog.e(_tag, 'Local financial wipe (remote reset) failed',
            error: e, st: st);
        return false;
      }
      await _prefs.setInt(_kExpenseApplied, serverExpense);
      TLog.i(_tag, 'Local financial data cleared (expense=$serverExpense)');
      return true;
    }

    return false;
  }

  /// Clear ONLY the financial tables + their derived memory rollup + any queued
  /// salary writes (so a stale offline write can't re-push after the reset).
  Future<void> _wipeFinancialLocal() async {
    await _db.transaction(() async {
      await _db.delete(_db.expenses).go();
      await _db.delete(_db.budgetEntries).go();
      await _db.delete(_db.salaryEntries).go();
      await _db.delete(_db.expenseMonthlyCategory).go();
    });
    await _db.purgeSyncByType('salary');
  }

  Future<void> _retryPendingBumps() async {
    if (_prefs.getBool(_kPendingBumpFull) ?? false) {
      await _bump(NukeScope.full);
    }
    if (_prefs.getBool(_kPendingBumpExpense) ?? false) {
      await _bump(NukeScope.expense);
    }
  }

  Map<String, dynamic>? _asMap(Object? data) => data is Map
      ? data.map((k, v) => MapEntry(k.toString(), v))
      : null;

  int _int(Object? v) =>
      v is int ? v : (v is num ? v.toInt() : int.tryParse('$v') ?? 0);
}
