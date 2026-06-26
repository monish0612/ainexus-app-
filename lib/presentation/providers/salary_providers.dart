import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/injection.dart';
import '../../core/services/insight_grounding.dart';
import '../../core/services/salary_insight_engine.dart';
import '../../domain/entities/expense_insight.dart';
import '../../domain/entities/salary_entities.dart';
import '../screens/expense/expense_screen.dart' show currentBudgetProvider;
import '../screens/settings/settings_controller.dart';

/// Live salary history (newest month first).
final salaryHistoryStreamProvider =
    StreamProvider<List<SalaryEntry>>((ref) {
  return ref.watch(salaryRepositoryProvider).watchSalaries();
});

/// In-hand salary recorded for the current calendar month (0 when not entered).
final currentSalaryProvider = Provider<double>((ref) {
  final history = ref.watch(salaryHistoryStreamProvider).valueOrNull ?? const [];
  final key = monthKeyOf(DateTime.now());
  for (final e in history) {
    if (e.month == key) return e.amount;
  }
  return 0;
});

/// True once we have at least one salary entry for the current month.
final hasCurrentSalaryProvider = Provider<bool>((ref) {
  return ref.watch(currentSalaryProvider) > 0;
});

/// Month-over-month trend items for the salary history list. Each item carries
/// the previous *recorded* month's amount so the UI can show hike/cut %.
final salaryTrendProvider = Provider<List<SalaryTrendItem>>((ref) {
  final history = ref.watch(salaryHistoryStreamProvider).valueOrNull ?? const [];
  // history is month-desc; compare each to the next (older) one.
  final out = <SalaryTrendItem>[];
  for (var i = 0; i < history.length; i++) {
    final prev = i + 1 < history.length ? history[i + 1].amount : null;
    out.add(SalaryTrendItem(entry: history[i], previousAmount: prev));
  }
  return out;
});

/// Reactive month-to-date spend for the current month, computed as a SQL
/// aggregate over the indexed `date` column — scales to millions of rows
/// without loading them into memory and re-emits when the month's data changes.
final currentMonthSpentProvider = StreamProvider<double>((ref) {
  return ref
      .watch(expenseRepositoryProvider)
      .watchMonthTotal(monthKeyOf(DateTime.now()));
});

/// Reactive per-month total spend across all months ('YYYY-MM' → spend),
/// derived from the compact memory rollup. Used to pair each recorded salary
/// month with its spend for lifetime savings / runway stats.
final monthlySpendTotalsProvider =
    StreamProvider<Map<String, double>>((ref) {
  return ref.watch(expenseRepositoryProvider).watchMonthlySpendTotals();
});

/// Reactive per-month credit-card (cardType 'CC') spend ('YYYY-MM' → CC spend).
/// Feeds the repayment forecast: this month's value becomes next month's bill,
/// last month's value is the bill being repaid from this month's salary.
final ccMonthlyTotalsProvider =
    StreamProvider<Map<String, double>>((ref) {
  return ref.watch(expenseRepositoryProvider).watchMonthlyCardSpendTotals('CC');
});

/// Fully-computed [SalaryStats] for the current month, blending the in-hand
/// salary, the live budget and the DB-aggregated month-to-date spend.
final salaryStatsProvider = Provider<SalaryStats>((ref) {
  final history = ref.watch(salaryHistoryStreamProvider).valueOrNull ?? const [];
  final budget = ref.watch(currentBudgetProvider);
  final spent = ref.watch(currentMonthSpentProvider).valueOrNull ?? 0.0;
  final spendByMonth =
      ref.watch(monthlySpendTotalsProvider).valueOrNull ?? const {};
  final ccByMonth =
      ref.watch(ccMonthlyTotalsProvider).valueOrNull ?? const {};

  return SalaryStats.compute(
    history: history,
    budget: budget,
    spent: spent,
    spendByMonth: spendByMonth,
    ccByMonth: ccByMonth,
    now: DateTime.now(),
  );
});

/// Personalized, grounded AI recommendation for the salary screen.
///
/// Pipeline (identical anti-hallucination contract to the expense insights):
///   1. [SalaryInsightEngine.compute] turns the verified [SalaryStats] into
///      bindable `{{token}}` facts.
///   2. The backend composer (LLM) phrases those tokens into a [ResponseSpec].
///   3. [InsightGrounding.ground] validates + binds — any ungrounded prose (or
///      an offline composer) falls back to the deterministic salary template,
///      so every figure shown is real and the message is always personalized.
///
/// Re-runs whenever the underlying stats change. Network failures degrade to
/// the template rather than throwing, so the UI always has content.
final salaryRecommendationProvider =
    FutureProvider.autoDispose<GroundedRecommendation>((ref) async {
  final stats = ref.watch(salaryStatsProvider);
  final name = ref.watch(userFirstNameProvider);
  final fallback = SalaryInsightEngine.template(stats, name);

  // Nothing to reason about yet — skip the network round-trip entirely.
  if (!stats.hasSalary) return fallback;

  final facts = SalaryInsightEngine.compute(firstName: name, stats: stats);
  try {
    final liteModel = ref.read(settingsProvider).liteModel;
    final spec = await ref
        .read(expenseInsightServiceProvider)
        .compose(facts, liteModel: liteModel);
    final grounded = InsightGrounding.ground(spec, facts);
    // InsightGrounding falls back to its EXPENSE template on failure; prefer our
    // salary-specific template in that case.
    return grounded.isTemplate ? fallback : grounded;
  } catch (_) {
    return fallback;
  }
});
