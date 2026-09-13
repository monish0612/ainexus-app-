import 'dart:math' as math;

import '../../domain/entities/expense_entities.dart';
import '../utils/currency_formatter.dart';

/// Spend-only transaction slice used by [ExpensePaceMetrics]. Dates are already
/// parsed so the engine stays free of I/O and UI types.
class PaceTxn {
  const PaceTxn({
    required this.amount,
    required this.category,
    required this.date,
    this.description = '',
  });

  final double amount;
  final String category;
  final DateTime date;
  final String description;

  factory PaceTxn.fromExpense(Expense e) => PaceTxn(
        amount: e.amount,
        category: e.category,
        date: safeParseDate(e.date),
        description: e.description,
      );

  bool get isSpend => !isNonSpendCategory(category);
}

enum PaceStatus {
  /// No monthly budget set — pace math is skipped.
  none,
  onTrack,
  aheadOfPace,
  overPlan,
}

enum RangeFactKind {
  vsPrevious,
  topCategoryShare,
  top3Concentration,
  categoryShift,
  sixMonthExtreme,
}

/// Calendar-month pace vs a monthly budget. All rupee figures are spend-only.
class MonthPace {
  const MonthPace({
    required this.budget,
    required this.monthSpent,
    required this.expectedByNow,
    required this.leftover,
    required this.safeDaily,
    required this.paceThreshold,
    required this.status,
    required this.dayOfMonth,
    required this.lengthOfMonth,
    required this.remainingDays,
  });

  final double budget;
  final double monthSpent;
  final double expectedByNow;
  final double leftover;
  final double safeDaily;
  final double paceThreshold;
  final PaceStatus status;
  final int dayOfMonth;
  final int lengthOfMonth;
  final int remainingDays;

  bool get hasBudget => budget > 0;

  /// Cashew-style remaining copy. Empty when no budget is set.
  String get remainingSentence {
    if (!hasBudget) return '';
    if (leftover <= 0) {
      return 'No remaining budget this month.';
    }
    final days =
        remainingDays == 1 ? '1 more day' : '$remainingDays more days';
    return 'You can spend ${formatCurrency(safeDaily)}/day for $days';
  }

  /// 0–1 position of "today" along a calendar-month bar (pace overlay tick).
  double get todayFraction =>
      lengthOfMonth <= 0 ? 0 : (dayOfMonth / lengthOfMonth).clamp(0.0, 1.0);
}

/// One cell in the current-month heat calendar.
class HeatDay {
  const HeatDay({
    required this.date,
    required this.spent,
    required this.intensity,
    required this.isFuture,
    required this.isToday,
  });

  final DateTime date;
  final double spent;

  /// 0–1 vs the hottest spend day in the month. Future days are 0.
  final double intensity;
  final bool isFuture;
  final bool isToday;
}

class RangeFact {
  const RangeFact({
    required this.kind,
    required this.headline,
    required this.detail,
    this.delta,
    this.percent,
    this.category,
  });

  final RangeFactKind kind;
  final String headline;
  final String detail;
  final double? delta;
  final double? percent;
  final String? category;
}

/// Historic facts for a period vs the previous equal-length range.
class RangeFacts {
  const RangeFacts({this.primary, this.secondary, this.all = const []});

  final RangeFact? primary;
  final RangeFact? secondary;
  final List<RangeFact> all;

  bool get isEmpty => primary == null;
  bool get isNotEmpty => primary != null;
}

class HistoricMonthBar {
  const HistoricMonthBar({
    required this.monthKey,
    required this.label,
    required this.total,
  });

  final String monthKey;
  final String label;
  final double total;
}

class MerchantTotal {
  const MerchantTotal({
    required this.name,
    required this.total,
    required this.count,
  });

  final String name;
  final double total;
  final int count;
}

/// Live budget surfaces (ring, Tracker card, Insights strip) share this.
/// 75% used → AT RISK; 100% → over. Cashew / Money Manager Step 0.
const double kBudgetAtRiskRatio = 0.75;

/// Pure, deterministic SpendSense-style metrics. No I/O.
class ExpensePaceMetrics {
  const ExpensePaceMetrics._();

  static const double rupeeFloor = 100;
  static const double pctFloor = 0.05;
  static const double pacePct = 0.08;
  static const double atRiskRatio = kBudgetAtRiskRatio;

  static const List<String> _monthShort = [
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

  static int daysInMonth(DateTime day) =>
      DateTime(day.year, day.month + 1, 0).day;

  static String monthKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';

  /// Inclusive of today. Last day of the period returns 1 (never 0).
  static int remainingDaysInclusive(
    DateTime today, {
    DateTime? periodEndInclusive,
  }) {
    final day = DateTime(today.year, today.month, today.day);
    final end = periodEndInclusive == null
        ? DateTime(day.year, day.month, daysInMonth(day))
        : DateTime(
            periodEndInclusive.year,
            periodEndInclusive.month,
            periodEndInclusive.day,
          );
    return math.max(1, end.difference(day).inDays + 1);
  }

  static bool isAtRisk({required double spent, required double budget}) {
    if (budget <= 0) return false;
    final pct = spent / budget;
    return spent < budget && pct >= kBudgetAtRiskRatio;
  }

  /// Mean spend of completed calendar months, skipping the current month and
  /// any month below [rupeeFloor] (Cashew "average of completed periods").
  static double? completedPeriodAverage({
    required Map<String, double> monthTotals,
    required DateTime now,
    int lookbackMonths = 12,
  }) {
    final values = <double>[];
    for (var i = 1; i <= lookbackMonths; i++) {
      final d = DateTime(now.year, now.month - i, 1);
      final total = monthTotals[monthKey(d)] ?? 0;
      if (total >= rupeeFloor) values.add(total);
    }
    if (values.isEmpty) return null;
    return values.reduce((a, b) => a + b) / values.length;
  }

  /// [today] is calendar-day scoped (time of day ignored).
  static MonthPace monthPace({
    required double budget,
    required double monthSpent,
    required DateTime today,
  }) {
    final day = DateTime(today.year, today.month, today.day);
    final length = daysInMonth(day);
    final dayOfMonth = day.day;
    final remaining = remainingDaysInclusive(day);
    final expected =
        budget > 0 ? budget * (dayOfMonth / length) : 0.0;
    final leftover = budget - monthSpent;
    final safeDaily =
        budget > 0 ? math.max(0.0, leftover) / remaining : 0.0;
    final threshold = budget > 0 ? math.max(budget * pacePct, rupeeFloor) : 0.0;

    PaceStatus status = PaceStatus.none;
    if (budget > 0) {
      if (monthSpent > budget) {
        status = PaceStatus.overPlan;
      } else if (monthSpent - expected > threshold) {
        status = PaceStatus.aheadOfPace;
      } else {
        status = PaceStatus.onTrack;
      }
    }

    return MonthPace(
      budget: budget,
      monthSpent: monthSpent,
      expectedByNow: expected,
      leftover: leftover,
      safeDaily: safeDaily,
      paceThreshold: threshold,
      status: status,
      dayOfMonth: dayOfMonth,
      lengthOfMonth: length,
      remainingDays: remaining,
    );
  }

  /// Spend-only daily heat for the calendar month containing [month].
  static List<HeatDay> heatMonth({
    required Iterable<PaceTxn> expenses,
    required DateTime month,
    required DateTime today,
  }) {
    final todayDay = DateTime(today.year, today.month, today.day);
    final start = DateTime(month.year, month.month, 1);
    final length = daysInMonth(start);
    final byDay = <int, double>{};
    for (final e in expenses) {
      if (!e.isSpend) continue;
      final d = DateTime(e.date.year, e.date.month, e.date.day);
      if (d.year != start.year || d.month != start.month) continue;
      byDay[d.day] = (byDay[d.day] ?? 0) + e.amount;
    }
    var hottest = 0.0;
    for (var day = 1; day <= length; day++) {
      final date = DateTime(start.year, start.month, day);
      if (date.isAfter(todayDay)) continue;
      final spent = byDay[day] ?? 0;
      if (spent > hottest) hottest = spent;
    }

    final days = <HeatDay>[];
    for (var day = 1; day <= length; day++) {
      final date = DateTime(start.year, start.month, day);
      final future = date.isAfter(todayDay);
      final spent = future ? 0.0 : (byDay[day] ?? 0);
      days.add(
        HeatDay(
          date: date,
          spent: spent,
          intensity: future || hottest <= 0 ? 0 : spent / hottest,
          isFuture: future,
          isToday: date == todayDay,
        ),
      );
    }
    return days;
  }

  /// Previous equal-length window: `[prevStart, currentStart)` when current is
  /// `[currentStart, currentEnd)`.
  static ({DateTime start, DateTime end}) previousMatchingTimeRange({
    required DateTime start,
    required DateTime end,
  }) {
    final duration = end.difference(start);
    return (start: start.subtract(duration), end: start);
  }

  static bool meetsFloor(double delta, double base) {
    final abs = delta.abs();
    if (abs < rupeeFloor) return false;
    if (base <= 0) return abs >= rupeeFloor;
    return abs / base >= pctFloor;
  }

  static RangeFacts rangeFacts({
    required Iterable<PaceTxn> current,
    required Iterable<PaceTxn> previous,
    required DateTime now,
    Map<String, double> monthlyTotals = const {},
    String periodLabel = 'this period',
  }) {
    final curr = current.where((e) => e.isSpend).toList();
    final prev = previous.where((e) => e.isSpend).toList();
    final currTotal = _sum(curr);
    final prevTotal = _sum(prev);
    final facts = <RangeFact>[];

    final vsPrev = _vsPrevious(
      currTotal: currTotal,
      prevTotal: prevTotal,
      periodLabel: periodLabel,
    );
    if (vsPrev != null) facts.add(vsPrev);

    final byCatCurr = _byCategory(curr);
    final byCatPrev = _byCategory(prev);
    final topShare = _topCategoryShare(byCatCurr, currTotal);
    if (topShare != null) facts.add(topShare);

    final concentration = _top3Concentration(byCatCurr, currTotal);
    if (concentration != null) facts.add(concentration);

    final shift = _categoryShift(byCatCurr, byCatPrev);
    if (shift != null) facts.add(shift);

    final extreme = _sixMonthExtreme(
      monthlyTotals: monthlyTotals,
      now: now,
    );
    if (extreme != null) facts.add(extreme);

    return RangeFacts(
      primary: facts.isEmpty ? null : facts.first,
      secondary: facts.length > 1 ? facts[1] : null,
      all: facts,
    );
  }

  /// Last [months] calendar months, oldest first, padded with zeros.
  /// [monthTotals] is `YYYY-MM` → spend (same shape as memory `monthlyTrend`).
  static List<HistoricMonthBar> historicCalendarBars({
    required Map<String, double> monthTotals,
    required int months,
    required DateTime now,
  }) {
    final n = months.clamp(1, 24);
    final bars = <HistoricMonthBar>[];
    for (var i = n - 1; i >= 0; i--) {
      final d = DateTime(now.year, now.month - i, 1);
      final key = monthKey(d);
      bars.add(
        HistoricMonthBar(
          monthKey: key,
          label: _monthShort[d.month - 1],
          total: monthTotals[key] ?? 0,
        ),
      );
    }
    return bars;
  }

  static Map<String, double> monthTotalsFrom(Iterable<PaceTxn> expenses) {
    final map = <String, double>{};
    for (final e in expenses) {
      if (!e.isSpend) continue;
      final key = monthKey(e.date);
      map[key] = (map[key] ?? 0) + e.amount;
    }
    return map;
  }

  static List<MerchantTotal> topMerchants(
    Iterable<PaceTxn> expenses, {
    int limit = 5,
  }) {
    final map = <String, ({double total, int count})>{};
    for (final e in expenses) {
      if (!e.isSpend) continue;
      final name = e.description.trim().isEmpty
          ? 'Unknown'
          : e.description.trim();
      final prev = map[name];
      map[name] = (
        total: (prev?.total ?? 0) + e.amount,
        count: (prev?.count ?? 0) + 1,
      );
    }
    final list = map.entries
        .map((e) => MerchantTotal(
              name: e.key,
              total: e.value.total,
              count: e.value.count,
            ))
        .toList()
      ..sort((a, b) => b.total.compareTo(a.total));
    return list.take(limit).toList();
  }

  static double _sum(Iterable<PaceTxn> items) =>
      items.fold<double>(0, (s, e) => s + e.amount);

  static Map<String, double> _byCategory(Iterable<PaceTxn> items) {
    final map = <String, double>{};
    for (final e in items) {
      map[e.category] = (map[e.category] ?? 0) + e.amount;
    }
    return map;
  }

  static RangeFact? _vsPrevious({
    required double currTotal,
    required double prevTotal,
    required String periodLabel,
  }) {
    final delta = currTotal - prevTotal;
    if (!meetsFloor(delta, prevTotal) &&
        !(prevTotal <= 0 && currTotal >= rupeeFloor)) {
      return null;
    }
    if (prevTotal <= 0) {
      return RangeFact(
        kind: RangeFactKind.vsPrevious,
        headline: '${formatCurrency(currTotal)} spent $periodLabel',
        detail: 'No matching prior range to compare.',
        delta: currTotal,
      );
    }
    final pct = (delta / prevTotal) * 100;
    final more = delta > 0;
    return RangeFact(
      kind: RangeFactKind.vsPrevious,
      headline: more
          ? '${formatCurrency(delta)} more than the previous range'
          : '${formatCurrency(delta.abs())} less than the previous range',
      detail: more
          ? '${formatCurrency(currTotal)} vs ${formatCurrency(prevTotal)} last time.'
          : '${formatCurrency(currTotal)} vs ${formatCurrency(prevTotal)} last time.',
      delta: delta,
      percent: pct,
    );
  }

  static RangeFact? _topCategoryShare(
    Map<String, double> byCat,
    double total,
  ) {
    if (byCat.isEmpty || total < rupeeFloor) return null;
    final top = byCat.entries.reduce((a, b) => a.value >= b.value ? a : b);
    if (top.value < rupeeFloor) return null;
    final pct = (top.value / total) * 100;
    return RangeFact(
      kind: RangeFactKind.topCategoryShare,
      headline: '${top.key} is ${pct.round()}% of this period',
      detail: '${formatCurrency(top.value)} of ${formatCurrency(total)}.',
      percent: pct,
      category: top.key,
    );
  }

  static RangeFact? _top3Concentration(
    Map<String, double> byCat,
    double total,
  ) {
    if (byCat.length < 3 || total < rupeeFloor) return null;
    final sorted = byCat.values.toList()..sort((a, b) => b.compareTo(a));
    final top3 = sorted.take(3).fold<double>(0, (s, v) => s + v);
    final pct = (top3 / total) * 100;
    if (pct < 70) return null;
    return RangeFact(
      kind: RangeFactKind.top3Concentration,
      headline: 'Top 3 categories are ${pct.round()}% of spend',
      detail: 'Most of this period sits in just a few buckets.',
      percent: pct,
    );
  }

  static RangeFact? _categoryShift(
    Map<String, double> curr,
    Map<String, double> prev,
  ) {
    if (curr.isEmpty) return null;
    String? bestCat;
    var bestDelta = 0.0;
    var bestBase = 0.0;
    final keys = {...curr.keys, ...prev.keys};
    for (final cat in keys) {
      final c = curr[cat] ?? 0;
      final p = prev[cat] ?? 0;
      final delta = c - p;
      if (!meetsFloor(delta, p)) continue;
      if (bestCat == null || delta.abs() > bestDelta.abs()) {
        bestCat = cat;
        bestDelta = delta;
        bestBase = p;
      }
    }
    if (bestCat == null) return null;
    final pct = bestBase > 0 ? (bestDelta / bestBase) * 100 : 100.0;
    final up = bestDelta > 0;
    return RangeFact(
      kind: RangeFactKind.categoryShift,
      headline: up
          ? '$bestCat rose ${formatCurrency(bestDelta)}'
          : '$bestCat dropped ${formatCurrency(bestDelta.abs())}',
      detail: up
          ? 'Up ${pct.abs().round()}% vs the previous range.'
          : 'Down ${pct.abs().round()}% vs the previous range.',
      delta: bestDelta,
      percent: pct,
      category: bestCat,
    );
  }

  static RangeFact? _sixMonthExtreme({
    required Map<String, double> monthlyTotals,
    required DateTime now,
  }) {
    if (monthlyTotals.isEmpty) return null;
    final bars = historicCalendarBars(
      monthTotals: monthlyTotals,
      months: 6,
      now: now,
    );
    final current = bars.last.total;
    if (current < rupeeFloor) return null;
    var high = bars.first.total;
    var low = bars.first.total;
    for (final b in bars) {
      if (b.total > high) high = b.total;
      if (b.total < low) low = b.total;
    }
    final isHigh = (current - high).abs() < 0.01 &&
        bars.where((b) => b.total >= high - 0.01).length == 1;
    final isLow = (current - low).abs() < 0.01 &&
        bars.where((b) => (b.total - low).abs() < 0.01).length == 1 &&
        current > 0;
    if (isHigh && meetsFloor(current - low, low)) {
      return RangeFact(
        kind: RangeFactKind.sixMonthExtreme,
        headline: '${formatCurrency(current)} is a 6-month high',
        detail: 'Highest calendar-month spend in the last six months.',
        delta: current - low,
      );
    }
    if (isLow && meetsFloor(high - current, high)) {
      return RangeFact(
        kind: RangeFactKind.sixMonthExtreme,
        headline: '${formatCurrency(current)} is a 6-month low',
        detail: 'Lowest calendar-month spend in the last six months.',
        delta: current - high,
      );
    }
    return null;
  }
}
