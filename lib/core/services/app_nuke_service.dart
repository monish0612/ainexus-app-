import '../../data/local/database/app_database.dart';
import '../../data/repositories/expense_repository.dart';
import '../../data/repositories/salary_repository.dart';
import '../../data/repositories/saved_words_repository.dart';
import 'nuke_report.dart';
import 'reset_sync_service.dart';
import 'telegram_logger.dart';

/// The full-app "nuke" engine — the nuclear option triggered from the InsightAI
/// search box. It resets the app to a pristine, first-launch data state by
/// deleting **every row from every table** locally (schema preserved — tables
/// are never dropped), and clearing the cloud for every domain that would
/// otherwise re-hydrate from the server on next use.
///
/// Cloud-backed domains cleared on the server too: expenses, budget, salary,
/// **saved words**, **category learnings** and **saved searches**. Each of
/// these has a server copy that the app pulls back down on next launch, so a
/// local-only wipe would silently "come back" (the saved-words-reappear bug).
///
/// Genuinely local domains are wiped locally only:
///   • News — server re-fills it from the RSS/X schedulers, so a cloud clear is
///     pointless (it would repopulate within minutes regardless).
///   • Cloud files — these rows are just metadata for the user's Google Drive;
///     the nuke must NOT touch the actual Drive files.
///
/// Robustness mirrors [ExpenseNukeService]: local wipe is atomic (single
/// transaction), every cloud clear runs exponential-backoff + verify +
/// pending-flag self-heal, every step is guarded, and the whole flow is logged
/// to Telegram with a start banner + a summary banner.
class AppNukeService {
  AppNukeService(
    this._db,
    this._expenseRepo,
    this._salaryRepo,
    this._savedWordsRepo,
    this._resetSync, {
    required Future<bool> Function() clearSavedSearches,
  }) : _clearSavedSearches = clearSavedSearches;

  final AppDatabase _db;
  final ExpenseRepository _expenseRepo;
  final SalaryRepository _salaryRepo;
  final SavedWordsRepository _savedWordsRepo;
  final ResetSyncService _resetSync;
  final Future<bool> Function() _clearSavedSearches;

  static const _tag = 'Nuke';

  Future<NukeReport> nuke() async {
    final sw = Stopwatch()..start();

    // Capture every data table's row count up front (best-effort).
    Map<String, int> counts;
    try {
      counts = await _db.dataRowCounts();
    } catch (e) {
      TLog.w(_tag, 'Full-nuke count snapshot failed (non-fatal)', error: e);
      counts = const {};
    }
    final total = counts.values.fold<int>(0, (s, v) => s + v);

    TLog.w(
      _tag,
      '☢️☢️ FULL NUKE initiated — wiping ALL local data ($total rows) + cloud '
      'data (financial, saved words, learnings, saved searches). Tables '
      'preserved, rows reset. This is irreversible.',
    );

    // 1) Atomic local wipe of EVERY table (rows only — schema untouched).
    var localOk = true;
    try {
      await _db.wipeAllRows();
      TLog.i(_tag, 'Local DB wiped — every table reset to 0 rows');
    } catch (e, st) {
      localOk = false;
      TLog.e(_tag, 'Local full wipe failed', error: e, st: st);
    }

    // 2) Cloud wipe for every domain that would otherwise re-hydrate. Each is
    //    local-first (now a no-op after the wipe) + server DELETE + verify +
    //    retry + pending-flag, so a cloud outage self-heals on next launch.
    final cloud = await Future.wait<bool>([
      _guard('expenses', _expenseRepo.clearAllExpenses),
      _guard('budget', _expenseRepo.clearBudgetHistory),
      _guard('salary', _salaryRepo.clearSalaryHistory),
      _guard('savedWords', _savedWordsRepo.clearAll),
      _guard('learnings', _expenseRepo.clearLearnings),
      _guard('savedSearches', _clearSavedSearches),
    ]);

    // Bump the cross-device reset epoch ONLY after the cloud is actually
    // cleared, so other devices that react to the new epoch pull from an
    // already-empty server (no partial re-hydration).
    final resetOk =
        await _guard('reset-epoch', () => _resetSync.recordReset(NukeScope.full));

    sw.stop();

    int c(String key) => counts[key] ?? 0;

    final report = NukeReport(
      scope: NukeScope.full,
      elapsedMs: sw.elapsedMilliseconds,
      fullySynced: localOk && cloud.every((r) => r) && resetOk,
      lines: [
        NukeLine(label: 'Expenses', emoji: '💸', count: c('Expenses'), cloudSynced: cloud[0]),
        NukeLine(label: 'Budget history', emoji: '📊', count: c('Budget history'), cloudSynced: cloud[1]),
        NukeLine(label: 'Salary', emoji: '💰', count: c('Salary'), cloudSynced: cloud[2]),
        NukeLine(label: 'Saved words', emoji: '📖', count: c('Saved words'), cloudSynced: cloud[3]),
        NukeLine(label: 'Learnings', emoji: '🧠', count: c('Learnings'), cloudSynced: cloud[4]),
        NukeLine(label: 'Saved searches', emoji: '🔍', count: c('Saved searches'), cloudSynced: cloud[5]),
        // Local-only: server re-fills news; cloud files are Drive metadata.
        NukeLine(label: 'News', emoji: '📰', count: c('News')),
        NukeLine(label: 'Cloud files', emoji: '☁️', count: c('Cloud files')),
      ],
    );

    final summary = report.fullySynced
        ? '✅ local wiped + cloud synced'
        : '⏳ local wiped — cloud sync pending, will auto-retry on next launch';

    TLog.w(
      _tag,
      '☢️☢️ FULL NUKE complete in ${report.elapsedMs}ms — removed '
      '${report.totalCleared} local rows across ${report.nonEmptyLines.length} '
      'domains [cloud: expenses ${_mark(cloud[0])} · budget ${_mark(cloud[1])} · '
      'salary ${_mark(cloud[2])} · words ${_mark(cloud[3])} · '
      'learnings ${_mark(cloud[4])} · searches ${_mark(cloud[5])} · '
      'cross-device ${_mark(resetOk)}] — $summary',
    );

    return report;
  }

  Future<bool> _guard(String label, Future<bool> Function() op) async {
    try {
      return await op();
    } catch (e, st) {
      TLog.e(
        _tag,
        'Full-nuke cloud step "$label" failed — server clear will be retried '
        'automatically',
        error: e,
        st: st,
      );
      return false;
    }
  }

  String _mark(bool ok) => ok ? '☁️' : '⏳';
}
