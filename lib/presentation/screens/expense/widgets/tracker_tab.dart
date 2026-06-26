import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../domain/entities/expense_entities.dart';
import './budget_ring.dart';
import './expense_item.dart';

/// Main expense tracker view (aligned with [docs/figma_source/TrackerTab.tsx], with
/// analysis periods Today / 7D / 1M / 6M / All per product spec).
class TrackerTab extends StatefulWidget {
  const TrackerTab({
    super.key,
    required this.expenses,
    required this.budget,
    required this.budgetHistory,
    required this.learnings,
    required this.onAddExpense,
    required this.onDeleteExpense,
    required this.onUpdateExpense,
    required this.onSetBudget,
    required this.onUpdateLearnings,
    required this.onEditExpense,
    required this.onShowTrend,
    required this.onShowBudgetHistory,
    required this.onOpenTimeframe,
  });

  final List<ExpenseData> expenses;
  final double budget;
  final List<BudgetHistoryEntry> budgetHistory;
  final Map<String, String> learnings;
  final VoidCallback onAddExpense;
  final void Function(String id) onDeleteExpense;
  final void Function(ExpenseData expense) onUpdateExpense;
  final VoidCallback onSetBudget;
  final VoidCallback onUpdateLearnings;
  final void Function(ExpenseData expense) onEditExpense;
  final VoidCallback onShowTrend;
  final VoidCallback onShowBudgetHistory;

  /// Opens the full-screen drill-down for the spending-analysis period at
  /// [index] (0=Today, 1=7D, 2=1M, 3=6M, 4=All).
  final void Function(int index) onOpenTimeframe;

  @override
  State<TrackerTab> createState() => _TrackerTabState();
}

class _TrackerTabState extends State<TrackerTab> {
  static const List<String> _analysisLabels = [
    'Today',
    '7D',
    '1M',
    '6M',
    'All',
  ];

  late final PageController _analysisPageController;
  int _analysisIndex = 0;
  int _analysisDir = 1;
  @override
  void initState() {
    super.initState();
    _analysisPageController = PageController(initialPage: _analysisIndex);
  }

  @override
  void dispose() {
    _analysisPageController.dispose();
    super.dispose();
  }

  DateTime _parseDate(String raw) => safeParseDate(raw);

  List<ExpenseData> _expensesInCurrentMonth(DateTime now) {
    final start = DateTime(now.year, now.month, 1);
    return widget.expenses.where((e) {
      final d = _parseDate(e.date);
      return !d.isBefore(start) &&
          d.year == now.year &&
          d.month == now.month;
    }).toList();
  }

  double _sumAmounts(Iterable<ExpenseData> items) =>
      items.fold<double>(0, (s, e) => s + e.amount.toDouble());

  List<ExpenseData> _analysisExpenses(int index, DateTime now) {
    switch (index) {
      case 0:
        final start = DateTime(now.year, now.month, now.day);
        return widget.expenses
            .where((e) => !_parseDate(e.date).isBefore(start))
            .toList();
      case 1:
        final start = DateTime(now.year, now.month, now.day)
            .subtract(const Duration(days: 6));
        return widget.expenses
            .where((e) => !_parseDate(e.date).isBefore(start))
            .toList();
      case 2:
        final start = DateTime(now.year, now.month, 1);
        return widget.expenses
            .where((e) => !_parseDate(e.date).isBefore(start))
            .toList();
      case 3:
        final start = DateTime(now.year, now.month - 6, 1);
        return widget.expenses
            .where((e) => !_parseDate(e.date).isBefore(start))
            .toList();
      default:
        return List<ExpenseData>.from(widget.expenses);
    }
  }

  _BalanceCardTheme _balanceCardTheme({
    required AppColors colors,
    required double budget,
    required double monthSpent,
  }) {
    final isDark = colors.isDark;
    final hasBudget = budget > 0;
    final over = hasBudget && monthSpent > budget;
    final pct = hasBudget ? (monthSpent / budget).clamp(0.0, 1.0) : 0.0;
    final atRisk = hasBudget && !over && pct > 0.75;

    if (!hasBudget) {
      return _BalanceCardTheme(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? const [
                  Color(0xFF1A1035),
                  Color(0xFF261848),
                  Color(0xFF1A1035),
                ]
              : const [
                  Color(0xFFF5F3FF),
                  Color(0xFFEDE9FE),
                ],
        ),
        shadow: isDark
            ? const Color(0x477C3AED)
            : const Color(0x1F7C3AED),
        statusLabel: 'SET BUDGET',
        statusColor: isDark ? const Color(0xFFC4B5FD) : const Color(0xFF7C3AED),
        statusBg: const Color(0x2E7C3AED),
        ringColor: const Color(0xFF7C3AED),
        useLightForeground: isDark,
      );
    }
    if (over) {
      return _BalanceCardTheme(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? const [
                  Color(0xFF3D0505),
                  Color(0xFF5C0D0D),
                  Color(0xFF3D0505),
                ]
              : const [
                  Color(0xFFFFF1F2),
                  Color(0xFFFFE4E6),
                ],
        ),
        shadow: isDark
            ? const Color(0x80EF4444)
            : const Color(0x26EF4444),
        statusLabel: 'OVER BUDGET',
        statusColor: isDark ? const Color(0xFFFCA5A5) : const Color(0xFFDC2626),
        statusBg: const Color(0x26EF4444),
        ringColor: const Color(0xFFEF4444),
        useLightForeground: isDark,
      );
    }
    if (atRisk) {
      return _BalanceCardTheme(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? const [
                  Color(0xFF2A1500),
                  Color(0xFF3E1E00),
                  Color(0xFF2A1500),
                ]
              : const [
                  Color(0xFFFFFBEB),
                  Color(0xFFFEF3C7),
                ],
        ),
        shadow: isDark
            ? const Color(0x4DF59E0B)
            : const Color(0x26F59E0B),
        statusLabel: 'AT RISK',
        statusColor: isDark ? const Color(0xFFFCD34D) : const Color(0xFFD97706),
        statusBg: const Color(0x26F59E0B),
        ringColor: const Color(0xFFF59E0B),
        useLightForeground: isDark,
      );
    }
    return _BalanceCardTheme(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: isDark
            ? const [
                Color(0xFF022C1A),
                Color(0xFF04402A),
                Color(0xFF022C1A),
              ]
            : const [
                Color(0xFFECFDF5),
                Color(0xFFD1FAE5),
              ],
      ),
      shadow: isDark
          ? const Color(0x3822C55E)
          : const Color(0x2622C55E),
      statusLabel: 'ON TRACK',
      statusColor: isDark ? const Color(0xFF86EFAC) : const Color(0xFF16A34A),
      statusBg: const Color(0x2622C55E),
      ringColor: const Color(0xFF22C55E),
      useLightForeground: isDark,
    );
  }

  String? _smartTip({
    required double monthSpent,
    required double budget,
    required List<_CategorySlice> allTimeTop,
  }) {
    final fromLearnings = widget.learnings['tip'] ??
        widget.learnings['insight'] ??
        widget.learnings['summary'];
    if (fromLearnings != null && fromLearnings.trim().isNotEmpty) {
      return fromLearnings.trim();
    }
    if (widget.expenses.isEmpty) return null;
    final top = allTimeTop.isNotEmpty ? allTimeTop.first : null;
    if (top == null) return null;
    final hasBudget = budget > 0;
    final over = hasBudget && monthSpent > budget;
    final budgetPct = hasBudget ? (monthSpent / budget).clamp(0.0, 1.0) : 0.0;
    if (over) {
      return '⚠️ Over budget by ${formatCurrency(monthSpent - budget)}. Review your ${top.category} expenses.';
    }
    if (top.pct > 40) {
      return '${top.category} takes up ${top.pct.round()}% of your spending. Consider a sub-limit.';
    }
    if (hasBudget && budgetPct > 0.7) {
      return 'You\'ve used ${(budgetPct * 100).round()}% of your budget. Slow down on ${top.category}!';
    }
    return 'Top category: ${top.category} at ${formatCurrency(top.total)}. You\'re doing well! 🎉';
  }

  List<_CategorySlice> _categorySlices(List<ExpenseData> scope) {
    final total = _sumAmounts(scope);
    final map = <String, double>{};
    for (final e in scope) {
      map[e.category] = (map[e.category] ?? 0) + e.amount.toDouble();
    }
    final entries = map.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries
        .take(5)
        .map(
          (e) => _CategorySlice(
            category: e.key,
            total: e.value,
            pct: total > 0 ? (e.value / total) * 100 : 0,
            color: AppColors.categoryColors[e.key] ?? const Color(0xFF818CF8),
          ),
        )
        .toList();
  }

  List<ExpenseData> _last24Hours(DateTime now) {
    final cutoff = now.subtract(const Duration(hours: 24));
    final recent = widget.expenses
        .where((e) => !_parseDate(e.date).isBefore(cutoff))
        .toList()
      ..sort((a, b) => _parseDate(b.date).compareTo(_parseDate(a.date)));
    return recent;
  }

  void _goAnalysis(int index) {
    if (index == _analysisIndex ||
        index < 0 ||
        index >= _analysisLabels.length) {
      return;
    }
    setState(() {
      _analysisDir = index > _analysisIndex ? 1 : -1;
      _analysisIndex = index;
    });
    _analysisPageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  void _onAnalysisPageChanged(int i) {
    if (i == _analysisIndex) return;
    setState(() {
      _analysisDir = i > _analysisIndex ? 1 : -1;
      _analysisIndex = i;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final now = DateTime.now();
    final monthList = _expensesInCurrentMonth(now);
    final monthSpent = _sumAmounts(monthList);
    final cardTheme = _balanceCardTheme(
      colors: colors,
      budget: widget.budget,
      monthSpent: monthSpent,
    );
    final titleColor =
        cardTheme.useLightForeground ? Colors.white : colors.text;
    final subtitleColor = cardTheme.useLightForeground
        ? Colors.white.withValues(alpha: 0.4)
        : colors.text3;

    final startOfMonth = DateTime(now.year, now.month, 1);
    final daysElapsed =
        now.difference(startOfMonth).inDays + 1; // 1..last day of month
    final dailyAvg = monthSpent / math.max(1, daysElapsed);
    double highestMonth = 0;
    for (final e in monthList) {
      highestMonth = math.max(highestMonth, e.amount.toDouble());
    }
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayExpenses = widget.expenses
        .where((e) => !_parseDate(e.date).isBefore(todayStart) &&
            _parseDate(e.date).isBefore(todayStart.add(const Duration(days: 1))))
        .toList();
    final txToday = todayExpenses.length;
    final todaySpent = _sumAmounts(todayExpenses);

    final allTimeSlices = _categorySlices(widget.expenses);
    final tip = _smartTip(
      monthSpent: monthSpent,
      budget: widget.budget,
      allTimeTop: allTimeSlices,
    );

    final recent24h = _last24Hours(now);

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 120),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: _TotalBalanceCard(
              theme: cardTheme,
              titleColor: titleColor,
              subtitleColor: subtitleColor,
              monthSpent: monthSpent,
              todaySpent: todaySpent,
              txToday: txToday,
              budget: widget.budget,
              monthSpentFormatted: formatCurrency(monthSpent),
              historyCount: widget.budgetHistory.length,
              onSetBudget: widget.onSetBudget,
              onShowBudgetHistory: widget.onShowBudgetHistory,
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: BudgetRing(
              budget: widget.budget,
              spent: monthSpent,
              onSetBudget: widget.onSetBudget,
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _DailyStatsRow(
              colors: colors,
              dailyAvg: dailyAvg,
              highest: highestMonth,
              txToday: txToday,
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _SpendingAnalysisSection(
              colors: colors,
              analysisDir: _analysisDir,
              analysisIndex: _analysisIndex,
              labels: _analysisLabels,
              pageController: _analysisPageController,
              onPageChanged: _onAnalysisPageChanged,
              onChipSelected: _goAnalysis,
              onOpen: widget.onOpenTimeframe,
              pageBuilder: (pageIndex) {
                final list = _analysisExpenses(pageIndex, now);
                final spent = _sumAmounts(list);
                final slices = _categorySlices(list);
                // Tapping empty space inside a period page opens that period's
                // full editable drill-down. The pie chart / legend keep their
                // own tap handlers (they win the gesture arena for their area).
                return GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () => widget.onOpenTimeframe(pageIndex),
                  child: _AnalysisPageBody(
                    colors: colors,
                    slices: slices,
                    spent: spent,
                    periodLabel: _analysisLabels[pageIndex],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _ExpenseTrendRow(
              colors: colors,
              onShowTrend: widget.onShowTrend,
            ),
          ),
          if (tip != null) ...[
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _SmartTipCard(
                colors: colors,
                tip: tip,
                onRefreshLearnings: widget.onUpdateLearnings,
              ),
            ),
          ],
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _RecentTransactionsSection(
              colors: colors,
              recentExpenses: recent24h,
              allExpensesEmpty: widget.expenses.isEmpty,
              onAddExpense: widget.onAddExpense,
              onEdit: widget.onEditExpense,
              onDelete: widget.onDeleteExpense,
            ),
          ),
        ],
      ),
    );
  }
}

class _BalanceCardTheme {
  const _BalanceCardTheme({
    required this.gradient,
    required this.shadow,
    required this.statusLabel,
    required this.statusColor,
    required this.statusBg,
    required this.ringColor,
    required this.useLightForeground,
  });

  final Gradient gradient;
  final Color shadow;
  final String statusLabel;
  final Color statusColor;
  final Color statusBg;
  final Color ringColor;
  final bool useLightForeground;
}

class _CategorySlice {
  const _CategorySlice({
    required this.category,
    required this.total,
    required this.pct,
    required this.color,
  });

  final String category;
  final double total;
  final double pct;
  final Color color;
}

class _TotalBalanceCard extends StatelessWidget {
  const _TotalBalanceCard({
    required this.theme,
    required this.titleColor,
    required this.subtitleColor,
    required this.monthSpent,
    required this.todaySpent,
    required this.txToday,
    required this.budget,
    required this.monthSpentFormatted,
    required this.historyCount,
    required this.onSetBudget,
    required this.onShowBudgetHistory,
  });

  final _BalanceCardTheme theme;
  final Color titleColor;
  final Color subtitleColor;
  final double monthSpent;
  final double todaySpent;
  final int txToday;
  final double budget;
  final String monthSpentFormatted;
  final int historyCount;
  final VoidCallback onSetBudget;
  final VoidCallback onShowBudgetHistory;

  @override
  Widget build(BuildContext context) {
    final hasBudget = budget > 0;
    final left = hasBudget ? (budget - monthSpent) : -monthSpent;
    final over = hasBudget && monthSpent > budget;
    final barPct = hasBudget ? (monthSpent / budget).clamp(0.0, 1.0) : 0.0;

    return Container(
      decoration: BoxDecoration(
        gradient: theme.gradient,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: theme.shadow,
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "TODAY'S SPENDING",
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2,
                    color: titleColor.withValues(alpha: 0.45),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: theme.statusBg,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: theme.ringColor.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: theme.ringColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        theme.statusLabel,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                          color: theme.statusColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              formatCurrency(todaySpent),
              style: GoogleFonts.plusJakartaSans(
                fontSize: 34,
                fontWeight: FontWeight.w800,
                letterSpacing: -1,
                height: 1,
                color: titleColor,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              txToday == 0
                  ? 'no expenses yet today'
                  : '$txToday transaction${txToday == 1 ? '' : 's'} today',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                color: subtitleColor,
              ),
            ),
            const SizedBox(height: 14),
            Container(height: 1, color: titleColor.withValues(alpha: 0.08)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'BUDGET',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.2,
                          color: titleColor.withValues(alpha: 0.38),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        hasBudget ? '+${formatCurrency(budget)}' : '—',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF6EE7B7),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 1,
                  height: 28,
                  color: titleColor.withValues(alpha: 0.1),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SPENT',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.2,
                          color: titleColor.withValues(alpha: 0.38),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '-${formatCurrency(monthSpent)}',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFFFCA5A5),
                        ),
                      ),
                    ],
                  ),
                ),
                if (hasBudget) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'LEFT',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.2,
                            color: titleColor.withValues(alpha: 0.38),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          over
                              ? '−${formatCurrency(monthSpent - budget)}'
                              : formatCurrency(left),
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: over
                                ? const Color(0xFFFCA5A5)
                                : const Color(0xFF6EE7B7),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
            if (hasBudget) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: barPct,
                  minHeight: 4,
                  backgroundColor: titleColor.withValues(alpha: 0.07),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    theme.ringColor.withValues(alpha: 0.85),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Divider(height: 1, color: titleColor.withValues(alpha: 0.07)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: onSetBudget,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: titleColor.withValues(alpha: 0.09),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: titleColor.withValues(alpha: 0.14),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text('💰', style: TextStyle(fontSize: 13)),
                            const SizedBox(width: 6),
                            Text(
                              hasBudget ? 'Change Budget' : 'Set Budget',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: titleColor.withValues(alpha: 0.85),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: onShowBudgetHistory,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0x266366F1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0x4D6366F1),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            LucideIcons.history,
                            size: 14,
                            color: Color(0xFF818CF8),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            historyCount > 0
                                ? 'History ($historyCount)'
                                : 'History',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF818CF8),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DailyStatsRow extends StatelessWidget {
  const _DailyStatsRow({
    required this.colors,
    required this.dailyAvg,
    required this.highest,
    required this.txToday,
  });

  final AppColors colors;
  final double dailyAvg;
  final double highest;
  final int txToday;

  @override
  Widget build(BuildContext context) {
    Widget cell(String label, String value) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            color: colors.bg2,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: colors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                  color: colors.text4,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                value,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: colors.text,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Row(
      children: [
        cell('DAILY AVG', formatCurrency(dailyAvg)),
        const SizedBox(width: 8),
        cell('HIGHEST', formatCurrency(highest)),
        const SizedBox(width: 8),
        cell('TODAY', '$txToday'),
      ],
    );
  }
}

class _SpendingAnalysisSection extends StatelessWidget {
  const _SpendingAnalysisSection({
    required this.colors,
    required this.analysisDir,
    required this.analysisIndex,
    required this.labels,
    required this.pageController,
    required this.onPageChanged,
    required this.onChipSelected,
    required this.onOpen,
    required this.pageBuilder,
  });

  final AppColors colors;
  final int analysisDir;
  final int analysisIndex;
  final List<String> labels;
  final PageController pageController;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<int> onChipSelected;
  final ValueChanged<int> onOpen;
  final Widget Function(int pageIndex) pageBuilder;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: colors.bg2,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => onOpen(analysisIndex),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Spending Analysis',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: colors.text,
                          ),
                        ),
                      ),
                      Text(
                        'View all',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF818CF8),
                        ),
                      ),
                      const Icon(
                        LucideIcons.chevronRight,
                        size: 15,
                        color: Color(0xFF818CF8),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: colors.bg3,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: List.generate(labels.length, (i) {
                      final selected = i == analysisIndex;
                      return Expanded(
                        child: GestureDetector(
                          onTap: () => onChipSelected(i),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeOutCubic,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: selected
                                  ? const Color(0xFF6366F1)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: selected
                                  ? [
                                      BoxShadow(
                                        color: const Color(0xFF6366F1)
                                            .withValues(alpha: 0.3),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ]
                                  : null,
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              labels[i],
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 11,
                                fontWeight:
                                    selected ? FontWeight.w700 : FontWeight.w600,
                                color: selected
                                    ? Colors.white
                                    : colors.text3,
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 220,
            child: PageView.builder(
              controller: pageController,
              onPageChanged: onPageChanged,
              itemCount: labels.length,
              itemBuilder: (context, pageIndex) {
                return KeyedSubtree(
                  key: ValueKey<int>(pageIndex),
                  child: pageBuilder(pageIndex),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _AnalysisPageBody extends StatefulWidget {
  const _AnalysisPageBody({
    required this.colors,
    required this.slices,
    required this.spent,
    required this.periodLabel,
  });

  final AppColors colors;
  final List<_CategorySlice> slices;
  final double spent;
  final String periodLabel;

  @override
  State<_AnalysisPageBody> createState() => _AnalysisPageBodyState();
}

class _AnalysisPageBodyState extends State<_AnalysisPageBody> {
  int _touchedIndex = -1;

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final slices = widget.slices;
    final spent = widget.spent;
    final periodLabel = widget.periodLabel;

    if (slices.isEmpty) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('📊', style: TextStyle(fontSize: 40)),
          const SizedBox(height: 10),
          Text(
            'No expenses for ${periodLabel.toLowerCase()}',
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              color: colors.text4,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Swipe or tap a period above',
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              color: colors.text5,
            ),
          ),
        ],
      );
    }

    final touchedSlice =
        _touchedIndex >= 0 && _touchedIndex < slices.length
            ? slices[_touchedIndex]
            : null;

    return LayoutBuilder(
      builder: (context, constraints) {
        final chartSize = (constraints.maxWidth * 0.42).clamp(130.0, 160.0);
        const ringThickness = 14.0;
        final centerRadius = (chartSize / 2) - ringThickness;

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: () {
                  if (_touchedIndex != -1) {
                    setState(() => _touchedIndex = -1);
                  }
                },
                child: SizedBox(
                  width: chartSize,
                  height: chartSize,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      PieChart(
                        PieChartData(
                          pieTouchData: PieTouchData(
                            touchCallback:
                                (FlTouchEvent event, pieTouchResponse) {
                              setState(() {
                                if (!event.isInterestedForInteractions ||
                                    pieTouchResponse == null ||
                                    pieTouchResponse.touchedSection == null) {
                                  _touchedIndex = -1;
                                  return;
                                }
                                final idx = pieTouchResponse
                                    .touchedSection!
                                    .touchedSectionIndex;
                                _touchedIndex =
                                    _touchedIndex == idx ? -1 : idx;
                              });
                            },
                          ),
                          sectionsSpace: 3,
                          centerSpaceRadius: centerRadius,
                          startDegreeOffset: -90,
                          borderData: FlBorderData(show: false),
                          sections: List.generate(slices.length, (i) {
                            final s = slices[i];
                            final isTouched = i == _touchedIndex;
                            return PieChartSectionData(
                              value: s.total,
                              color: isTouched
                                  ? s.color
                                  : s.color.withValues(alpha: 0.7),
                              radius: isTouched
                                  ? ringThickness + 6
                                  : ringThickness,
                              title: '',
                              showTitle: false,
                              borderSide: isTouched
                                  ? BorderSide(
                                      color: s.color.withValues(alpha: 0.5),
                                      width: 1.5,
                                    )
                                  : BorderSide.none,
                            );
                          }),
                        ),
                      ),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        transitionBuilder: (child, animation) {
                          return FadeTransition(
                            opacity: animation,
                            child: ScaleTransition(
                              scale: Tween<double>(begin: 0.8, end: 1.0)
                                  .animate(CurvedAnimation(
                                parent: animation,
                                curve: Curves.easeOutCubic,
                              )),
                              child: child,
                            ),
                          );
                        },
                        child: touchedSlice != null
                            ? Column(
                                key: ValueKey(
                                  'cat_${touchedSlice.category}',
                                ),
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    AppColors.categoryIcons[
                                            touchedSlice.category] ??
                                        '📦',
                                    style: const TextStyle(fontSize: 20),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    formatCurrency(touchedSlice.total),
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                      color: touchedSlice.color,
                                      height: 1,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${touchedSlice.pct.round()}%',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 8,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.5,
                                      color: colors.text4,
                                    ),
                                  ),
                                ],
                              )
                            : Column(
                                key: const ValueKey('total'),
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    formatCurrency(spent),
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                      color: colors.text,
                                      height: 1,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'SPENT',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 7,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 1.2,
                                      color: colors.text4,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 4,
                runSpacing: 4,
                children: List.generate(slices.length, (i) {
                  final s = slices[i];
                  final isTouched = i == _touchedIndex;
                  final emoji =
                      AppColors.categoryIcons[s.category] ?? '📦';
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        _touchedIndex =
                            _touchedIndex == i ? -1 : i;
                      });
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOutCubic,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: isTouched
                            ? s.color.withValues(alpha: 0.15)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        border: isTouched
                            ? Border.all(
                                color: s.color.withValues(alpha: 0.3),
                              )
                            : null,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: s.color,
                              shape: BoxShape.circle,
                              boxShadow: isTouched
                                  ? [
                                      BoxShadow(
                                        color: s.color
                                            .withValues(alpha: 0.5),
                                        blurRadius: 6,
                                      ),
                                    ]
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            emoji,
                            style: const TextStyle(fontSize: 10),
                          ),
                          const SizedBox(width: 3),
                          Text(
                            s.category,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 10,
                              fontWeight: isTouched
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: isTouched
                                  ? colors.text
                                  : colors.text3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ExpenseTrendRow extends StatelessWidget {
  const _ExpenseTrendRow({
    required this.colors,
    required this.onShowTrend,
  });

  final AppColors colors;
  final VoidCallback onShowTrend;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'Expense Trend',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: colors.text,
          ),
        ),
        TextButton.icon(
          onPressed: onShowTrend,
          icon: const Icon(
            LucideIcons.chevronRight,
            size: 14,
            color: Color(0xFF818CF8),
          ),
          label: Text(
            'Details',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF818CF8),
            ),
          ),
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ],
    );
  }
}

class _SmartTipCard extends StatelessWidget {
  const _SmartTipCard({
    required this.colors,
    required this.tip,
    required this.onRefreshLearnings,
  });

  final AppColors colors;
  final String tip;
  final VoidCallback onRefreshLearnings;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0x1A4725F4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x474725F4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            margin: const EdgeInsets.only(top: 2),
            decoration: BoxDecoration(
              color: const Color(0x2E7C3AED),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0x477C3AED)),
            ),
            child: const Text('✨', style: TextStyle(fontSize: 14)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'SMART TIP',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                          color: colors.text3,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: onRefreshLearnings,
                      icon: Icon(
                        LucideIcons.refreshCw,
                        size: 16,
                        color: colors.text4,
                      ),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                      tooltip: 'Refresh insights',
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  tip,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    height: 1.55,
                    color: colors.text3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentTransactionsSection extends StatelessWidget {
  const _RecentTransactionsSection({
    required this.colors,
    required this.recentExpenses,
    required this.allExpensesEmpty,
    required this.onAddExpense,
    required this.onEdit,
    required this.onDelete,
  });

  final AppColors colors;
  final List<ExpenseData> recentExpenses;
  final bool allExpensesEmpty;
  final VoidCallback onAddExpense;
  final void Function(ExpenseData expense) onEdit;
  final void Function(String id) onDelete;

  @override
  Widget build(BuildContext context) {
    if (allExpensesEmpty) {
      return Column(
        children: [
          const SizedBox(height: 24),
          const Text('💸', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 16),
          Text(
            'No expenses yet',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: colors.text3,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Tap + to add your first expense',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              color: colors.text5,
            ),
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: onAddExpense,
            child: Text(
              'Add expense',
              style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w700,
                color: AppColors.accent,
              ),
            ),
          ),
        ],
      );
    }

    final count = recentExpenses.length;
    final total = recentExpenses.fold<double>(
      0,
      (s, e) => s + e.amount.toDouble(),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFF22C55E),
                boxShadow: [
                  BoxShadow(
                    color: Color(0x6622C55E),
                    blurRadius: 6,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Last 24 Hours',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
                color: colors.text,
              ),
            ),
            const Spacer(),
            if (count > 0) ...[
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0x1A6366F1),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: const Color(0x336366F1),
                    ),
                  ),
                  child: Text(
                    '$count txn${count != 1 ? 's' : ''} · ${formatCurrency(total)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF818CF8),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            const SizedBox(width: 16),
            Text(
              '← swipe to edit/delete',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 9,
                color: colors.text5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (recentExpenses.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
            decoration: BoxDecoration(
              color: colors.bg2,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colors.border),
            ),
            child: Column(
              children: [
                const Text('✨', style: TextStyle(fontSize: 36)),
                const SizedBox(height: 12),
                Text(
                  'All clear!',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: colors.text3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'No expenses in the last 24 hours',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: colors.text5,
                  ),
                ),
              ],
            ),
          )
        else
          ...recentExpenses.map((e) {
            final dt = safeParseDate(e.date);
            final relTime = formatRelativeTime(dt);
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 4),
                    child: Text(
                      relTime,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        color: colors.text5,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                  ExpenseItem(
                    expense: e,
                    onEdit: () => onEdit(e),
                    onDelete: () => onDelete(e.id),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }
}
