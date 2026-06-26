import '../../domain/entities/expense_insight.dart';
import '../../domain/entities/salary_entities.dart';
import '../utils/currency_formatter.dart';

/// Pure, deterministic computation of [InsightFacts] from a [SalaryStats]
/// snapshot, plus a salary-specific deterministic [GroundedRecommendation]
/// fallback.
///
/// Mirrors [ExpenseInsightEngine] exactly: EVERY figure the AI can mention is
/// pre-computed here as a real value and exposed as a bindable `{{token}}`. The
/// composer (LLM) only phrases/arranges these verified tokens — it never
/// originates a number — so a salary/savings recommendation is dynamic AND
/// impossible to hallucinate. Ungrounded prose falls back to [template].
class SalaryInsightEngine {
  const SalaryInsightEngine._();

  /// Default question used when surfacing the insight passively (no user query).
  static const defaultQuestion =
      'How are my finances, savings and budget this month?';

  static InsightFacts compute({
    required String firstName,
    required SalaryStats stats,
    String question = defaultQuestion,
  }) {
    final t = <String, InsightToken>{};
    final fn = firstName.trim().isEmpty ? 'there' : firstName.trim();
    t['name'] = InsightToken(fn);
    t['month'] = InsightToken(monthKeyLabel(stats.month));

    final hasData = stats.hasSalary;

    // ── Core income / spend / savings ────────────────────────────────────────
    t['salary'] = InsightToken(formatCurrency(stats.salary), number: _r(stats.salary));
    t['spent'] = InsightToken(formatCurrency(stats.spent), number: _r(stats.spent));
    t['saved'] = InsightToken(formatCurrency(stats.saved), number: _r(stats.saved));
    t['savedPct'] = InsightToken(_pct(stats.savedPct), number: stats.savedPct.round());
    t['spentPct'] = InsightToken(_pct(stats.spentPct), number: stats.spentPct.round());

    // ── Budget ───────────────────────────────────────────────────────────────
    if (stats.budget > 0) {
      t['budget'] =
          InsightToken(formatCurrency(stats.budget), number: _r(stats.budget));
      t['budgetUsedPct'] =
          InsightToken(_pct(stats.budgetUsedPct), number: stats.budgetUsedPct.round());
      t['budgetPctOfSalary'] = InsightToken(_pct(stats.budgetPctOfSalary),
          number: stats.budgetPctOfSalary.round());
    }

    // ── Salary hike vs previous recorded month ───────────────────────────────
    final hikePct = stats.hikePct;
    final hikeAbs = stats.hikeAbs;
    if (hikePct != null) {
      final sign = hikePct > 0 ? '+' : '';
      t['hikePct'] =
          InsightToken('$sign${hikePct.toStringAsFixed(1)}%', number: _r(hikePct));
    }
    if (hikeAbs != null) {
      t['hikeAbs'] = InsightToken(formatCurrency(hikeAbs.abs()), number: _r(hikeAbs.abs()));
      t['hikeDirection'] = InsightToken(
          hikeAbs > 0 ? 'more' : (hikeAbs < 0 ? 'less' : 'the same'));
    }

    // ── This-month projection / pace ─────────────────────────────────────────
    t['projectedSpend'] = InsightToken(formatCurrency(stats.projectedSpend),
        number: _r(stats.projectedSpend));
    t['projectedSaved'] = InsightToken(formatCurrency(stats.projectedSaved),
        number: _r(stats.projectedSaved));
    t['dailyBurn'] = InsightToken(formatCurrency(stats.dailyBurnRate),
        number: _r(stats.dailyBurnRate));
    t['safePerDay'] = InsightToken(formatCurrency(stats.safeToSpendPerDay),
        number: _r(stats.safeToSpendPerDay));
    t['daysRemaining'] =
        InsightToken('${stats.daysRemaining}', number: stats.daysRemaining);

    // ── Lifetime ─────────────────────────────────────────────────────────────
    t['cumulativeSaved'] = InsightToken(formatCurrency(stats.cumulativeSaved),
        number: _r(stats.cumulativeSaved));
    t['avgSavingsRate'] = InsightToken(_pct(stats.avgSavingsRatePct),
        number: stats.avgSavingsRatePct.round());
    t['avgMonthlySpend'] = InsightToken(formatCurrency(stats.avgMonthlySpend),
        number: _r(stats.avgMonthlySpend));
    final runway = stats.runwayMonths;
    if (runway != null) {
      t['runway'] = InsightToken('${runway.toStringAsFixed(1)} months',
          number: _r1(runway));
    }
    // ── Credit-card repayment forecast ───────────────────────────────────────
    if (stats.hasCreditCardActivity) {
      t['ccThisMonth'] = InsightToken(formatCurrency(stats.ccSpentThisMonth),
          number: _r(stats.ccSpentThisMonth));
      t['ccDueThisMonth'] = InsightToken(formatCurrency(stats.ccDueThisMonth),
          number: _r(stats.ccDueThisMonth));
      t['forecastNextTakeHome'] = InsightToken(
          formatCurrency(stats.forecastNextMonthTakeHome),
          number: _r(stats.forecastNextMonthTakeHome));
      t['effectiveTakeHome'] = InsightToken(
          formatCurrency(stats.effectiveTakeHomeThisMonth),
          number: _r(stats.effectiveTakeHomeThisMonth));
      t['ccPctOfSalary'] = InsightToken(_pct(stats.ccPctOfSalary),
          number: stats.ccPctOfSalary.round());
    }

    t['monthsTracked'] =
        InsightToken('${stats.monthsRecorded}', number: stats.monthsRecorded);
    if (stats.monthsRecorded > 0) {
      t['highestSalary'] = InsightToken(formatCurrency(stats.highestSalary),
          number: _r(stats.highestSalary));
      t['averageSalary'] = InsightToken(formatCurrency(stats.averageSalary),
          number: _r(stats.averageSalary));
    }

    return InsightFacts(
      question: question,
      firstName: fn,
      tokens: t,
      tone: _tone(stats),
      hasData: hasData,
    );
  }

  /// Deterministic, always-grounded salary recommendation built directly from
  /// [stats] — used when the composer is offline or its prose fails grounding.
  /// Marked [isTemplate] so analytics can tell it apart (never shown to users).
  static GroundedRecommendation template(SalaryStats stats, String firstName) {
    final fn = firstName.trim().isEmpty ? '' : firstName.trim();
    final greeting = fn.isEmpty ? 'Hey,' : 'Hey $fn,';

    if (!stats.hasSalary) {
      return GroundedRecommendation(
        greeting: greeting,
        headline: 'Add this month\'s salary to unlock your insights.',
        tip: 'Once I know your in-hand pay, I can track savings, budget pace '
            'and your runway.',
        tone: InsightTone.info,
        chips: const ['Enter salary', 'Set a budget'],
        isTemplate: true,
      );
    }

    // Headline: lead with savings, flag overspending.
    final String headline;
    if (stats.isOverspent) {
      headline =
          'You\'ve spent ${formatCurrency(stats.spent)} — more than your '
          '${formatCurrency(stats.salary)} salary this month.';
    } else {
      headline = 'You\'ve saved ${formatCurrency(stats.saved)} '
          '(${_pct(stats.savedPct)}) of your ${formatCurrency(stats.salary)} '
          'salary so far.';
    }

    // Tip: lead with the credit-card repayment warning when there's CC spend —
    // that's the most actionable, behaviour-shaping signal — then fall back to
    // the forward-looking pace + a concrete safe-to-spend or runway nudge.
    final tip = StringBuffer();
    if (stats.ccSpentThisMonth > 0) {
      tip.write('Heads up: you\'ve charged '
          '${formatCurrency(stats.ccSpentThisMonth)} to credit this month. '
          'That bill comes out of next month\'s pay, leaving about '
          '${formatCurrency(stats.forecastNextMonthTakeHome)} to live on. ');
    } else if (stats.ccDueThisMonth > 0) {
      tip.write('Last month\'s card bill of '
          '${formatCurrency(stats.ccDueThisMonth)} is due now, so your real '
          'take-home is ${formatCurrency(stats.effectiveTakeHomeThisMonth)}. ');
    }
    if (stats.projectedSaved < 0) {
      tip.write('At this pace you\'ll overspend by '
          '${formatCurrency(stats.projectedSaved.abs())} by month-end.');
    } else {
      tip.write('At this pace you\'re on track to save '
          '${formatCurrency(stats.projectedSaved)} this month.');
    }
    if (stats.budget > 0 && stats.safeToSpendPerDay > 0) {
      tip.write(' Keep spending under '
          '${formatCurrency(stats.safeToSpendPerDay)}/day to stay on budget.');
    } else if (stats.runwayMonths != null) {
      tip.write(' Your savings now cover about '
          '${stats.runwayMonths!.toStringAsFixed(1)} months of spending.');
    }

    final chips = <String>[
      if (stats.ccSpentThisMonth > 0) 'What\'s my card bill next month?',
      'How can I save more?',
      if (stats.budget <= 0) 'Set a budget' else 'Am I on track this month?',
      'Did I get a hike?',
    ];

    return GroundedRecommendation(
      greeting: greeting,
      headline: headline,
      tip: tip.toString(),
      tone: _tone(stats),
      chips: chips.take(3).toList(),
      isTemplate: true,
    );
  }

  static InsightTone _tone(SalaryStats stats) {
    if (!stats.hasSalary) return InsightTone.info;
    if (stats.isOverspent ||
        stats.projectedOverBudget ||
        stats.ccLeavesNextMonthShort) {
      return InsightTone.warning;
    }
    if (stats.savedPct >= 20 || (stats.hikePct ?? 0) > 0) {
      return InsightTone.positive;
    }
    return InsightTone.info;
  }

  static int _r(num v) => v.round();

  /// One-decimal rounding kept as a num for the grounding validator.
  static num _r1(num v) => (v * 10).round() / 10;

  static String _pct(double v) => '${v.round()}%';
}
