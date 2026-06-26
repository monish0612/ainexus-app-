import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../domain/entities/expense_entities.dart';

/// Period chips: Week, Month, 3M, 6M, All Time (simplified from `ExpenseTrendModal.tsx`).
enum ExpenseTrendPeriod {
  week,
  month,
  threeMonths,
  sixMonths,
  allTime,
}

extension on ExpenseTrendPeriod {
  String get label {
    switch (this) {
      case ExpenseTrendPeriod.week:
        return 'Week';
      case ExpenseTrendPeriod.month:
        return 'Month';
      case ExpenseTrendPeriod.threeMonths:
        return '3M';
      case ExpenseTrendPeriod.sixMonths:
        return '6M';
      case ExpenseTrendPeriod.allTime:
        return 'All Time';
    }
  }
}

class _RangePair {
  const _RangePair({
    required this.start,
    required this.end,
    required this.prevStart,
    required this.prevEnd,
  });

  final DateTime start;
  final DateTime end;
  final DateTime prevStart;
  final DateTime prevEnd;
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

bool _inclusiveInRange(DateTime d, DateTime start, DateTime end) {
  final dd = d.millisecondsSinceEpoch;
  final s = _day(start).millisecondsSinceEpoch;
  final e = DateTime(
    end.year,
    end.month,
    end.day,
    23,
    59,
    59,
    999,
  ).millisecondsSinceEpoch;
  return dd >= s && dd <= e;
}

_RangePair _rangeFor(ExpenseTrendPeriod p, DateTime now) {
  final today = _day(now);
  switch (p) {
    case ExpenseTrendPeriod.week:
      final start = today.subtract(
        Duration(days: today.weekday == DateTime.sunday ? 0 : today.weekday),
      );
      final end = start.add(const Duration(days: 6));
      final prevEnd = start.subtract(const Duration(days: 1));
      final prevStart = prevEnd.subtract(const Duration(days: 6));
      return _RangePair(
        start: start,
        end: end,
        prevStart: prevStart,
        prevEnd: prevEnd,
      );
    case ExpenseTrendPeriod.month:
      final start = DateTime(now.year, now.month, 1);
      final end = DateTime(now.year, now.month + 1, 0);
      final prevEnd = start.subtract(const Duration(days: 1));
      final prevStart = DateTime(prevEnd.year, prevEnd.month, 1);
      return _RangePair(
        start: start,
        end: end,
        prevStart: prevStart,
        prevEnd: prevEnd,
      );
    case ExpenseTrendPeriod.threeMonths:
      final start = DateTime(now.year, now.month - 2, 1);
      final end = DateTime(now.year, now.month + 2, 0);
      final prevEnd = start.subtract(const Duration(days: 1));
      final prevStart = DateTime(now.year, now.month - 5, 1);
      return _RangePair(
        start: start,
        end: end,
        prevStart: prevStart,
        prevEnd: prevEnd,
      );
    case ExpenseTrendPeriod.sixMonths:
      final start = DateTime(now.year, now.month - 5, 1);
      final end = DateTime(now.year, now.month + 2, 0);
      final prevEnd = start.subtract(const Duration(days: 1));
      final prevStart = DateTime(now.year, now.month - 11, 1);
      return _RangePair(
        start: start,
        end: end,
        prevStart: prevStart,
        prevEnd: prevEnd,
      );
    case ExpenseTrendPeriod.allTime:
      final futureEnd = DateTime(now.year, now.month + 2, 0);
      return _RangePair(
        start: DateTime.fromMillisecondsSinceEpoch(0),
        end: futureEnd,
        prevStart: DateTime.fromMillisecondsSinceEpoch(0),
        prevEnd: futureEnd,
      );
  }
}

List<Expense> _filter(
  List<Expense> expenses,
  DateTime start,
  DateTime end,
) {
  return expenses
      .where((e) => _inclusiveInRange(safeParseDate(e.date), start, end))
      .toList();
}

/// Full-screen spending trends (`ExpenseTrendModal.tsx` subset + requested periods).
Future<void> showExpenseTrendModal(
  BuildContext context, {
  required List<Expense> expenses,
  double budget = 0,
}) {
  return Navigator.of(context).push<void>(
    PageRouteBuilder<void>(
      pageBuilder: (_, __, ___) => ExpenseTrendModal(
        expenses: expenses,
        budget: budget,
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

class ExpenseTrendModal extends StatefulWidget {
  const ExpenseTrendModal({
    super.key,
    required this.expenses,
    this.budget = 0,
  });

  final List<Expense> expenses;
  final double budget;

  @override
  State<ExpenseTrendModal> createState() => _ExpenseTrendModalState();
}

class _ExpenseTrendModalState extends State<ExpenseTrendModal> {
  ExpenseTrendPeriod _period = ExpenseTrendPeriod.month;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final textTheme = GoogleFonts.plusJakartaSansTextTheme(
      Theme.of(context).textTheme,
    );
    final now = DateTime.now();
    final rp = _rangeFor(_period, now);
    final curr = _filter(widget.expenses, rp.start, rp.end);
    final prev = _period == ExpenseTrendPeriod.allTime
        ? <Expense>[]
        : _filter(widget.expenses, rp.prevStart, rp.prevEnd);

    final currTotal = curr.fold<double>(0, (s, e) => s + e.amount);
    final prevTotal = prev.fold<double>(0, (s, e) => s + e.amount);
    final changePct = prevTotal > 0
        ? (((currTotal - prevTotal) / prevTotal) * 100).round()
        : 0;

    final chart = _buildChartSeries(curr, _period, now);
    final spots = chart.spots;
    final rawMax = spots.isEmpty
        ? 0.0
        : spots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
    final maxY = rawMax > 0 ? rawMax * 1.15 : 1.0;

    final categories = _topCategories(curr, prev, currTotal);
    final dayPattern = _dayPattern(curr);
    final maxDay = dayPattern.isEmpty
        ? null
        : dayPattern.reduce((a, b) => a.amount >= b.amount ? a : b);

    final isEmpty = curr.isEmpty;
    final isUp = changePct > 0;
    final isStable = prevTotal == 0 || changePct.abs() <= 3;

    return Scaffold(
      backgroundColor: colors.bg,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: colors.bg,
                border: Border(bottom: BorderSide(color: colors.border)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Expense Trend',
                          style: textTheme.titleMedium?.copyWith(
                            color: colors.text,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0x2EEF4444),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: const Color(0x59EF4444),
                            ),
                          ),
                          child: Text(
                            'LIVE',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFFEF4444),
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                children: [
                  for (final p in ExpenseTrendPeriod.values) ...[
                    if (p != ExpenseTrendPeriod.values.first)
                      const SizedBox(width: 8),
                    ChoiceChip(
                      label: Text(p.label),
                      selected: _period == p,
                      onSelected: (_) => setState(() => _period = p),
                      selectedColor: const Color(0xFF6366F1),
                      labelStyle: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight:
                            _period == p ? FontWeight.w700 : FontWeight.w500,
                        color: _period == p ? Colors.white : colors.text3,
                      ),
                      side: BorderSide(
                        color: _period == p ? Colors.transparent : colors.border,
                      ),
                      backgroundColor: colors.bg2,
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [
                            Color(0xFF110826),
                            Color(0xFF1A0D36),
                            Color(0xFF0D1A3A),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: const Color(0x4D7C3AED),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${_period.label.toUpperCase()} TOTAL',
                                        style: textTheme.labelSmall?.copyWith(
                                          color: colors.text4,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 1.5,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        formatCurrency(currTotal),
                                        style: textTheme.displaySmall?.copyWith(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w900,
                                          fontSize: 36,
                                          letterSpacing: -1.2,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (prevTotal > 0 &&
                                    _period != ExpenseTrendPeriod.allTime)
                                  Container(
                                    margin: const EdgeInsets.only(top: 8),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isStable
                                          ? colors.bg3
                                          : isUp
                                              ? const Color(0x2EEF4444)
                                              : const Color(0x2E22C55E),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: isStable
                                            ? colors.border
                                            : isUp
                                                ? const Color(0x66EF4444)
                                                : const Color(0x6622C55E),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          isStable
                                              ? LucideIcons.minus
                                              : isUp
                                                  ? LucideIcons.trendingUp
                                                  : LucideIcons.trendingDown,
                                          size: 12,
                                          color: isStable
                                              ? colors.text3
                                              : isUp
                                                  ? const Color(0xFFEF4444)
                                                  : const Color(0xFF22C55E),
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          isStable
                                              ? 'Stable'
                                              : '${isUp ? '+' : ''}$changePct%',
                                          style: GoogleFonts.plusJakartaSans(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w800,
                                            color: isStable
                                                ? colors.text3
                                                : isUp
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
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 0, 16, 0),
                            child: SizedBox(
                              height: 160,
                              child: spots.isEmpty
                                  ? Center(
                                      child: Text(
                                        'No chart data',
                                        style: textTheme.bodySmall?.copyWith(
                                          color: colors.text4,
                                        ),
                                      ),
                                    )
                                  : LineChart(
                                      LineChartData(
                                        minY: 0,
                                        maxY: maxY > 0 ? maxY : 1,
                                        clipData: const FlClipData.all(),
                                        gridData: FlGridData(
                                          show: true,
                                          drawVerticalLine: false,
                                          horizontalInterval: maxY > 4
                                              ? maxY / 4
                                              : 1,
                                          getDrawingHorizontalLine: (_) =>
                                              FlLine(
                                            color: colors.border
                                                .withValues(alpha: 0.5),
                                            strokeWidth: 1,
                                          ),
                                        ),
                                        borderData: FlBorderData(show: false),
                                        titlesData: FlTitlesData(
                                          topTitles: const AxisTitles(
                                            sideTitles: SideTitles(
                                              showTitles: false,
                                            ),
                                          ),
                                          rightTitles: const AxisTitles(
                                            sideTitles: SideTitles(
                                              showTitles: false,
                                            ),
                                          ),
                                          leftTitles: const AxisTitles(
                                            sideTitles: SideTitles(
                                              showTitles: false,
                                            ),
                                          ),
                                          bottomTitles: AxisTitles(
                                            sideTitles: SideTitles(
                                              showTitles: true,
                                              reservedSize: 30,
                                              interval: chart.labels.length > 12
                                                  ? (chart.labels.length / 6)
                                                      .ceilToDouble()
                                                  : 1,
                                              getTitlesWidget: (v, meta) {
                                                final i = v.round();
                                                if (i < 0 ||
                                                    i >= chart.labels.length) {
                                                  return const SizedBox.shrink();
                                                }
                                                return SideTitleWidget(
                                                  axisSide: meta.axisSide,
                                                  fitInside:
                                                      SideTitleFitInsideData
                                                          .fromTitleMeta(meta),
                                                  child: Text(
                                                    chart.labels[i],
                                                    style:
                                                        GoogleFonts
                                                            .plusJakartaSans(
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
                                            dotData: const FlDotData(
                                              show: false,
                                            ),
                                            belowBarData: BarAreaData(
                                              show: true,
                                              gradient: const LinearGradient(
                                                colors: [
                                                  Color(0x8C7C3AED),
                                                  Color(0x057C3AED),
                                                ],
                                                begin: Alignment.topCenter,
                                                end: Alignment.bottomCenter,
                                              ),
                                            ),
                                          ),
                                        ],
                                        lineTouchData: LineTouchData(
                                          touchTooltipData:
                                              LineTouchTooltipData(
                                            getTooltipItems: (touched) {
                                              return touched.map((t) {
                                                final i = t.x.round().clamp(
                                                      0,
                                                      chart.labels.length - 1,
                                                    );
                                                return LineTooltipItem(
                                                  '${chart.labels[i]}\n${formatCurrency(t.y)}',
                                                  GoogleFonts.plusJakartaSans(
                                                    color: const Color(
                                                      0xFFC4B5FD,
                                                    ),
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                );
                                              }).toList();
                                            },
                                          ),
                                        ),
                                      ),
                                    ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.fromLTRB(8, 14, 8, 18),
                            decoration: BoxDecoration(
                              border: Border(
                                top: BorderSide(
                                  color: colors.border.withValues(alpha: 0.5),
                                ),
                              ),
                            ),
                            child: Row(
                              children: [
                                _QuickStatIcon(
                                  icon: LucideIcons.calendarDays,
                                  iconColor: const Color(0xFFA78BFA),
                                  label: 'AVG / DAY',
                                  value: _avgPerDay(curr, currTotal),
                                  colors: colors,
                                ),
                                _QuickStatIcon(
                                  icon: LucideIcons.trendingUp,
                                  iconColor: const Color(0xFFF87171),
                                  label: 'PEAK BAR',
                                  value: chart.peakLabel,
                                  colors: colors,
                                ),
                                _QuickStatIcon(
                                  icon: LucideIcons.hash,
                                  iconColor: const Color(0xFF34D399),
                                  label: 'TXNS',
                                  value: '${curr.length}',
                                  colors: colors,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!isEmpty && categories.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      Text(
                        'Category breakdown',
                        style: textTheme.titleMedium?.copyWith(
                          color: colors.text,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Shift vs previous period',
                        style: textTheme.bodySmall?.copyWith(
                          color: colors.text4,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ...categories.map(
                        (c) => _CategoryShiftRow(
                          item: c,
                          colors: colors,
                          textTheme: textTheme,
                        ),
                      ),
                    ],
                    if (!isEmpty) ...[
                      const SizedBox(height: 20),
                      Text(
                        'Spending by day',
                        style: textTheme.titleMedium?.copyWith(
                          color: colors.text,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (maxDay != null && maxDay.amount > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 6, bottom: 8),
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0x1FF59E0B),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: const Color(0x40F59E0B),
                                ),
                              ),
                              child: Text(
                                '🔥 Peak: ${maxDay.full}',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFFF59E0B),
                                ),
                              ),
                            ),
                          ),
                        ),
                      SizedBox(
                        height: 140,
                        child: BarChart(
                          BarChartData(
                            maxY: math.max(
                              1,
                              dayPattern
                                      .map((e) => e.amount)
                                      .reduce((a, b) => a > b ? a : b) *
                                  1.2,
                            ),
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
                                  reservedSize: 22,
                                  getTitlesWidget: (v, _) {
                                    final i = v.toInt();
                                    if (i < 0 || i >= dayPattern.length) {
                                      return const SizedBox.shrink();
                                    }
                                    return Text(
                                      dayPattern[i].short,
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 11,
                                        color: colors.text3,
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                            barGroups: [
                              for (var i = 0; i < dayPattern.length; i++)
                                BarChartGroupData(
                                  x: i,
                                  barRods: [
                                    BarChartRodData(
                                      toY: dayPattern[i].amount,
                                      width: 14,
                                      borderRadius: const BorderRadius.vertical(
                                        top: Radius.circular(5),
                                      ),
                                      gradient: const LinearGradient(
                                        colors: [
                                          Color(0xFF7C3AED),
                                          Color(0xB34F46E5),
                                        ],
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    if (isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 48),
                        child: Column(
                          children: [
                            const Text('📊', style: TextStyle(fontSize: 52)),
                            const SizedBox(height: 16),
                            Text(
                              'No data for ${_period.label}',
                              style: textTheme.titleSmall?.copyWith(
                                color: colors.text3,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Add expenses to see trends and comparisons.',
                              textAlign: TextAlign.center,
                              style: textTheme.bodySmall?.copyWith(
                                color: colors.text5,
                                height: 1.6,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _avgPerDay(List<Expense> curr, double total) {
    if (curr.isEmpty) return '—';
    final days = curr.map((e) => _day(safeParseDate(e.date))).toSet().length;
    if (days == 0) return '—';
    return formatCurrency(total / days);
  }
}

class _ChartSeries {
  _ChartSeries({
    required this.spots,
    required this.labels,
    required this.peakLabel,
  });

  final List<FlSpot> spots;
  final List<String> labels;
  final String peakLabel;
}

_ChartSeries _buildChartSeries(
  List<Expense> curr,
  ExpenseTrendPeriod period,
  DateTime now,
) {
  switch (period) {
    case ExpenseTrendPeriod.week:
      const names = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
      final m = <int, double>{for (var i = 0; i < 7; i++) i: 0};
      for (final e in curr) {
        final wd = safeParseDate(e.date).weekday; // 1..7 Mon..Sun
        final idx = wd == DateTime.sunday ? 0 : wd;
        m[idx] = (m[idx] ?? 0) + e.amount;
      }
      const labels = names;
      final vals = List<double>.generate(7, (i) => m[i] ?? 0);
      return _ChartSeries(
        spots: [
          for (var i = 0; i < 7; i++) FlSpot(i.toDouble(), vals[i]),
        ],
        labels: labels,
        peakLabel: vals.every((v) => v == 0)
            ? '—'
            : formatCurrency(vals.reduce((a, b) => a > b ? a : b)),
      );
    case ExpenseTrendPeriod.month:
      final last = DateTime(now.year, now.month + 1, 0).day;
      final m = <int, double>{for (var d = 1; d <= last; d++) d: 0};
      for (final e in curr) {
        final dt = safeParseDate(e.date);
        m[dt.day] = (m[dt.day] ?? 0) + e.amount;
      }
      final labels = List.generate(last, (i) => '${i + 1}');
      final vals = List.generate(last, (i) => m[i + 1] ?? 0);
      return _ChartSeries(
        spots: [
          for (var i = 0; i < last; i++) FlSpot(i.toDouble(), vals[i]),
        ],
        labels: labels,
        peakLabel: vals.every((v) => v == 0)
            ? '—'
            : formatCurrency(vals.reduce((a, b) => a > b ? a : b)),
      );
    case ExpenseTrendPeriod.threeMonths:
    case ExpenseTrendPeriod.sixMonths:
    case ExpenseTrendPeriod.allTime:
      final monthBuckets = <String, double>{};
      for (final e in curr) {
        final dt = safeParseDate(e.date);
        final key =
            '${dt.year}-${dt.month.toString().padLeft(2, '0')}';
        monthBuckets[key] = (monthBuckets[key] ?? 0) + e.amount;
      }
      final keys = monthBuckets.keys.toList()..sort();
      if (keys.isEmpty) {
        return _ChartSeries(spots: [], labels: [], peakLabel: '—');
      }
      final labels = keys.map((k) {
        final p = k.split('-');
        final y = int.parse(p[0]);
        final mo = int.parse(p[1]);
        return '${_mon(mo)} \'${y.toString().substring(2)}';
      }).toList();
      final vals = keys.map((k) => monthBuckets[k]!).toList();
      return _ChartSeries(
        spots: [
          for (var i = 0; i < keys.length; i++) FlSpot(i.toDouble(), vals[i]),
        ],
        labels: labels,
        peakLabel: formatCurrency(vals.reduce((a, b) => a > b ? a : b)),
      );
  }
}

String _mon(int m) {
  const names = [
    '',
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return names[m];
}

class _CatShift {
  _CatShift({
    required this.name,
    required this.amount,
    required this.pct,
    required this.shift,
    required this.prevAmount,
  });

  final String name;
  final double amount;
  final int pct;
  final int shift;
  final double prevAmount;
}

List<_CatShift> _topCategories(
  List<Expense> curr,
  List<Expense> prev,
  double currTotal,
) {
  final catMap = <String, double>{};
  for (final e in curr) {
    catMap[e.category] = (catMap[e.category] ?? 0) + e.amount;
  }
  final prevCat = <String, double>{};
  for (final e in prev) {
    prevCat[e.category] = (prevCat[e.category] ?? 0) + e.amount;
  }
  final sorted = catMap.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return sorted.take(5).map((e) {
    final amt = e.value;
    final pa = prevCat[e.key] ?? 0;
    final shift = pa > 0
        ? (((amt - pa) / pa) * 100).round()
        : (amt > 0 ? 100 : 0);
    final pct = currTotal > 0 ? ((amt / currTotal) * 100).round() : 0;
    return _CatShift(
      name: e.key,
      amount: amt,
      pct: pct,
      shift: shift,
      prevAmount: pa,
    );
  }).toList();
}

class _DayAmt {
  _DayAmt({
    required this.short,
    required this.full,
    required this.amount,
  });

  final String short;
  final String full;
  final double amount;
}

List<_DayAmt> _dayPattern(List<Expense> curr) {
  const shorts = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
  const fulls = [
    'Sun',
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
  ];
  final m = List<double>.filled(7, 0);
  for (final e in curr) {
    final d = safeParseDate(e.date).weekday;
    final i = d == DateTime.sunday ? 0 : d;
    m[i] += e.amount;
  }
  return List.generate(
    7,
    (i) => _DayAmt(short: shorts[i], full: fulls[i], amount: m[i]),
  );
}

class _QuickStatIcon extends StatelessWidget {
  const _QuickStatIcon({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.colors,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 14, color: iconColor),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 8,
              color: colors.text4,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryShiftRow extends StatelessWidget {
  const _CategoryShiftRow({
    required this.item,
    required this.colors,
    required this.textTheme,
  });

  final _CatShift item;
  final AppColors colors;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.categoryColors[item.name] ?? AppColors.accent;
    final icon = AppColors.categoryIcons[item.name] ?? '📦';
    final isUp = item.shift > 5;
    final isDown = item.shift < -5;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: c.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: c.withValues(alpha: 0.35)),
                ),
                child: Text(icon, style: const TextStyle(fontSize: 16)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.name,
                            style: textTheme.titleSmall?.copyWith(
                              color: colors.text,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (item.prevAmount > 0)
                          Container(
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: isUp
                                  ? const Color(0x1FEF4444)
                                  : isDown
                                      ? const Color(0x1F22C55E)
                                      : colors.bg3,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isUp
                                      ? LucideIcons.trendingUp
                                      : isDown
                                          ? LucideIcons.trendingDown
                                          : LucideIcons.minus,
                                  size: 9,
                                  color: isUp
                                      ? const Color(0xFFEF4444)
                                      : isDown
                                          ? const Color(0xFF22C55E)
                                          : colors.text4,
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  '${isUp ? '+' : ''}${item.shift}%',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    color: isUp
                                        ? const Color(0xFFFCA5A5)
                                        : isDown
                                            ? const Color(0xFF86EFAC)
                                            : colors.text4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        Text(
                          formatCurrency(item.amount),
                          style: textTheme.titleSmall?.copyWith(
                            color: colors.text,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: item.pct / 100,
              minHeight: 5,
              backgroundColor: colors.bg3,
              valueColor: AlwaysStoppedAnimation<Color>(c),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${item.pct}% of total spend',
                style: textTheme.labelSmall?.copyWith(color: colors.text5),
              ),
              if (item.prevAmount > 0)
                Text(
                  'prev: ${formatCurrency(item.prevAmount)}',
                  style: textTheme.labelSmall?.copyWith(color: colors.text5),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
