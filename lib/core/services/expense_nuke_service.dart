import '../../data/repositories/expense_repository.dart';
import '../../data/repositories/salary_repository.dart';
import 'nuke_report.dart';
import 'reset_sync_service.dart';
import 'telegram_logger.dart';

/// The expense-scope "nuke" engine — a single, robust, fire-once reset that
/// wipes the financial domain (expenses, budget history, salary history) from
/// both the local Drift DB and the cloud backend, returning the expense
/// feature to a true from-scratch state.
///
/// Design goals (production-grade):
///  • **Fluid & fast** — the three domains are cleared *in parallel*, so the
///    whole nuke is bounded by the slowest single domain rather than their sum.
///  • **Local-first** — each underlying repo deletes locally first (instant UI
///    refresh via Drift streams) before touching the network.
///  • **Robust retry** — every server delete already runs through exponential
///    backoff + a GET verification pass inside the repos; if the cloud is
///    unreachable the wipe is flagged and replayed automatically on next launch
///    (`retryPendingClears` / `retryPendingClear`). Nothing is silently lost.
///  • **Telegram flow logs** — a bold start banner, each repo's own step log,
///    then a single summary banner with timings + per-domain sync status.
///  • **Crash-proof** — every step is guarded; a throw in one domain can never
///    abort the others, and never crashes the app.
class ExpenseNukeService {
  ExpenseNukeService(this._expenseRepo, this._salaryRepo, this._resetSync);

  final ExpenseRepository _expenseRepo;
  final SalaryRepository _salaryRepo;
  final ResetSyncService _resetSync;

  static const _tag = 'Nuke';

  Future<NukeReport> nuke() async {
    final sw = Stopwatch()..start();

    // Snapshot counts *before* wiping so the logs/UI can report exactly what
    // was destroyed. Best-effort — a count failure must never block the wipe.
    final counts = await _snapshotCounts();

    TLog.w(
      _tag,
      '☢️ NUKE initiated — wiping ${counts.expenses} expenses · '
      '${counts.budget} budget entries · ${counts.salary} salary entries '
      'from local + cloud. This is irreversible.',
    );

    // Parallel wipe. Each repo method is already local-first + retry + verify
    // + pending-flag-on-failure, so we just orchestrate and aggregate here.
    final results = await Future.wait<bool>([
      _guard('expenses', _expenseRepo.clearAllExpenses),
      _guard('budget', _expenseRepo.clearBudgetHistory),
      _guard('salary', _salaryRepo.clearSalaryHistory),
    ]);

    // Propagate to other devices — bump the expense reset epoch AFTER the cloud
    // financial data is cleared.
    final resetOk = await _guard(
        'reset-epoch', () => _resetSync.recordReset(NukeScope.expense));

    sw.stop();

    final report = NukeReport(
      scope: NukeScope.expense,
      elapsedMs: sw.elapsedMilliseconds,
      fullySynced: results.every((r) => r) && resetOk,
      lines: [
        NukeLine(
          label: 'Expenses',
          emoji: '💸',
          count: counts.expenses,
          cloudSynced: results[0],
        ),
        NukeLine(
          label: 'Budget history',
          emoji: '📊',
          count: counts.budget,
          cloudSynced: results[1],
        ),
        NukeLine(
          label: 'Salary',
          emoji: '💰',
          count: counts.salary,
          cloudSynced: results[2],
        ),
      ],
    );

    final summary = report.fullySynced
        ? '✅ fully synced to cloud'
        : '⏳ cloud sync pending — will auto-retry on next launch';

    TLog.w(
      _tag,
      '☢️ NUKE complete in ${report.elapsedMs}ms — removed '
      '${report.totalCleared} records '
      '[expenses ${counts.expenses} ${_mark(results[0])} · '
      'budget ${counts.budget} ${_mark(results[1])} · '
      'salary ${counts.salary} ${_mark(results[2])}] — $summary',
    );

    return report;
  }

  /// Wraps a single domain clear so a thrown error is logged and downgraded to
  /// "not synced" instead of taking down the whole parallel nuke.
  Future<bool> _guard(String label, Future<bool> Function() op) async {
    try {
      return await op();
    } catch (e, st) {
      TLog.e(
        _tag,
        'Nuke step "$label" failed hard — local state may be cleared, '
        'server clear will be retried automatically',
        error: e,
        st: st,
      );
      return false;
    }
  }

  Future<({int expenses, int budget, int salary})> _snapshotCounts() async {
    var expenses = 0;
    var budget = 0;
    var salary = 0;
    try {
      expenses = (await _expenseRepo.rangeSummary()).count;
    } catch (_) {/* telemetry only — ignore */}
    try {
      budget = await _expenseRepo.budgetHistoryCount();
    } catch (_) {/* telemetry only — ignore */}
    try {
      salary = await _salaryRepo.salaryCount();
    } catch (_) {/* telemetry only — ignore */}
    return (expenses: expenses, budget: budget, salary: salary);
  }

  String _mark(bool ok) => ok ? '☁️' : '⏳';
}
