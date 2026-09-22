import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/services/expense_pace_metrics.dart';
import '../../../../core/services/expense_composition.dart';
import '../../../../core/services/telegram_logger.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/utils/expense_logged_at.dart';
import '../../../../domain/entities/expense_entities.dart';
import './budget_ring.dart';
import './expense_item.dart';
import './expense_merge_bar.dart';

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
    this.onShowTrend,
    required this.onShowBudgetHistory,
    required this.onOpenTimeframe,
    this.onOpenDay,
    this.onOpenCategory,
    this.onMergeExpenses,
    this.onMergeSelectionChanged,
    this.clock,
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

  /// Kept so existing call sites that still pass a trend callback compile.
  /// Trend lives on Insights now; Tracker does not invoke this.
  final VoidCallback? onShowTrend;
  final VoidCallback onShowBudgetHistory;

  /// Opens the full-screen drill-down for the spending-analysis period at
  /// [index] (0=Today, 1=7D, 2=1M, 3=6M, 4=All).
  final void Function(int index) onOpenTimeframe;

  /// Opens the existing timeframe screen for a single calendar day
  /// (heat-calendar tap). Does not open add-expense.
  final void Function(DateTime day)? onOpenDay;

  final void Function(int index, String category)? onOpenCategory;

  /// Long-press merge of two or more tracker rows. Null keeps the existing
  /// swipe-only row (tests and older call sites).
  final void Function(List<ExpenseData> selected)? onMergeExpenses;
  final ValueChanged<int>? onMergeSelectionChanged;

  /// Test hook. Production always uses the device clock via [DateTime.now].
  final DateTime? clock;

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
  late final ScrollController _scrollCtrl;
  int _analysisIndex = 0;
  int _analysisDir = 1;
  final Set<String> _selectedIds = <String>{};

  bool get _selecting => _selectedIds.isNotEmpty;
  @override
  void initState() {
    super.initState();
    _analysisPageController = PageController(initialPage: _analysisIndex);
    _scrollCtrl = ScrollController();
  }

  @override
  void dispose() {
    _analysisPageController.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant TrackerTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_selectedIds.isEmpty) return;
    final live = widget.expenses.map((e) => e.id).toSet();
    final next = _selectedIds.intersection(live);
    if (next.length != _selectedIds.length) {
      _selectedIds
        ..clear()
        ..addAll(next);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _emitSelection();
      });
    }
  }

  void _emitSelection() {
    widget.onMergeSelectionChanged?.call(_selectedIds.length);
  }

  void _clearSelection() {
    if (_selectedIds.isEmpty) return;
    setState(_selectedIds.clear);
    _emitSelection();
  }

  void _enterSelection(ExpenseData e) {
    if (widget.onMergeExpenses == null) return;
    setState(() {
      _selectedIds.add(e.id);
    });
    _emitSelection();
  }

  void _toggleSelection(ExpenseData e) {
    setState(() {
      if (_selectedIds.contains(e.id)) {
        _selectedIds.remove(e.id);
      } else {
        _selectedIds.add(e.id);
      }
    });
    _emitSelection();
  }

  List<ExpenseData> _selectedExpenses() {
    final byId = {for (final e in widget.expenses) e.id: e};
    return _selectedIds
        .map((id) => byId[id])
        .whereType<ExpenseData>()
        .toList(growable: false);
  }

  DateTime _parseDate(String raw) => safeParseDate(raw);

  PaceTxn _toPace(ExpenseData e) => PaceTxn(
        amount: e.amount.toDouble(),
        category: e.category,
        date: _parseDate(e.date),
        description: e.description,
      );

  /// Spending only — investments (wealth) and loan repayments (debt) are not
  /// expenses, so every total / chart / list on this tab is computed from this
  /// filtered view.
  List<ExpenseData> get _spend => widget.expenses
      .where((e) => !isNonSpendCategory(e.category))
      .toList(growable: false);

  List<ExpenseData> _expensesInCurrentMonth(DateTime now) {
    return _spend.where((e) {
      return sameCalendarMonth(_parseDate(e.date), now);
    }).toList();
  }

  double _sumAmounts(Iterable<ExpenseData> items) =>
      items.fold<double>(0, (s, e) => s + e.amount.toDouble());

  /// Filters [_spend] to the half-open range `[start, end)`. A null [end] means
  /// no upper bound (used by the "All" period, which includes future-dated
  /// entries such as a next-month bill).
  List<ExpenseData> _inRange(DateTime start, DateTime? end) {
    return _spend.where((e) {
      final d = _parseDate(e.date);
      if (d.isBefore(start)) return false;
      if (end != null && !d.isBefore(end)) return false;
      return true;
    }).toList();
  }

  List<ExpenseData> _analysisExpenses(int index, DateTime now) {
    // Upper bound for the bounded periods: start of tomorrow, so anything
    // logged today counts but future-dated entries (e.g. NM 1st) do NOT leak
    // into Today/7D — they surface in their own period and under "All".
    final tomorrow = DateTime(now.year, now.month, now.day)
        .add(const Duration(days: 1));
    final nextMonthStart = DateTime(now.year, now.month + 1, 1);
    switch (index) {
      case 0:
        return _spend
            .where((e) => sameCalendarDay(_parseDate(e.date), now))
            .toList();
      case 1:
        final start = DateTime(now.year, now.month, now.day)
            .subtract(const Duration(days: 6));
        return _inRange(start, tomorrow);
      case 2:
        // This calendar month only.
        return _inRange(DateTime(now.year, now.month, 1), nextMonthStart);
      case 3:
        // Trailing six months through the end of the current month.
        return _inRange(DateTime(now.year, now.month - 6, 1), nextMonthStart);
      default:
        return List<ExpenseData>.from(_spend);
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
    final atRisk = ExpensePaceMetrics.isAtRisk(
      spent: monthSpent,
      budget: budget,
    );

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
    if (_spend.isEmpty) return null;
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
    if (hasBudget && budgetPct >= kBudgetAtRiskRatio) {
      return 'You\'ve used ${(budgetPct * 100).round()}% of your budget. Slow down on ${top.category}!';
    }
    return 'Top category: ${top.category} at ${formatCurrency(top.total)}. You\'re doing well! 🎉';
  }

  List<_CategorySlice> _categorySlices(List<ExpenseData> scope) {
    final map = <String, double>{};
    for (final e in scope) {
      map[e.category] = (map[e.category] ?? 0) + e.amount.toDouble();
    }
    return ExpenseComposition.pieSlices(map)
        .map(
          (e) => _CategorySlice(
            category: e.category,
            total: e.total,
            pct: e.pct,
            color: e.isOther
                ? const Color(0xFF94A3B8)
                : (AppColors.categoryColors[e.category] ??
                    const Color(0xFF818CF8)),
            isOther: e.isOther,
          ),
        )
        .toList();
  }

  /// How many rows the "Most Recent Transactions" section shows before the
  /// "View all" affordance takes over.
  static const int _recentLimit = 15;

  /// The most recent transactions by their (user-selected) date, newest first.
  /// Because this sorts by the expense date — not the 24h clock — a backdated
  /// entry (yesterday / last month) or a forward-dated one (next month) shows
  /// up here immediately after logging, so nothing ever feels "untracked".
  List<ExpenseData> _mostRecentTransactions() {
    final sorted = List<ExpenseData>.from(_spend)
      ..sort((a, b) => _parseDate(b.date).compareTo(_parseDate(a.date)));
    return sorted.take(_recentLimit).toList();
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
    final now = widget.clock ?? DateTime.now();
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
    final todayExpenses = _spend
        .where((e) => sameCalendarDay(_parseDate(e.date), now))
        .toList();
    final txToday = todayExpenses.length;
    final todaySpent = _sumAmounts(todayExpenses);

    final monthSlices = _categorySlices(monthList);
    final tip = _smartTip(
      monthSpent: monthSpent,
      budget: widget.budget,
      allTimeTop: monthSlices,
    );

    final recent = _mostRecentTransactions();
    final totalTxns = _spend.length;

    final pace = ExpensePaceMetrics.monthPace(
      budget: widget.budget,
      monthSpent: monthSpent,
      today: now,
    );
    final heatDays = ExpensePaceMetrics.heatMonth(
      expenses: _spend.map(_toPace),
      month: now,
      today: now,
    );
    ExpenseComposition? composition;
    try {
      composition = ExpenseComposition.ofMonth(
        txns: widget.expenses.map(
          (e) => CompositionTxn(
            amount: e.amount.toDouble(),
            category: e.category,
            cardType: e.cardType,
            date: _parseDate(e.date),
          ),
        ),
        now: now,
      );
    } catch (e) {
      TLog.w('Tracker', 'composition failed (non-fatal)', error: e);
    }

    final scroll = SingleChildScrollView(
      key: const ValueKey('tracker-main-scroll'),
      controller: _scrollCtrl,
      padding: EdgeInsets.only(bottom: _selecting ? 200 : 120),
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
              expectedByNow: pace.hasBudget ? pace.expectedByNow : null,
              safeDaily: pace.hasBudget ? pace.safeDaily : null,
              todayFraction: pace.hasBudget ? pace.todayFraction : null,
            ),
          ),
          if (pace.hasBudget) ...[
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _PaceBanner(pace: pace, colors: colors),
            ),
          ],
          const SizedBox(height: 16),
          Center(
            child: BudgetRing(
              budget: widget.budget,
              spent: monthSpent,
              onSetBudget: widget.onSetBudget,
            ),
          ),
          if (composition != null && composition.hasAny) ...[
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _CompositionStrip(
                colors: colors,
                composition: composition,
              ),
            ),
          ],
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _HeatCalendar(
              colors: colors,
              days: heatDays,
              now: now,
              onOpenDay: widget.onOpenDay,
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
                    onOpenPeriod: () => widget.onOpenTimeframe(pageIndex),
                    onOpenCategory: (cat) =>
                        widget.onOpenCategory?.call(pageIndex, cat),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
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
              recentExpenses: recent,
              totalCount: totalTxns,
              allExpensesEmpty: _spend.isEmpty,
              onAddExpense: widget.onAddExpense,
              onEdit: widget.onEditExpense,
              onDelete: widget.onDeleteExpense,
              onViewAll: () => widget.onOpenTimeframe(4),
              now: now,
              selectionMode: _selecting,
              selectedIds: _selectedIds,
              onLongPress: widget.onMergeExpenses == null
                  ? null
                  : _enterSelection,
              onToggleSelect: _toggleSelection,
              onExitSelection: widget.onMergeExpenses == null
                  ? null
                  : _clearSelection,
            ),
          ),
        ],
      ),
    );

    final selected = _selectedExpenses();
    final total = selected.fold<double>(0, (s, e) => s + e.amount);
    return ExpenseSelectionScope(
      active: _selecting,
      onCancel: _clearSelection,
      child: Stack(
        children: [
          scroll,
          if (_selecting)
            Positioned(
              left: 12,
              right: 12,
              bottom: 20,
              child: ExpenseMergeActionBar(
                selectedCount: selected.length,
                total: total,
                onMerge: () => widget.onMergeExpenses?.call(selected),
                onCancel: _clearSelection,
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
    this.isOther = false,
  });

  final String category;
  final double total;
  final double pct;
  final Color color;
  final bool isOther;
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
    this.expectedByNow,
    this.safeDaily,
    this.todayFraction,
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
  final double? expectedByNow;
  final double? safeDaily;
  final double? todayFraction;

  @override
  Widget build(BuildContext context) {
    final hasBudget = budget > 0;
    final left = hasBudget ? (budget - monthSpent) : -monthSpent;
    final over = hasBudget && monthSpent > budget;
    final barPct = hasBudget ? (monthSpent / budget).clamp(0.0, 1.0) : 0.0;
    // The balance card uses a light tinted gradient in white theme, where the
    // pastel green/salmon figures wash out — use deeper shades there so the
    // amounts stay legible. Dark theme keeps the original light tints.
    final isDark = Theme.of(context).extension<AppColors>()!.isDark;
    final positiveColor =
        isDark ? const Color(0xFF6EE7B7) : const Color(0xFF059669);
    final negativeColor =
        isDark ? const Color(0xFFFCA5A5) : const Color(0xFFDC2626);

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
                          color: positiveColor,
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
                          color: negativeColor,
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
                            color: over ? negativeColor : positiveColor,
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
              LayoutBuilder(
                builder: (context, constraints) {
                  final frac = todayFraction ?? 0;
                  final tickLeft = (constraints.maxWidth * frac)
                      .clamp(0.0, math.max(0.0, constraints.maxWidth - 2))
                      .toDouble();
                  return SizedBox(
                    height: 8,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned(
                          left: 0,
                          right: 0,
                          top: 2,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: barPct,
                              minHeight: 4,
                              backgroundColor:
                                  titleColor.withValues(alpha: 0.07),
                              valueColor: AlwaysStoppedAnimation<Color>(
                                theme.ringColor.withValues(alpha: 0.85),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: tickLeft,
                          top: 0,
                          child: Container(
                            width: 2,
                            height: 8,
                            decoration: BoxDecoration(
                              color: titleColor.withValues(alpha: 0.75),
                              borderRadius: BorderRadius.circular(1),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
            if (expectedByNow != null && safeDaily != null) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  Text(
                    'Expected ${formatCurrency(expectedByNow!)}',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: titleColor.withValues(alpha: 0.55),
                    ),
                  ),
                  Text(
                    'Safe ${formatCurrency(safeDaily!)}/day',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: titleColor.withValues(alpha: 0.55),
                    ),
                  ),
                ],
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
    required this.onOpenPeriod,
    this.onOpenCategory,
  });

  final AppColors colors;
  final List<_CategorySlice> slices;
  final double spent;
  final String periodLabel;
  final VoidCallback onOpenPeriod;
  final void Function(String category)? onOpenCategory;

  @override
  State<_AnalysisPageBody> createState() => _AnalysisPageBodyState();
}

class _AnalysisPageBodyState extends State<_AnalysisPageBody> {
  int _touchedIndex = -1;

  @override
  void didUpdateWidget(covariant _AnalysisPageBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldCats = oldWidget.slices.map((s) => s.category).join('|');
    final newCats = widget.slices.map((s) => s.category).join('|');
    if (oldCats != newCats) {
      _touchedIndex = -1;
    }
  }

  void _selectOrDrill(int idx) {
    if (idx < 0 || idx >= widget.slices.length) return;
    if (_touchedIndex == idx) {
      _drill(widget.slices[idx]);
      return;
    }
    setState(() => _touchedIndex = idx);
  }

  void _drill(_CategorySlice slice) {
    HapticFeedback.selectionClick();
    if (slice.isOther || widget.onOpenCategory == null) {
      widget.onOpenPeriod();
      return;
    }
    widget.onOpenCategory!(slice.category);
  }

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
                  final slice =
                      _touchedIndex >= 0 && _touchedIndex < slices.length
                          ? slices[_touchedIndex]
                          : null;
                  if (slice != null) {
                    _drill(slice);
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
                              if (event is! FlTapUpEvent) return;
                              final idx = pieTouchResponse
                                  ?.touchedSection?.touchedSectionIndex;
                              if (idx == null || idx < 0) return;
                              _selectOrDrill(idx);
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
                    onTap: () => _selectOrDrill(i),
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

class _CompositionStrip extends StatelessWidget {
  const _CompositionStrip({
    required this.colors,
    required this.composition,
  });

  final AppColors colors;
  final ExpenseComposition composition;

  @override
  Widget build(BuildContext context) {
    final mom = composition.momIndex;
    Widget chip(String label, double amount, Color accent) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
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
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: colors.text4,
                ),
              ),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  formatCurrency(amount),
                  maxLines: 1,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: accent,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            chip('CASH', composition.cash, const Color(0xFF34D399)),
            const SizedBox(width: 8),
            chip('DEBIT', composition.debit, const Color(0xFF60A5FA)),
            const SizedBox(width: 8),
            chip('CREDIT', composition.credit, const Color(0xFFA78BFA)),
          ],
        ),
        if (composition.moved > 0 ||
            mom != null ||
            composition.completedMonthAverage != null) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 4,
            children: [
              if (composition.moved > 0)
                Text(
                  'Moved ${formatCurrency(composition.moved)} to wealth/debt',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: colors.text3,
                  ),
                ),
              if (mom != null)
                Text(
                  'MoM ${mom.round()}',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: mom > 100
                        ? const Color(0xFFF87171)
                        : mom < 100
                            ? const Color(0xFF34D399)
                            : colors.text3,
                  ),
                ),
              if (composition.completedMonthAverage != null)
                Text(
                  'Avg month ${formatCurrency(composition.completedMonthAverage!)}',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: colors.text3,
                  ),
                ),
            ],
          ),
        ],
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
    required this.totalCount,
    required this.allExpensesEmpty,
    required this.onAddExpense,
    required this.onEdit,
    required this.onDelete,
    required this.onViewAll,
    required this.now,
    this.selectionMode = false,
    this.selectedIds = const <String>{},
    this.onLongPress,
    this.onToggleSelect,
    this.onExitSelection,
  });

  final AppColors colors;
  final List<ExpenseData> recentExpenses;

  /// Total number of (spending) transactions across all time — drives the
  /// header badge and whether the "View all" footer is shown.
  final int totalCount;
  final bool allExpensesEmpty;
  final VoidCallback onAddExpense;
  final void Function(ExpenseData expense) onEdit;
  final void Function(String id) onDelete;
  final VoidCallback onViewAll;
  final DateTime now;
  final bool selectionMode;
  final Set<String> selectedIds;
  final void Function(ExpenseData expense)? onLongPress;
  final void Function(ExpenseData expense)? onToggleSelect;
  final VoidCallback? onExitSelection;

  /// Calendar-day grouping key so we render one date header per day.
  String _dayKey(DateTime d) {
    final l = expenseLocal(d);
    return '${l.year}-${l.month.toString().padLeft(2, '0')}-${l.day.toString().padLeft(2, '0')}';
  }

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

    final hasMore = totalCount > recentExpenses.length;

    // Build a grouped list: one small date header per calendar day, then the
    // transactions for that day. Newest day first (list is already sorted).
    final children = <Widget>[];
    String? lastKey;
    for (final e in recentExpenses) {
      final dt = safeParseDate(e.date);
      final key = _dayKey(dt);
      if (key != lastKey) {
        children.add(
          Padding(
            padding: EdgeInsets.only(left: 4, top: lastKey == null ? 0 : 8, bottom: 6),
            child: Text(
              formatCalendarDayLabel(dt, now: now).toUpperCase(),
              style: GoogleFonts.plusJakartaSans(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: colors.text5,
                letterSpacing: 0.8,
              ),
            ),
          ),
        );
        lastKey = key;
      }
      children.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: ExpenseItem(
            key: ValueKey('expense-row-${e.id}'),
            expense: e,
            onEdit: () => onEdit(e),
            onDelete: () => onDelete(e.id),
            selectionMode: selectionMode,
            selected: selectedIds.contains(e.id),
            onLongPress:
                onLongPress == null ? null : () => onLongPress!(e),
            onToggleSelect:
                onToggleSelect == null ? null : () => onToggleSelect!(e),
            onExitSelection: onLongPress == null ? null : onExitSelection,
          ),
        ),
      );
    }

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
            Expanded(
              child: Text(
                'Most Recent Transactions',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                  color: colors.text,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
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
                '$totalCount txn${totalCount != 1 ? 's' : ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF818CF8),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.only(left: 16),
          child: Text(
            '← ${selectionMode ? 'swipe back to exit · tap to select' : 'swipe to edit / delete'}',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 9,
              color: colors.text5,
            ),
          ),
        ),
        const SizedBox(height: 12),
        ...children,
        if (hasMore) ...[
          const SizedBox(height: 4),
          Material(
            color: colors.bg2,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: onViewAll,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 13),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: colors.border),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'View all $totalCount transactions',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF818CF8),
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      LucideIcons.arrowRight,
                      size: 14,
                      color: Color(0xFF818CF8),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _PaceBanner extends StatelessWidget {
  const _PaceBanner({required this.pace, required this.colors});

  final MonthPace pace;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    final (label, color, copy) = switch (pace.status) {
      PaceStatus.overPlan => (
          'OVER PLAN',
          const Color(0xFFEF4444),
          '${formatCurrency(pace.monthSpent - pace.budget)} over the monthly budget',
        ),
      PaceStatus.aheadOfPace => (
          'AHEAD OF PACE',
          const Color(0xFFF59E0B),
          '${formatCurrency(pace.monthSpent - pace.expectedByNow)} above expected-by-now',
        ),
      _ => (
          'ON TRACK',
          const Color(0xFF22C55E),
          'Spending is in line with ${formatCurrency(pace.expectedByNow)} expected by now',
        ),
    };

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 240),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeOutCubic,
      child: Container(
        key: ValueKey(pace.status),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: colors.isDark ? 0.16 : 0.10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Container(
                width: 8,
                height: 8,
                decoration:
                    BoxDecoration(color: color, shape: BoxShape.circle),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                color: color,
                height: 1.5,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    copy,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                      color: colors.text3,
                    ),
                  ),
                  if (pace.remainingSentence.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      pace.remainingSentence,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                        color: colors.text4,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeatCalendar extends StatelessWidget {
  const _HeatCalendar({
    required this.colors,
    required this.days,
    required this.now,
    required this.onOpenDay,
  });

  final AppColors colors;
  final List<HeatDay> days;
  final DateTime now;
  final void Function(DateTime day)? onOpenDay;

  static const _dow = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

  @override
  Widget build(BuildContext context) {
    if (days.isEmpty) return const SizedBox.shrink();
    final leading = DateTime(now.year, now.month, 1).weekday % 7;
    final monthTitle =
        '${_monthName(now.month)} ${now.year}';
    const hot = Color(0xFFEF4444);

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: BoxDecoration(
        color: colors.bg2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Heat · $monthTitle',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: colors.text,
                  ),
                ),
              ),
              Text(
                'Tap a day',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: colors.text4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final d in _dow)
                Expanded(
                  child: Center(
                    child: Text(
                      d,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: colors.text4,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          LayoutBuilder(
            builder: (context, constraints) {
              final cellW = (constraints.maxWidth - 18) / 7;
              final cellH = math.min(math.max(cellW, 40.0), 46.0);
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: leading + days.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  mainAxisSpacing: 3,
                  crossAxisSpacing: 3,
                  mainAxisExtent: cellH,
                ),
                itemBuilder: (context, i) {
                  if (i < leading) {
                    return const SizedBox.shrink();
                  }
                  final day = days[i - leading];
                  final bg = day.isFuture
                      ? colors.bg3.withValues(alpha: colors.bg3.a * 0.45)
                      : Color.lerp(
                          colors.bg3,
                          hot,
                          day.intensity.clamp(0.0, 1.0),
                        )!;
                  final tappable = !day.isFuture && onOpenDay != null;
                  final tip = day.isFuture
                      ? 'Upcoming'
                      : day.spent <= 0
                          ? 'No spend'
                          : formatCurrency(day.spent);
                  return Tooltip(
                    message: tip,
                    child: Material(
                      key: ValueKey('heat-day-${day.date.day}'),
                      color: bg,
                      borderRadius: BorderRadius.circular(8),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: tappable
                            ? () {
                                HapticFeedback.selectionClick();
                                onOpenDay!(day.date);
                              }
                            : null,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: day.isToday
                                ? Border.all(
                                    color: AppColors.accent,
                                    width: 1.4,
                                  )
                                : null,
                          ),
                          child: SizedBox.expand(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 1,
                                vertical: 2,
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    '${day.date.day}',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 10,
                                      fontWeight: day.isToday
                                          ? FontWeight.w800
                                          : FontWeight.w600,
                                      height: 1.05,
                                      color: day.isFuture
                                          ? colors.text5
                                          : day.intensity > 0.55
                                              ? Colors.white
                                              : colors.text,
                                    ),
                                  ),
                                  if (!day.isFuture && day.spent > 0)
                                    FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        formatCompactRupee(day.spent),
                                        maxLines: 1,
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 8,
                                          fontWeight: FontWeight.w700,
                                          height: 1.05,
                                          color: day.intensity > 0.55
                                              ? Colors.white.withValues(
                                                  alpha: 0.92,
                                                )
                                              : colors.text3,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                'Less',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: colors.text4,
                ),
              ),
              const SizedBox(width: 6),
              for (final t in const [0.0, 0.25, 0.5, 0.75, 1.0]) ...[
                Container(
                  width: 12,
                  height: 8,
                  margin: const EdgeInsets.only(right: 3),
                  decoration: BoxDecoration(
                    color: Color.lerp(colors.bg3, hot, t),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ],
              Text(
                'More',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: colors.text4,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _monthName(int month) {
    const names = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return names[month - 1];
  }
}
