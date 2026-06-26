import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../domain/entities/expense_entities.dart';

/// Full-screen budget history (`BudgetHistoryModal.tsx`).
void showBudgetHistoryModal(
  BuildContext context, {
  required List<BudgetHistoryEntry> budgetHistory,
  required List<Expense> expenses,
  required double currentBudget,
  required VoidCallback onClose,
}) {
  Navigator.of(context).push<void>(
    PageRouteBuilder<void>(
      pageBuilder: (_, __, ___) => BudgetHistoryModal(
        budgetHistory: budgetHistory,
        expenses: expenses,
        currentBudget: currentBudget,
        onClose: onClose,
      ),
      transitionsBuilder: (_, animation, __, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        );
      },
    ),
  );
}

class BudgetHistoryModal extends StatelessWidget {
  const BudgetHistoryModal({
    super.key,
    required this.budgetHistory,
    required this.expenses,
    required this.currentBudget,
    required this.onClose,
  });

  final List<BudgetHistoryEntry> budgetHistory;
  final List<Expense> expenses;
  final double currentBudget;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final textTheme = GoogleFonts.plusJakartaSansTextTheme(
      Theme.of(context).textTheme,
    );
    final data = _computeBudgetHistoryData(
      budgetHistory: budgetHistory,
      expenses: expenses,
      currentBudget: currentBudget,
    );
    final hasData = budgetHistory.isNotEmpty;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) onClose();
      },
      child: Scaffold(
        backgroundColor: colors.bg,
        body: SafeArea(
          child: Column(
            children: [
              _Header(
                colors: colors,
                textTheme: textTheme,
                onClose: () => Navigator.of(context).pop(),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 48),
                  child: hasData
                      ? _BudgetHistoryBody(
                          data: data,
                          colors: colors,
                          textTheme: textTheme,
                        )
                      : _EmptyState(colors: colors),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.colors,
    required this.textTheme,
    required this.onClose,
  });

  final AppColors colors;
  final TextTheme textTheme;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: colors.headerBg,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Budget History',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: colors.text,
                    letterSpacing: -0.2,
                  ),
                ),
                Text(
                  'MONTHLY OVERVIEW',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: colors.text5,
                    letterSpacing: 1.2,
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

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.colors,
  });

  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    final hintBorder = colors.isDark
        ? const Color(0x477C3AED)
        : const Color(0x337C3AED);
    final hintBg = colors.isDark
        ? const Color(0x1F7C3AED)
        : const Color(0x147C3AED);

    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 96, 32, 32),
      child: Column(
        children: [
          Container(
            width: 96,
            height: 96,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: const LinearGradient(
                colors: [
                  Color(0x337C3AED),
                  Color(0x1A6366F1),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(color: hintBorder),
            ),
            child: const Text('📅', style: TextStyle(fontSize: 44)),
          ),
          const SizedBox(height: 24),
          Text(
            'No Budget History Yet',
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: colors.text3,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Every time you set or update your budget,\nit gets recorded here automatically.',
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              height: 1.7,
              color: colors.text5,
            ),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: hintBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: hintBorder),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('💰'),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'Tap "Set Budget" on the balance card to start',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFFC4B5FD),
                    ),
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

class _BudgetHistoryBody extends StatelessWidget {
  const _BudgetHistoryBody({
    required this.data,
    required this.colors,
    required this.textTheme,
  });

  final _BudgetHistoryData data;
  final AppColors colors;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    final remaining = data.stats.totalBudgetAdded - data.stats.totalSpent;
    final isOver = remaining < 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF7C3AED).withValues(alpha: 0.15),
                  const Color(0xFF6366F1).withValues(alpha: 0.08),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: const Color(0xFF7C3AED).withValues(alpha: 0.25),
              ),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'TOTAL BUDGET ADDED',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: colors.text5,
                              letterSpacing: 1.0,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            formatCurrency(data.stats.totalBudgetAdded),
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFFA78BFA),
                              height: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 40,
                      color: colors.border,
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(left: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'TOTAL SPENT',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: colors.text5,
                                letterSpacing: 1.0,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              formatCurrency(data.stats.totalSpent),
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: isOver
                                    ? const Color(0xFFEF4444)
                                    : const Color(0xFF34D399),
                                height: 1,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: isOver
                        ? const Color(0x1AEF4444)
                        : const Color(0x1A22C55E),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isOver
                          ? const Color(0x40EF4444)
                          : const Color(0x4022C55E),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        isOver ? '⚠️' : '✨',
                        style: const TextStyle(fontSize: 13),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isOver
                            ? 'Overspent by ${formatCurrency(remaining.abs())} across all months'
                            : '${formatCurrency(remaining)} remaining across all months',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: isOver
                              ? const Color(0xFFFCA5A5)
                              : const Color(0xFF86EFAC),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: _StatCard(
                  icon: '📅',
                  label: 'MONTHS',
                  value: '${data.stats.totalMonths}',
                  valueColor: const Color(0xFF818CF8),
                  colors: colors,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _StatCard(
                  icon: '💰',
                  label: 'AVG BUDGET',
                  value: formatCurrency(data.stats.avgBudget),
                  valueColor: const Color(0xFF34D399),
                  colors: colors,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _StatCard(
                  icon: data.stats.drainedCount > 0 ? '🔥' : '✅',
                  label: 'DRAINED',
                  value: '${data.stats.drainedCount}',
                  valueColor: data.stats.drainedCount > 0
                      ? const Color(0xFFEF4444)
                      : const Color(0xFF22C55E),
                  colors: colors,
                ),
              ),
            ],
          ),
        ),
        if (data.trendSpots.length >= 2)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: _BudgetEvolutionChart(
              spots: data.trendSpots,
              labels: data.trendLabels,
              colors: colors,
            ),
          ),
        if (data.spendingBars.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: _SpendingVsBudgetChart(
              rows: data.spendingBars,
              colors: colors,
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
          child: _ChangesTimeline(
            changes: data.changes,
            colors: colors,
          ),
        ),
        if (data.monthlyPerf.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
            child: _MonthlyPerformanceSection(
              items: data.monthlyPerf,
              colors: colors,
            ),
          ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.valueColor,
    required this.colors,
  });

  final String icon;
  final String label;
  final String value;
  final Color valueColor;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.bg2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        children: [
          Text(icon, style: const TextStyle(fontSize: 22)),
          const SizedBox(height: 4),
          Text(
            value,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: valueColor,
              height: 1,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 8,
              fontWeight: FontWeight.w600,
              color: colors.text5,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _BudgetEvolutionChart extends StatelessWidget {
  const _BudgetEvolutionChart({
    required this.spots,
    required this.labels,
    required this.colors,
  });

  final List<FlSpot> spots;
  final List<String> labels;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    final maxY = spots.isEmpty
        ? 1.0
        : spots.map((s) => s.y).reduce((a, b) => a > b ? a : b) * 1.15;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.isDark
            ? const Color(0x08FFFFFF)
            : colors.bg2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colors.isDark
              ? const Color(0x12FFFFFF)
              : colors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Budget Evolution',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: colors.text3,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0x267C3AED),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'TREND',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFFA78BFA),
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 110,
            child: LineChart(
              LineChartData(
                minY: 0,
                maxY: maxY > 0 ? maxY : 1,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: colors.border.withValues(alpha: 0.5),
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 22,
                      interval: 1,
                      getTitlesWidget: (v, _) {
                        final i = v.round();
                        if (i < 0 || i >= labels.length) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            labels[i],
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 9,
                              color: colors.text4,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    color: const Color(0xFF7C3AED),
                    barWidth: 2.5,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (s, p, bar, i) => FlDotCirclePainter(
                        radius: 3,
                        color: const Color(0xFFA78BFA),
                        strokeWidth: 0,
                      ),
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: const LinearGradient(
                        colors: [
                          Color(0x807C3AED),
                          Color(0x057C3AED),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ],
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipItems: (touched) {
                      return touched.map((t) {
                        final i = t.x.round().clamp(0, labels.length - 1);
                        return LineTooltipItem(
                          '${labels[i]}\n${formatCurrency(t.y)}',
                          GoogleFonts.plusJakartaSans(
                            color: const Color(0xFFC4B5FD),
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
                          ),
                        );
                      }).toList();
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SpendingVsBudgetChart extends StatelessWidget {
  const _SpendingVsBudgetChart({
    required this.rows,
    required this.colors,
  });

  final List<_SpendingBarRow> rows;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    final maxY = rows
        .map((r) => math.max(r.budget, r.spent))
        .reduce((a, b) => a > b ? a : b);
    final top = maxY > 0 ? maxY * 1.12 : 1.0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.isDark
            ? const Color(0x08FFFFFF)
            : colors.bg2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colors.isDark
              ? const Color(0x12FFFFFF)
              : colors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Spending vs Budget',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: colors.text3,
                ),
              ),
              Row(
                children: [
                  _LegendDot(
                    color: AppColors.accent.withValues(alpha: 0.9),
                    label: 'Budget',
                    colors: colors,
                  ),
                  const SizedBox(width: 12),
                  _LegendDot(
                    color: const Color(0xFF22C55E),
                    label: 'Spent',
                    colors: colors,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Spent bars use your top category color per month',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 9,
              color: colors.text5,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 140,
            child: BarChart(
              BarChartData(
                maxY: top,
                alignment: BarChartAlignment.spaceAround,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: colors.border.withValues(alpha: 0.4),
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 24,
                      getTitlesWidget: (v, _) {
                        final i = v.toInt();
                        if (i < 0 || i >= rows.length) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            rows[i].name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 9,
                              color: colors.text4,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                barGroups: [
                  for (var i = 0; i < rows.length; i++)
                    BarChartGroupData(
                      x: i,
                      barsSpace: 6,
                      barRods: [
                        BarChartRodData(
                          toY: rows[i].budget,
                          width: 10,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(3),
                          ),
                          color: AppColors.accent,
                        ),
                        BarChartRodData(
                          toY: rows[i].spent,
                          width: 10,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(3),
                          ),
                          color: rows[i].spentColor,
                        ),
                      ],
                    ),
                ],
                barTouchData: BarTouchData(
                  enabled: true,
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      final row = rows[group.x.toInt()];
                      final isBudget = rodIndex == 0;
                      return BarTooltipItem(
                        isBudget
                            ? 'Budget\n${formatCurrency(row.budget)}'
                            : 'Spent\n${formatCurrency(row.spent)}',
                        GoogleFonts.plusJakartaSans(
                          color: colors.text,
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({
    required this.color,
    required this.label,
    required this.colors,
  });

  final Color color;
  final String label;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 9,
            color: colors.text5,
          ),
        ),
      ],
    );
  }
}

class _ChangesTimeline extends StatelessWidget {
  const _ChangesTimeline({
    required this.changes,
    required this.colors,
  });

  final List<_ChangeRow> changes;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Budget Changes',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: colors.text,
          ),
        ),
        const SizedBox(height: 14),
        Stack(
          children: [
            Positioned(
              left: 11,
              top: 16,
              bottom: 16,
              child: Container(
                width: 1,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Color(0x807C3AED),
                      Color(0x0D7C3AED),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
            ),
            Column(
              children: [
                for (var i = 0; i < changes.length; i++)
                  _ChangeTile(
                    row: changes[i],
                    colors: colors,
                    isLast: i == changes.length - 1,
                  ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

class _ChangeTile extends StatelessWidget {
  const _ChangeTile({
    required this.row,
    required this.colors,
    required this.isLast,
  });

  final _ChangeRow row;
  final AppColors colors;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final isUp = row.delta != null && row.delta! > 0;
    final isDown = row.delta != null && row.delta! < 0;
    final dotColor = row.isFirst
        ? const Color(0xFF818CF8)
        : isUp
            ? const Color(0xFF22C55E)
            : isDown
                ? const Color(0xFFEF4444)
                : const Color(0xFF6B7280);

    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            margin: const EdgeInsets.only(top: 2),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: dotColor.withValues(alpha: 0.1),
              border: Border.all(color: dotColor, width: 2),
            ),
            child: row.isFirst
                ? const Text('🌟', style: TextStyle(fontSize: 10))
                : Icon(
                    isUp
                        ? LucideIcons.trendingUp
                        : isDown
                            ? LucideIcons.trendingDown
                            : LucideIcons.minus,
                    size: 10,
                    color: dotColor,
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: colors.bg2,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: colors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        formatCurrency(row.amount),
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: colors.text,
                        ),
                      ),
                      if (row.isFirst)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0x336366F1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'INITIAL BUDGET',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF818CF8),
                              letterSpacing: 0.8,
                            ),
                          ),
                        )
                      else
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: isUp
                                ? const Color(0x1F22C55E)
                                : const Color(0x1FEF4444),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${isUp ? '+' : ''}${row.deltaPct}%',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: isUp
                                  ? const Color(0xFF22C55E)
                                  : const Color(0xFFEF4444),
                              letterSpacing: 0.6,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    row.displayDate,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      color: colors.text5,
                    ),
                  ),
                  if (row.delta != null &&
                      row.delta != 0 &&
                      !row.isFirst) ...[
                    const SizedBox(height: 3),
                    Text(
                      isUp
                          ? '↑ Increased by ${formatCurrency(row.delta!.abs())}'
                          : '↓ Decreased by ${formatCurrency(row.delta!.abs())}',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        color: isUp
                            ? const Color(0xFF86EFAC)
                            : const Color(0xFFFCA5A5),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthlyPerformanceSection extends StatelessWidget {
  const _MonthlyPerformanceSection({
    required this.items,
    required this.colors,
  });

  final List<_MonthlyPerfRow> items;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Monthly Performance',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: colors.text,
          ),
        ),
        const SizedBox(height: 14),
        for (final m in items) _MonthlyPerfCard(row: m, colors: colors),
      ],
    );
  }
}

class _MonthlyPerfCard extends StatelessWidget {
  const _MonthlyPerfCard({
    required this.row,
    required this.colors,
  });

  final _MonthlyPerfRow row;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    final cfg = _statusConfig(row.status);
    final isDrained = row.status == _PerfStatus.drained;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: BoxDecoration(
          gradient: isDrained
              ? const LinearGradient(
                  colors: [
                    Color(0x1AEF4444),
                    Color(0x0AEF4444),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: isDrained ? null : cfg.dimBg,
          borderRadius: BorderRadius.circular(16),
          border: Border(
            left: BorderSide(
              color: isDrained ? const Color(0xFFEF4444) : cfg.border,
              width: isDrained ? 4 : 1,
            ),
            top: BorderSide(color: cfg.border),
            right: BorderSide(color: cfg.border),
            bottom: BorderSide(color: cfg.border),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      if (isDrained) ...[
                        const Text('🔥', style: TextStyle(fontSize: 16)),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        row.label,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: colors.text,
                        ),
                      ),
                      if (row.isCurrent) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0x336366F1),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            'CURRENT',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF818CF8),
                              letterSpacing: 0.6,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: cfg.dimBg,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: cfg.border),
                    ),
                    child: Text(
                      cfg.label,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: cfg.color,
                        letterSpacing: 0.7,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: row.pct.clamp(0.0, 1.0),
                  minHeight: 6,
                  backgroundColor: colors.bg3,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    isDrained ? const Color(0xFFEF4444) : cfg.color,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${formatCurrency(row.spent)} spent',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colors.text3,
                    ),
                  ),
                  if (row.budget > 0)
                    Text(
                      'of ${formatCurrency(row.budget)} · ${(row.rawPct * 100).round()}%',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        color: colors.text5,
                      ),
                    ),
                ],
              ),
              if (isDrained && row.overspent > 0) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0x2EEF4444),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0x59EF4444),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('⚠️', style: TextStyle(fontSize: 13)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Overspent by ${formatCurrency(row.overspent)}',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFFFCA5A5),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Budget completely drained this period',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 10,
                                color: colors.text5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Data model (mirrors `BudgetHistoryModal.tsx` useMemo) ────────────────

enum _PerfStatus { healthy, warning, danger, drained, empty }

class _StatusStyle {
  const _StatusStyle({
    required this.color,
    required this.dimBg,
    required this.border,
    required this.label,
  });

  final Color color;
  final Color dimBg;
  final Color border;
  final String label;
}

_StatusStyle _statusConfig(_PerfStatus s) {
  switch (s) {
    case _PerfStatus.healthy:
      return const _StatusStyle(
        color: Color(0xFF22C55E),
        dimBg: Color(0x1422C55E),
        border: Color(0x3322C55E),
        label: 'ON TRACK',
      );
    case _PerfStatus.warning:
      return const _StatusStyle(
        color: Color(0xFFF59E0B),
        dimBg: Color(0x17F59E0B),
        border: Color(0x40F59E0B),
        label: 'AT RISK',
      );
    case _PerfStatus.danger:
      return const _StatusStyle(
        color: Color(0xFFF97316),
        dimBg: Color(0x17F97316),
        border: Color(0x40F97316),
        label: 'HIGH USAGE',
      );
    case _PerfStatus.drained:
      return const _StatusStyle(
        color: Color(0xFFEF4444),
        dimBg: Color(0x1AEF4444),
        border: Color(0x4DEF4444),
        label: 'DRAINED 🔥',
      );
    case _PerfStatus.empty:
      return const _StatusStyle(
        color: Color(0xFF6366F1),
        dimBg: Color(0x126366F1),
        border: Color(0x2E6366F1),
        label: 'NO DATA',
      );
  }
}

class _BudgetStats {
  const _BudgetStats({
    required this.totalMonths,
    required this.drainedCount,
    required this.avgBudget,
    required this.totalBudgetAdded,
    required this.totalSpent,
  });

  final int totalMonths;
  final int drainedCount;
  final int avgBudget;
  final double totalBudgetAdded;
  final double totalSpent;
}

class _ChangeRow {
  const _ChangeRow({
    required this.id,
    required this.amount,
    required this.setAt,
    required this.delta,
    required this.deltaPct,
    required this.isFirst,
    required this.displayDate,
  });

  final String id;
  final double amount;
  final String setAt;
  final double? delta;
  final int? deltaPct;
  final bool isFirst;
  final String displayDate;
}

class _MonthlyPerfRow {
  const _MonthlyPerfRow({
    required this.month,
    required this.label,
    required this.budget,
    required this.spent,
    required this.pct,
    required this.rawPct,
    required this.status,
    required this.isCurrent,
    required this.overspent,
  });

  final String month;
  final String label;
  final double budget;
  final double spent;
  final double pct;
  final double rawPct;
  final _PerfStatus status;
  final bool isCurrent;
  final double overspent;
}

class _SpendingBarRow {
  const _SpendingBarRow({
    required this.name,
    required this.budget,
    required this.spent,
    required this.spentColor,
  });

  final String name;
  final double budget;
  final double spent;
  final Color spentColor;
}

class _BudgetHistoryData {
  const _BudgetHistoryData({
    required this.monthlyPerf,
    required this.changes,
    required this.trendSpots,
    required this.trendLabels,
    required this.stats,
    required this.spendingBars,
  });

  final List<_MonthlyPerfRow> monthlyPerf;
  final List<_ChangeRow> changes;
  final List<FlSpot> trendSpots;
  final List<String> trendLabels;
  final _BudgetStats stats;
  final List<_SpendingBarRow> spendingBars;
}

String _monthKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}';

String _fmtMonthLabel(String monthKey) {
  final p = monthKey.split('-');
  final y = int.parse(p[0]);
  final m = int.parse(p[1]);
  final name = DateFormat.MMM('en').format(DateTime(y, m));
  return "$name '${y.toString().substring(2)}";
}

Color _dominantCategoryColor(String monthKey, List<Expense> expenses) {
  final p = monthKey.split('-');
  final y = int.parse(p[0]);
  final mo = int.parse(p[1]);
  final start = DateTime(y, mo, 1);
  final end = DateTime(y, mo + 1, 0, 23, 59, 59, 999);
  final byCat = <String, double>{};
  for (final e in expenses) {
    if (isInvestmentCategory(e.category)) continue;
    final d = safeParseDate(e.date);
    if (!d.isBefore(start) && !d.isAfter(end)) {
      byCat[e.category] = (byCat[e.category] ?? 0) + e.amount;
    }
  }
  if (byCat.isEmpty) {
    return AppColors.categoryOthers;
  }
  final top = byCat.entries.reduce((a, b) => a.value >= b.value ? a : b);
  return AppColors.categoryColors[top.key] ?? AppColors.categoryOthers;
}

_BudgetHistoryData _computeBudgetHistoryData({
  required List<BudgetHistoryEntry> budgetHistory,
  required List<Expense> expenses,
  required double currentBudget,
}) {
  final now = DateTime.now();
  final currentMonthKey = _monthKey(now);

  final monthSet = <String>{};
  for (final e in expenses) {
    monthSet.add(_monthKey(safeParseDate(e.date)));
  }
  for (final h in budgetHistory) {
    monthSet.add(_monthKey(safeParseDate(h.setAt)));
  }
  if (currentBudget > 0 || budgetHistory.isNotEmpty) {
    monthSet.add(currentMonthKey);
  }
  final months = monthSet.toList()..sort((a, b) => b.compareTo(a));

  final sorted = List<BudgetHistoryEntry>.from(budgetHistory)
    ..sort(
      (a, b) => safeParseDate(b.setAt).compareTo(safeParseDate(a.setAt)),
    );

  double getBudget(String monthKey) {
    final p = monthKey.split('-');
    final y = int.parse(p[0]);
    final m = int.parse(p[1]);
    final endOfMonth = DateTime(y, m + 1, 0, 23, 59, 59);
    BudgetHistoryEntry? entry;
    for (final h in sorted) {
      if (!safeParseDate(h.setAt).isAfter(endOfMonth)) {
        entry = h;
        break;
      }
    }
    return entry?.amount ?? (currentBudget > 0 ? currentBudget : 0);
  }

  double getSpent(String monthKey) {
    final p = monthKey.split('-');
    final y = int.parse(p[0]);
    final m = int.parse(p[1]);
    final start = DateTime(y, m, 1);
    final end = DateTime(y, m + 1, 0, 23, 59, 59, 999);
    return expenses
        .where((e) {
          final d = safeParseDate(e.date);
          return !isInvestmentCategory(e.category) &&
              !d.isBefore(start) &&
              !d.isAfter(end);
        })
        .fold<double>(0, (s, e) => s + e.amount);
  }

  final monthlyPerf = <_MonthlyPerfRow>[];
  for (final month in months) {
    final budget = getBudget(month);
    final spent = getSpent(month);
    final rawPct = budget > 0 ? spent / budget : 0.0;
    final pct = rawPct.clamp(0.0, 1.0);
    _PerfStatus status;
    if (budget == 0) {
      status = _PerfStatus.empty;
    } else if (rawPct >= 1) {
      status = _PerfStatus.drained;
    } else if (rawPct > 0.85) {
      status = _PerfStatus.danger;
    } else if (rawPct > 0.6) {
      status = _PerfStatus.warning;
    } else {
      status = _PerfStatus.healthy;
    }
    monthlyPerf.add(
      _MonthlyPerfRow(
        month: month,
        label: _fmtMonthLabel(month),
        budget: budget,
        spent: spent,
        pct: pct,
        rawPct: rawPct,
        status: status,
        isCurrent: month == currentMonthKey,
        overspent: rawPct >= 1 ? spent - budget : 0,
      ),
    );
  }

  final changes = <_ChangeRow>[];
  for (var i = 0; i < sorted.length; i++) {
    final entry = sorted[i];
    final prev = i + 1 < sorted.length ? sorted[i + 1] : null;
    final delta = prev != null ? entry.amount - prev.amount : null;
    final deltaPct = prev != null && prev.amount != 0
        ? (((entry.amount - prev.amount) / prev.amount) * 100).round()
        : null;
    final displayDate = DateFormat('d MMM yy', 'en_IN').format(
      safeParseDate(entry.setAt),
    );
    changes.add(
      _ChangeRow(
        id: entry.id,
        amount: entry.amount,
        setAt: entry.setAt,
        delta: delta,
        deltaPct: deltaPct,
        isFirst: prev == null,
        displayDate: displayDate,
      ),
    );
  }

  final trendSlice = sorted.length > 10 ? sorted.sublist(0, 10) : sorted;
  final trendReversed = trendSlice.reversed.toList();
  final trendSpots = <FlSpot>[];
  final trendLabels = <String>[];
  for (var i = 0; i < trendReversed.length; i++) {
    final entry = trendReversed[i];
    trendSpots.add(FlSpot(i.toDouble(), entry.amount));
    trendLabels.add(
      DateFormat.MMMd('en').format(safeParseDate(entry.setAt)),
    );
  }

  final barMonths = months.length > 6 ? months.sublist(0, 6) : months;
  final barChrono = barMonths.reversed.toList();
  final spendingBars = <_SpendingBarRow>[];
  for (final month in barChrono) {
    final b = getBudget(month);
    final s = getSpent(month);
    spendingBars.add(
      _SpendingBarRow(
        name: _fmtMonthLabel(month),
        budget: b,
        spent: s,
        spentColor: _dominantCategoryColor(month, expenses),
      ),
    );
  }

  final valid = monthlyPerf.where((m) => m.budget > 0).toList();
  final drainedCount = valid.where((m) => m.status == _PerfStatus.drained).length;
  final avgBudget = valid.isEmpty
      ? 0
      : (valid.fold<double>(0, (a, m) => a + m.budget) / valid.length).round();

  final totalBudgetAdded = valid.fold<double>(0, (a, m) => a + m.budget);
  final totalSpent = monthlyPerf.fold<double>(0, (a, m) => a + m.spent);

  return _BudgetHistoryData(
    monthlyPerf: monthlyPerf,
    changes: changes,
    trendSpots: trendSpots,
    trendLabels: trendLabels,
    stats: _BudgetStats(
      totalMonths: valid.length,
      drainedCount: drainedCount,
      avgBudget: avgBudget,
      totalBudgetAdded: totalBudgetAdded,
      totalSpent: totalSpent,
    ),
    spendingBars: spendingBars,
  );
}
