import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/di/injection.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../domain/entities/salary_entities.dart';
import '../../providers/salary_providers.dart';
import 'modals/expense_ai_ask_sheet.dart';
import 'modals/salary_entry_modal.dart';
import 'widgets/ai_recommendation_card.dart';

const _green = Color(0xFF51CF66);
const _red = Color(0xFFFF6B6B);
const _amber = Color(0xFFFCC419);

/// Full-screen salary & income stats. Opened from the Insights salary card or
/// from the AI search when a question is classified as a salary/income topic.
Future<void> showSalaryScreen(BuildContext context, {String? aiAnswer}) {
  return Navigator.of(context, rootNavigator: true).push<void>(
    PageRouteBuilder<void>(
      opaque: true,
      barrierColor: Colors.black,
      transitionDuration: const Duration(milliseconds: 280),
      reverseTransitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, __, ___) => SalaryScreen(aiAnswer: aiAnswer),
      transitionsBuilder: (_, animation, __, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.04),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    ),
  );
}

class SalaryScreen extends ConsumerWidget {
  const SalaryScreen({super.key, this.aiAnswer});

  /// Optional AI-generated one-liner shown in a banner at the top.
  final String? aiAnswer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final stats = ref.watch(salaryStatsProvider);
    final trend = ref.watch(salaryTrendProvider);
    final firstName = ref.watch(userFirstNameProvider);

    return Scaffold(
      backgroundColor: colors.bg,
      body: Column(
        children: [
          _Header(colors: colors),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
              children: [
                if (aiAnswer != null && aiAnswer!.trim().isNotEmpty)
                  _AiBanner(text: aiAnswer!.trim(), colors: colors),
                _SalaryHero(stats: stats, colors: colors, firstName: firstName),
                const SizedBox(height: 14),
                if (stats.hasSalary) ...[
                  _SalaryAiInsight(colors: colors),
                  const SizedBox(height: 14),
                  _AllocationCard(stats: stats, colors: colors),
                  const SizedBox(height: 14),
                  _StatGrid(stats: stats, colors: colors),
                  const SizedBox(height: 14),
                  _ProjectionCard(stats: stats, colors: colors),
                  const SizedBox(height: 14),
                  if (stats.hasCreditCardActivity) ...[
                    _CreditCardForecastCard(stats: stats, colors: colors),
                    const SizedBox(height: 14),
                  ],
                ],
                if (stats.monthsRecorded > 0) ...[
                  _LifetimeCard(stats: stats, colors: colors),
                  const SizedBox(height: 14),
                ],
                if (trend.length >= 2) ...[
                  _TrendChartCard(trend: trend, colors: colors),
                  const SizedBox(height: 14),
                ],
                _HistoryCard(trend: trend, stats: stats, colors: colors),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Header ─────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({required this.colors});
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: colors.headerBg,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: Icon(Icons.arrow_back, color: colors.text, size: 22),
            tooltip: 'Back',
          ),
          Expanded(
            child: Text(
              'Salary & Income',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: colors.text,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}

class _AiBanner extends StatelessWidget {
  const _AiBanner({required this.text, required this.colors});
  final String text;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.accent.withValues(alpha: 0.16),
            AppColors.accent.withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('✨', style: TextStyle(fontSize: 16)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13.5,
                height: 1.35,
                fontWeight: FontWeight.w600,
                color: colors.text,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Personalized AI insight ──────────────────────────────────────────────────

/// Grounded, personalized AI recommendation for the user's finances. Reuses the
/// same anti-hallucination [AiRecommendationCard] as the expense insights: shows
/// a shimmer while composing, then a verified greeting/headline/tip + follow-up
/// chips. Chips reopen Ask AI primed with the follow-up question.
class _SalaryAiInsight extends ConsumerWidget {
  const _SalaryAiInsight({required this.colors});
  final AppColors colors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(salaryRecommendationProvider);
    return AiRecommendationCard(
      colors: colors,
      loading: async.isLoading,
      recommendation: async.valueOrNull,
      onChip: (chip) {
        HapticFeedback.selectionClick();
        showExpenseAiAskSheet(context, initialQuestion: chip);
      },
    );
  }
}

// ── Hero ─────────────────────────────────────────────────────────────────

class _SalaryHero extends ConsumerWidget {
  const _SalaryHero({
    required this.stats,
    required this.colors,
    required this.firstName,
  });
  final SalaryStats stats;
  final AppColors colors;
  final String firstName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hike = stats.hikePct;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.accent.withValues(alpha: 0.22),
            colors.bg2,
          ],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'In-hand · ${monthKeyLabel(stats.month)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: colors.text3,
                  ),
                ),
              ),
              if (hike != null) ...[
                const SizedBox(width: 8),
                _HikeChip(pct: hike, colors: colors),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Text(
            stats.hasSalary ? formatCurrency(stats.salary) : '—',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 40,
              fontWeight: FontWeight.w800,
              letterSpacing: -1,
              color: colors.text,
            ),
          ),
          const SizedBox(height: 4),
          if (stats.hasSalary)
            Text(
              hike == null
                  ? (firstName.isEmpty
                      ? 'Your take-home pay this month'
                      : '$firstName, this is your take-home pay this month')
                  : (hike > 0
                      ? '${_fmtSigned(stats.hikeAbs)} more than last month'
                      : hike < 0
                          ? '${_fmtSigned(stats.hikeAbs)} vs last month'
                          : 'Same as last month'),
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: colors.text3,
              ),
            )
          else
            Text(
              'Enter the salary you received this month to unlock stats',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: colors.text3,
              ),
            ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => showSalaryEntryModal(context),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: Icon(
                stats.hasSalary ? Icons.edit_outlined : Icons.add,
                size: 18,
              ),
              label: Text(
                stats.hasSalary ? 'Update this month' : 'Enter salary',
                style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Allocation ──────────────────────────────────────────────────────────────

class _AllocationCard extends StatelessWidget {
  const _AllocationCard({required this.stats, required this.colors});
  final SalaryStats stats;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    final s = stats.salary;
    final spent = stats.spent.clamp(0, double.infinity).toDouble();
    final spentFrac = s > 0 ? (spent / s).clamp(0.0, 1.0) : 0.0;
    final savedFrac = (1 - spentFrac).clamp(0.0, 1.0);
    final over = stats.isOverspent;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.bg2,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Where your salary went',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: colors.text,
            ),
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 16,
              child: Row(
                children: [
                  if (spentFrac > 0)
                    Expanded(
                      flex: (spentFrac * 1000).round(),
                      child: Container(color: over ? _red : _amber),
                    ),
                  if (savedFrac > 0)
                    Expanded(
                      flex: (savedFrac * 1000).round(),
                      child: Container(color: _green),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _LegendItem(
                  color: over ? _red : _amber,
                  label: over ? 'Overspent' : 'Spent',
                  value: formatCurrency(stats.spent),
                  sub: '${stats.spentPct.toStringAsFixed(0)}% of salary',
                  colors: colors,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _LegendItem(
                  color: _green,
                  label: stats.saved < 0 ? 'Shortfall' : 'Saved',
                  value: formatCurrency(stats.saved),
                  sub: '${stats.savedPct.toStringAsFixed(0)}% of salary',
                  colors: colors,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({
    required this.color,
    required this.label,
    required this.value,
    required this.sub,
    required this.colors,
  });

  final Color color;
  final String label;
  final String value;
  final String sub;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colors.text3,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: colors.text,
          ),
        ),
        Text(
          sub,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: colors.text4,
          ),
        ),
      ],
    );
  }
}

// ── Stat grid ────────────────────────────────────────────────────────────────

class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.stats, required this.colors});
  final SalaryStats stats;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    final budgetUsed = stats.budget > 0
        ? '${stats.budgetUsedPct.toStringAsFixed(0)}%'
        : 'No budget';
    final budgetSub = stats.budget > 0
        ? '${formatCurrency(stats.spent)} of ${formatCurrency(stats.budget)}'
        : 'Set a budget to track';

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _StatTile(
                icon: Icons.savings_outlined,
                accent: _green,
                title: 'Savings rate',
                value: '${stats.savedPct.clamp(-999, 999).toStringAsFixed(0)}%',
                sub: '${formatCurrency(stats.saved)} kept',
                colors: colors,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatTile(
                icon: Icons.account_balance_wallet_outlined,
                accent: _amber,
                title: 'Budget used',
                value: budgetUsed,
                sub: budgetSub,
                colors: colors,
                danger: stats.isOverBudget,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _StatTile(
                icon: Icons.pie_chart_outline,
                accent: AppColors.accent,
                title: 'Budget of salary',
                value: stats.salary > 0 && stats.budget > 0
                    ? '${stats.budgetPctOfSalary.toStringAsFixed(0)}%'
                    : '—',
                sub: 'committed to budget',
                colors: colors,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatTile(
                icon: Icons.favorite_outline,
                accent: _healthColor(stats.healthScore),
                title: 'Health score',
                value: '${stats.healthScore}',
                sub: _healthLabel(stats.healthScore),
                colors: colors,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.accent,
    required this.title,
    required this.value,
    required this.sub,
    required this.colors,
    this.danger = false,
  });

  final IconData icon;
  final Color accent;
  final String title;
  final String value;
  final String sub;
  final AppColors colors;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.bg2,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: danger ? _red.withValues(alpha: 0.4) : colors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 16, color: accent),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: danger ? _red : colors.text,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: colors.text2,
            ),
          ),
          Text(
            sub,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: colors.text4,
            ),
          ),
        ],
      ),
    );
  }
}

// ── This-month projection ────────────────────────────────────────────────────

class _ProjectionCard extends StatelessWidget {
  const _ProjectionCard({required this.stats, required this.colors});
  final SalaryStats stats;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    final hasBudget = stats.budget > 0;
    final overPace = hasBudget && stats.projectedOverBudget;
    final projColor = stats.projectedSaved < 0 ? _red : _green;

    // Headline message about the current pace.
    final String headline;
    if (stats.projectedSaved < 0) {
      headline = 'At this pace you\'ll overspend by '
          '${formatCurrency(stats.projectedSaved.abs())} this month.';
    } else {
      headline = 'At this pace you\'ll save '
          '${formatCurrency(stats.projectedSaved)} this month.';
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.bg2,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: overPace ? _red.withValues(alpha: 0.4) : colors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.speed_outlined, size: 16, color: colors.text2),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  'This month\'s pace',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: colors.text,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Day ${stats.daysElapsed}/${stats.daysInMonth}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: colors.text4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            headline,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              height: 1.35,
              fontWeight: FontWeight.w600,
              color: projColor,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _MiniStat(
                  label: 'Projected spend',
                  value: formatCurrency(stats.projectedSpend),
                  colors: colors,
                ),
              ),
              Expanded(
                child: _MiniStat(
                  label: 'Daily burn',
                  value: formatCurrency(stats.dailyBurnRate),
                  colors: colors,
                ),
              ),
              Expanded(
                child: _MiniStat(
                  label: 'Safe / day',
                  value: stats.safeToSpendPerDay > 0
                      ? formatCurrency(stats.safeToSpendPerDay)
                      : '₹0',
                  colors: colors,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            hasBudget
                ? 'Spend up to ${formatCurrency(stats.safeToSpendPerDay)}/day '
                    'for the remaining ${stats.daysRemaining} days to stay on budget'
                : 'Set a budget to get a daily safe-to-spend target',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: colors.text4,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Lifetime ──────────────────────────────────────────────────────────────────

class _LifetimeCard extends StatelessWidget {
  const _LifetimeCard({required this.stats, required this.colors});
  final SalaryStats stats;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    final savedColor = stats.cumulativeSaved < 0 ? _red : _green;
    final runway = stats.runwayMonths;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.bg2,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.account_balance_outlined,
                  size: 16, color: colors.text2),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  'Lifetime',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: colors.text,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${stats.monthsRecorded} mo tracked',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: colors.text4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            stats.cumulativeSaved < 0
                ? '-${formatCurrency(stats.cumulativeSaved.abs())}'
                : formatCurrency(stats.cumulativeSaved),
            style: GoogleFonts.plusJakartaSans(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              color: savedColor,
            ),
          ),
          Text(
            stats.cumulativeSaved < 0
                ? 'Net shortfall across recorded months'
                : 'Net saved across recorded months',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
              color: colors.text3,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _MiniStat(
                  label: 'Avg savings rate',
                  value:
                      '${stats.avgSavingsRatePct.clamp(-999, 999).toStringAsFixed(0)}%',
                  colors: colors,
                ),
              ),
              Expanded(
                child: _MiniStat(
                  label: 'Avg monthly spend',
                  value: formatCurrency(stats.avgMonthlySpend),
                  colors: colors,
                ),
              ),
              Expanded(
                child: _MiniStat(
                  label: 'Runway',
                  value: runway != null
                      ? '${runway.toStringAsFixed(1)} mo'
                      : '—',
                  colors: colors,
                ),
              ),
            ],
          ),
          if (runway != null) ...[
            const SizedBox(height: 4),
            Text(
              'Your savings could cover ~${runway.toStringAsFixed(1)} months '
              'of spending at your average burn rate',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: colors.text4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Credit-card repayment forecast ───────────────────────────────────────────

/// Surfaces the timing gap of credit-card spending: money charged this month is
/// a bill that lands next month and is drawn from next month's salary. Shows the
/// forecasted next-month take-home (current salary − this month's CC charges) so
/// swiping the card *feels* like spending real future income.
class _CreditCardForecastCard extends StatelessWidget {
  const _CreditCardForecastCard({required this.stats, required this.colors});
  final SalaryStats stats;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    final chargedThisMonth = stats.ccSpentThisMonth;
    final dueNow = stats.ccDueThisMonth;
    final forecast = stats.forecastNextMonthTakeHome;

    // Severity: red when the bill would leave next month short or negative,
    // amber as a standing caution whenever there's a card bill building up.
    final bool severe =
        stats.ccLeavesNextMonthShort || forecast < 0;
    final accent = severe ? _red : _amber;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.bg2,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.credit_card_outlined, size: 16, color: accent),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  'Credit card forecast',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: colors.text,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Due next month',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (chargedThisMonth > 0) ...[
            Text(
              'Forecasted take-home next month',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
                color: colors.text3,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Flexible(
                  child: Text(
                    forecast < 0
                        ? '-${formatCurrency(forecast.abs())}'
                        : formatCurrency(forecast),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                      color: accent,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              '${formatCurrency(stats.salary)} salary − '
              '${formatCurrency(chargedThisMonth)} card bill',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: colors.text4,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _MiniStat(
                    label: 'Charged this month',
                    value: formatCurrency(chargedThisMonth),
                    colors: colors,
                  ),
                ),
                Expanded(
                  child: _MiniStat(
                    label: 'Repay next month',
                    value: formatCurrency(chargedThisMonth),
                    colors: colors,
                  ),
                ),
                Expanded(
                  child: _MiniStat(
                    label: 'Of salary',
                    value:
                        '${stats.ccPctOfSalary.clamp(0, 999).toStringAsFixed(0)}%',
                    colors: colors,
                  ),
                ),
              ],
            ),
          ],
          if (dueNow > 0) ...[
            if (chargedThisMonth > 0) const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.bg3,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Icon(Icons.event_repeat_outlined,
                      size: 15, color: colors.text3),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Last month\'s ${formatCurrency(dueNow)} card bill is due '
                      'now — real take-home this month is '
                      '${formatCurrency(stats.effectiveTakeHomeThisMonth)}.',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11.5,
                        height: 1.35,
                        fontWeight: FontWeight.w500,
                        color: colors.text2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (chargedThisMonth > 0) ...[
            const SizedBox(height: 10),
            Text(
              forecast < 0
                  ? 'This bill alone outweighs a full month\'s salary — pause '
                      'card spending before it snowballs.'
                  : 'Every card swipe shrinks next month\'s pay. Spend like '
                      'it\'s already gone.',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                height: 1.3,
                fontWeight: FontWeight.w500,
                color: colors.text4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Trend chart ──────────────────────────────────────────────────────────────

class _TrendChartCard extends StatelessWidget {
  const _TrendChartCard({required this.trend, required this.colors});
  final List<SalaryTrendItem> trend;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    // Oldest → newest, last 12 months for readability.
    final items = trend.reversed.toList();
    final shown =
        items.length > 12 ? items.sublist(items.length - 12) : items;
    final maxAmt = shown.fold<double>(
        0, (m, e) => e.amount > m ? e.amount : m);
    final maxY = maxAmt <= 0 ? 1.0 : maxAmt * 1.18;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
      decoration: BoxDecoration(
        color: colors.bg2,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Salary over time',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: colors.text,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 150,
            child: BarChart(
              BarChartData(
                maxY: maxY,
                alignment: BarChartAlignment.spaceAround,
                barTouchData: BarTouchData(
                  enabled: true,
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => colors.bg4,
                    getTooltipItem: (group, _, rod, __) {
                      final item = shown[group.x.toInt()];
                      return BarTooltipItem(
                        '${monthKeyShort(item.month)}\n',
                        GoogleFonts.plusJakartaSans(
                          color: colors.text,
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                        children: [
                          TextSpan(
                            text: formatCurrency(item.amount),
                            style: GoogleFonts.plusJakartaSans(
                              color: colors.text2,
                              fontWeight: FontWeight.w600,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  leftTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      getTitlesWidget: (value, _) {
                        final i = value.toInt();
                        if (i < 0 || i >= shown.length) {
                          return const SizedBox.shrink();
                        }
                        // Thin out labels when crowded.
                        if (shown.length > 6 && i % 2 != 0) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            monthKeyShort(shown[i].month),
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              color: colors.text4,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                barGroups: [
                  for (var i = 0; i < shown.length; i++)
                    BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: shown[i].amount,
                          width: 14,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(5),
                          ),
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              AppColors.accent.withValues(alpha: 0.55),
                              AppColors.accent,
                            ],
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── History ──────────────────────────────────────────────────────────────────

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({
    required this.trend,
    required this.stats,
    required this.colors,
  });

  final List<SalaryTrendItem> trend;
  final SalaryStats stats;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      decoration: BoxDecoration(
        color: colors.bg2,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Monthly history',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: colors.text,
                  ),
                ),
              ),
              if (stats.monthsRecorded > 0)
                Text(
                  '${stats.monthsRecorded} mo',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colors.text4,
                  ),
                ),
            ],
          ),
          if (stats.monthsRecorded > 0) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _MiniStat(
                    label: 'Total earned',
                    value: formatCurrency(stats.totalRecorded),
                    colors: colors,
                  ),
                ),
                Expanded(
                  child: _MiniStat(
                    label: 'Average',
                    value: formatCurrency(stats.averageSalary),
                    colors: colors,
                  ),
                ),
                Expanded(
                  child: _MiniStat(
                    label: 'Highest',
                    value: formatCurrency(stats.highestSalary),
                    colors: colors,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          if (trend.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'No salary recorded yet.\nEnter your in-hand salary to start tracking.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    height: 1.4,
                    fontWeight: FontWeight.w500,
                    color: colors.text4,
                  ),
                ),
              ),
            )
          else
            for (final item in trend)
              _HistoryRow(item: item, colors: colors),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.label,
    required this.value,
    required this.colors,
  });
  final String label;
  final String value;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 14.5,
            fontWeight: FontWeight.w800,
            color: colors.text,
          ),
        ),
        Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 10.5,
            fontWeight: FontWeight.w500,
            color: colors.text4,
          ),
        ),
      ],
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.item, required this.colors});
  final SalaryTrendItem item;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          Expanded(
            child: Text(
              monthKeyLabel(item.month),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: colors.text,
              ),
            ),
          ),
          if (item.deltaPct != null) ...[
            _HikeChip(pct: item.deltaPct!, colors: colors, small: true),
            const SizedBox(width: 10),
          ],
          // Flexible so an ultra-narrow screen ellipsizes rather than overflows.
          Flexible(
            child: Text(
              formatCurrency(item.amount),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14.5,
                fontWeight: FontWeight.w800,
                color: colors.text,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Shared bits ──────────────────────────────────────────────────────────────

class _HikeChip extends StatelessWidget {
  const _HikeChip({
    required this.pct,
    required this.colors,
    this.small = false,
  });
  final double pct;
  final AppColors colors;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final flat = pct.abs() < 0.05;
    final up = pct > 0;
    final color = flat ? colors.text4 : (up ? _green : _red);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: small ? 7 : 9,
        vertical: small ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(small ? 8 : 10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            flat
                ? Icons.remove
                : (up ? Icons.trending_up : Icons.trending_down),
            size: small ? 12 : 14,
            color: color,
          ),
          const SizedBox(width: 3),
          Text(
            flat ? '0%' : '${up ? '+' : ''}${pct.toStringAsFixed(1)}%',
            style: GoogleFonts.plusJakartaSans(
              fontSize: small ? 11 : 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

String _fmtSigned(double? v) {
  if (v == null) return '';
  final s = formatCurrency(v.abs());
  return v >= 0 ? s : '-$s';
}

Color _healthColor(int score) {
  if (score >= 70) return _green;
  if (score >= 40) return _amber;
  return _red;
}

String _healthLabel(int score) {
  if (score >= 80) return 'Excellent';
  if (score >= 60) return 'Healthy';
  if (score >= 40) return 'Okay';
  if (score > 0) return 'Tight';
  return 'Set salary';
}
