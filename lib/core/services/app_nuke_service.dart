import '../../data/local/database/app_database.dart';
import '../../data/repositories/expense_repository.dart';
import '../../data/repositories/salary_repository.dart';
import 'nuke_report.dart';
import 'telegram_logger.dart';

/// The full-app "nuke" engine — the nuclear option triggered from the InsightAI
/// search box. It resets the app to a pristine, first-launch data state by
/// deleting **every row from every table** locally (schema preserved — tables
/// are never dropped), and clearing the cloud for every domain that exposes a
/// bulk-delete (the financial tables).
///
/// Domains without a bulk cloud-delete (news, cloud files, saved words, saved
/// searches, learnings) are wiped locally only; they are server-owned caches
/// that simply re-hydrate on next use, so there is nothing to "sync away".
///
/// Robustness mirrors [ExpenseNukeService]: local wipe is atomic (single
/// transaction), cloud clears run the repos' exponential-backoff + verify +
/// pending-flag self-heal, every step is guarded, and the whole flow is logged
/// to Telegram with a start banner + a summary banner.
class AppNukeService {
  AppNukeService(this._db, this._expenseRepo, this._salaryRepo);

  final AppDatabase _db;
  final ExpenseRepository _expenseRepo;
  final SalaryRepository _salaryRepo;

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
      'financial data. Tables preserved, rows reset. This is irreversible.',
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

    // 2) Cloud wipe for the domains that support a bulk delete. These repo
    //    methods are local-first (now a no-op) + server DELETE + verify +
    //    retry + pending-flag, so a cloud outage self-heals on next launch.
    final cloud = await Future.wait<bool>([
      _guard('expenses', _expenseRepo.clearAllExpenses),
      _guard('budget', _expenseRepo.clearBudgetHistory),
      _guard('salary', _salaryRepo.clearSalaryHistory),
    ]);

    sw.stop();

    int c(String key) => counts[key] ?? 0;

    final report = NukeReport(
      scope: NukeScope.full,
      elapsedMs: sw.elapsedMilliseconds,
      fullySynced: localOk && cloud.every((r) => r),
      lines: [
        NukeLine(label: 'Expenses', emoji: '💸', count: c('Expenses'), cloudSynced: cloud[0]),
        NukeLine(label: 'Budget history', emoji: '📊', count: c('Budget history'), cloudSynced: cloud[1]),
        NukeLine(label: 'Salary', emoji: '💰', count: c('Salary'), cloudSynced: cloud[2]),
        NukeLine(label: 'News', emoji: '📰', count: c('News')),
        NukeLine(label: 'Saved words', emoji: '📖', count: c('Saved words')),
        NukeLine(label: 'Cloud files', emoji: '☁️', count: c('Cloud files')),
        NukeLine(label: 'Saved searches', emoji: '🔍', count: c('Saved searches')),
        NukeLine(label: 'Learnings', emoji: '🧠', count: c('Learnings')),
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
      'salary ${_mark(cloud[2])}] — $summary',
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
