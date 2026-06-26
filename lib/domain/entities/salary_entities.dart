import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// A single month's in-hand salary. [month] is the canonical 'YYYY-MM' key.
@immutable
class SalaryEntry extends Equatable {
  const SalaryEntry({
    required this.id,
    required this.month,
    required this.amount,
    required this.setAt,
  });

  final String id;

  /// 'YYYY-MM' — the month this salary applies to.
  final String month;
  final double amount;

  /// ISO-8601 UTC timestamp of when this entry was last set.
  final String setAt;

  /// Returns the 1-based [year, month] parsed from [month], or null if invalid.
  int? get year => int.tryParse(month.split('-').first);
  int? get monthNumber {
    final parts = month.split('-');
    return parts.length >= 2 ? int.tryParse(parts[1]) : null;
  }

  SalaryEntry copyWith({
    String? id,
    String? month,
    double? amount,
    String? setAt,
  }) {
    return SalaryEntry(
      id: id ?? this.id,
      month: month ?? this.month,
      amount: amount ?? this.amount,
      setAt: setAt ?? this.setAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'month': month,
        'amount': amount,
        'setAt': setAt,
      };

  factory SalaryEntry.fromJson(Map<String, dynamic> json) {
    return SalaryEntry(
      id: (json['id'] ?? '').toString(),
      month: (json['month'] ?? '').toString(),
      amount: (json['amount'] is num)
          ? (json['amount'] as num).toDouble()
          : double.tryParse(json['amount']?.toString() ?? '') ?? 0,
      setAt: (json['setAt'] ?? json['set_at'] ?? '').toString(),
    );
  }

  @override
  List<Object?> get props => [id, month, amount, setAt];
}

/// A salary entry enriched with month-over-month comparison vs the
/// chronologically previous recorded month (the previous *entry*, not
/// necessarily the immediately prior calendar month).
@immutable
class SalaryTrendItem extends Equatable {
  const SalaryTrendItem({
    required this.entry,
    required this.previousAmount,
  });

  final SalaryEntry entry;

  /// Amount of the previous recorded month, or null when this is the first.
  final double? previousAmount;

  double get amount => entry.amount;
  String get month => entry.month;

  double? get deltaAbs =>
      previousAmount == null ? null : amount - previousAmount!;

  /// % change vs the previous recorded month. Positive = hike.
  double? get deltaPct {
    final prev = previousAmount;
    if (prev == null || prev <= 0) return null;
    return ((amount - prev) / prev) * 100;
  }

  bool get isHike => (deltaAbs ?? 0) > 0.0001;
  bool get isCut => (deltaAbs ?? 0) < -0.0001;

  @override
  List<Object?> get props => [entry, previousAmount];
}

/// Fully computed salary stats for the *current month*, combining the in-hand
/// salary with the live budget and the month-to-date spend. All percentages are
/// 0..n doubles (not clamped) so callers can show "over budget" states; UI
/// clamps where it needs a 0..1 progress value.
@immutable
class SalaryStats extends Equatable {
  const SalaryStats({
    required this.month,
    required this.salary,
    required this.budget,
    required this.spent,
    required this.previousSalary,
    required this.totalRecorded,
    required this.monthsRecorded,
    required this.highestSalary,
    required this.averageSalary,
    this.cumulativeSaved = 0,
    this.avgSavingsRatePct = 0,
    this.avgMonthlySpend = 0,
    this.dayOfMonth = 1,
    this.daysInMonth = 30,
    this.ccSpentThisMonth = 0,
    this.ccDueThisMonth = 0,
  });

  /// Current month key 'YYYY-MM'.
  final String month;

  /// In-hand salary for the current month (0 when not yet entered).
  final double salary;

  /// Active monthly budget (0 when not set).
  final double budget;

  /// Month-to-date spend for the current month.
  final double spent;

  /// In-hand salary of the previous recorded month (for hike %), or null.
  final double? previousSalary;

  /// Sum of every recorded month's salary.
  final double totalRecorded;
  final int monthsRecorded;
  final double highestSalary;
  final double averageSalary;

  /// Lifetime net savings: Σ(salary − spend) across every recorded salary
  /// month (the current month's figure is month-to-date). Can be negative.
  final double cumulativeSaved;

  /// Mean per-month savings rate (%) across recorded months with a salary.
  final double avgSavingsRatePct;

  /// Mean monthly spend across *completed* recorded months — used as the burn
  /// baseline for the runway estimate (the in-progress month is excluded so it
  /// doesn't deflate the figure).
  final double avgMonthlySpend;

  /// 1-based day of the current month (clamped to [daysInMonth]).
  final int dayOfMonth;

  /// Number of days in the current calendar month.
  final int daysInMonth;

  /// Total charged to credit cards (cardType 'CC') *this* calendar month. This
  /// is a deferred liability: it settles next month and will be drawn from next
  /// month's salary, so it shrinks the forecasted take-home for next month.
  final double ccSpentThisMonth;

  /// Total charged to credit cards *last* calendar month — the bill that lands
  /// and is repaid from *this* month's salary. Reduces the real take-home now.
  final double ccDueThisMonth;

  bool get hasSalary => salary > 0;

  /// Amount left after spend (can be negative if overspent).
  double get saved => salary - spent;

  /// Spend as a fraction of salary (0..n). 0 when no salary.
  double get spentRatio => salary > 0 ? spent / salary : 0;
  double get savedRatio => salary > 0 ? saved / salary : 0;

  /// Budget as a fraction of salary — how much of income is budgeted.
  double get budgetRatioOfSalary => salary > 0 ? budget / salary : 0;

  /// Spend as a fraction of budget (0..n). 0 when no budget.
  double get budgetUsedRatio => budget > 0 ? spent / budget : 0;

  /// Discretionary income not committed to the budget.
  double get unbudgeted => salary - budget;

  double get spentPct => spentRatio * 100;
  double get savedPct => savedRatio * 100;
  double get budgetPctOfSalary => budgetRatioOfSalary * 100;
  double get budgetUsedPct => budgetUsedRatio * 100;

  /// Month-over-month salary change vs the previous recorded month. Positive =
  /// hike. Null when there's no prior month to compare against.
  double? get hikePct {
    final prev = previousSalary;
    if (prev == null || prev <= 0 || salary <= 0) return null;
    return ((salary - prev) / prev) * 100;
  }

  double? get hikeAbs {
    final prev = previousSalary;
    if (prev == null || salary <= 0) return null;
    return salary - prev;
  }

  bool get isOverBudget => budget > 0 && spent > budget;
  bool get isOverspent => salary > 0 && spent > salary;

  // ── This-month pace / projection ───────────────────────────────────────────

  /// Days elapsed so far this month (at least 1, capped at [daysInMonth]).
  int get daysElapsed => dayOfMonth.clamp(1, daysInMonth);

  /// Days left in the current month (0 on the last day).
  int get daysRemaining => (daysInMonth - dayOfMonth).clamp(0, daysInMonth);

  /// Average spend per elapsed day this month.
  double get dailyBurnRate => spent / daysElapsed;

  /// Projected full-month spend if the current daily pace continues.
  double get projectedSpend => dailyBurnRate * daysInMonth;

  /// Projected end-of-month savings at the current pace (can be negative).
  double get projectedSaved => salary - projectedSpend;

  /// Whether the current pace is on track to finish within budget/salary.
  bool get projectedOverBudget => budget > 0 && projectedSpend > budget;

  /// How much can still be spent per remaining day to stay within the budget
  /// (falls back to salary when no budget is set). 0 once the cap is reached.
  double get safeToSpendPerDay {
    final cap = budget > 0 ? budget : salary;
    if (cap <= 0) return 0;
    final remaining = cap - spent;
    if (remaining <= 0) return 0;
    final days = daysRemaining > 0 ? daysRemaining : 1;
    return remaining / days;
  }

  // ── Credit-card repayment forecast ──────────────────────────────────────────
  //
  // A credit-card charge isn't real cash today — it's a bill you settle next
  // month out of your salary. We surface that timing gap so spending on the
  // card feels as "real" as cash: this month's CC charges are forecast as a
  // deduction from next month's pay.

  /// Any credit-card activity worth surfacing (charging now or a bill landing).
  bool get hasCreditCardActivity => ccSpentThisMonth > 0 || ccDueThisMonth > 0;

  /// What's actually left of *this* month's salary once last month's credit-card
  /// bill is repaid. Can be negative if the bill exceeds the salary.
  double get effectiveTakeHomeThisMonth => salary - ccDueThisMonth;

  /// Forecast take-home for *next* month: we use the current salary as the best
  /// estimate of next month's pay, then subtract this month's credit-card
  /// charges (which become next month's bill). Can be negative.
  double get forecastNextMonthTakeHome => salary - ccSpentThisMonth;

  /// The amount that will be carved out of next month's salary — i.e. this
  /// month's credit-card spend. Alias kept for intent-revealing call sites.
  double get nextMonthRepayment => ccSpentThisMonth;

  /// Share of the (current) salary already committed to next month's CC bill.
  double get ccPctOfSalary => salary > 0 ? (ccSpentThisMonth / salary) * 100 : 0;

  /// True when next month's forecast take-home falls below the average monthly
  /// spend — i.e. the card bill could leave next month short.
  bool get ccLeavesNextMonthShort =>
      hasSalary &&
      ccSpentThisMonth > 0 &&
      avgMonthlySpend > 0 &&
      forecastNextMonthTakeHome < avgMonthlySpend;

  // ── Lifetime ────────────────────────────────────────────────────────────────

  /// Months of expenses the lifetime savings could cover at the average burn
  /// rate — an emergency-fund runway. Null when there's nothing to compute.
  double? get runwayMonths {
    if (avgMonthlySpend <= 0 || cumulativeSaved <= 0) return null;
    return cumulativeSaved / avgMonthlySpend;
  }

  /// A simple 0..100 "financial health" score blending savings rate and budget
  /// discipline. Used purely for the standout stats display.
  int get healthScore {
    if (salary <= 0) return 0;
    final savingsComponent = (savedRatio.clamp(0.0, 1.0)) * 70;
    final budgetComponent = budget > 0
        ? (1 - budgetUsedRatio.clamp(0.0, 1.0)) * 30
        : (savedRatio.clamp(0.0, 1.0)) * 30;
    return (savingsComponent + budgetComponent).round().clamp(0, 100);
  }

  static const empty = SalaryStats(
    month: '',
    salary: 0,
    budget: 0,
    spent: 0,
    previousSalary: null,
    totalRecorded: 0,
    monthsRecorded: 0,
    highestSalary: 0,
    averageSalary: 0,
  );

  /// Pure aggregation of the full salary picture — kept out of the Riverpod
  /// provider so it can be unit-tested in isolation (no DB, no container).
  ///
  /// [history] must be newest-month-first (as the repository emits it).
  /// [spendByMonth] maps 'YYYY-MM' → total spend for that month; the current
  /// month's value is month-to-date. [now] anchors the current-month math.
  /// [ccByMonth] maps 'YYYY-MM' → total credit-card (cardType 'CC') spend for
  /// that month. Used to derive the repayment forecast: this month's CC spend
  /// becomes next month's bill; last month's CC spend is the bill due now.
  factory SalaryStats.compute({
    required List<SalaryEntry> history,
    required double budget,
    required double spent,
    required Map<String, double> spendByMonth,
    required DateTime now,
    Map<String, double> ccByMonth = const {},
  }) {
    final monthKey = monthKeyOf(now);
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final prevMonthKey = monthKeyOf(DateTime(now.year, now.month - 1, 1));

    double salary = 0;
    double? previousSalary;
    for (final e in history) {
      if (e.month == monthKey) {
        salary = e.amount;
      } else if (e.month.compareTo(monthKey) < 0 && previousSalary == null) {
        // history is desc → the first older month is the previous recorded one.
        previousSalary = e.amount;
      }
    }

    final amounts = history.map((e) => e.amount).toList();
    final total = amounts.fold<double>(0, (s, a) => s + a);
    final count = amounts.length;
    final highest =
        amounts.isEmpty ? 0.0 : amounts.reduce((a, b) => a > b ? a : b);
    final average = count > 0 ? total / count : 0.0;

    // Lifetime net savings + mean savings rate: pair each recorded salary
    // month with its spend (current month is month-to-date).
    var cumulativeSaved = 0.0;
    var rateSum = 0.0;
    var rateCount = 0;
    for (final e in history) {
      final monthSpend = spendByMonth[e.month] ?? 0.0;
      cumulativeSaved += e.amount - monthSpend;
      if (e.amount > 0) {
        rateSum += ((e.amount - monthSpend) / e.amount) * 100;
        rateCount++;
      }
    }
    final avgSavingsRatePct = rateCount > 0 ? rateSum / rateCount : 0.0;

    // Burn baseline for runway: mean spend over *completed* months (exclude the
    // in-progress current month). Fall back to the current month when that's
    // all the data we have.
    final completed = spendByMonth.entries
        .where((e) => e.key != monthKey)
        .map((e) => e.value)
        .toList();
    final avgMonthlySpend = completed.isNotEmpty
        ? completed.fold<double>(0, (s, a) => s + a) / completed.length
        : (spendByMonth[monthKey] ?? 0.0);

    return SalaryStats(
      month: monthKey,
      salary: salary,
      budget: budget,
      spent: spent,
      previousSalary: previousSalary,
      totalRecorded: total,
      monthsRecorded: count,
      highestSalary: highest,
      averageSalary: average,
      cumulativeSaved: cumulativeSaved,
      avgSavingsRatePct: avgSavingsRatePct,
      avgMonthlySpend: avgMonthlySpend,
      dayOfMonth: now.day,
      daysInMonth: daysInMonth,
      ccSpentThisMonth: ccByMonth[monthKey] ?? 0.0,
      ccDueThisMonth: ccByMonth[prevMonthKey] ?? 0.0,
    );
  }

  @override
  List<Object?> get props => [
        month,
        salary,
        budget,
        spent,
        previousSalary,
        totalRecorded,
        monthsRecorded,
        highestSalary,
        averageSalary,
        cumulativeSaved,
        avgSavingsRatePct,
        avgMonthlySpend,
        dayOfMonth,
        daysInMonth,
        ccSpentThisMonth,
        ccDueThisMonth,
      ];
}

/// Canonical 'YYYY-MM' month key for a [DateTime] (local).
String monthKeyOf(DateTime dt) =>
    '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}';

/// Human label for a 'YYYY-MM' key, e.g. '2026-06' -> 'June 2026'.
String monthKeyLabel(String key) {
  final parts = key.split('-');
  if (parts.length < 2) return key;
  final y = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (y == null || m == null || m < 1 || m > 12) return key;
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
  return '${names[m - 1]} $y';
}

/// Short label, e.g. '2026-06' -> "Jun '26".
String monthKeyShort(String key) {
  final parts = key.split('-');
  if (parts.length < 2) return key;
  final y = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (y == null || m == null || m < 1 || m > 12) return key;
  const names = [
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
  return "${names[m - 1]} '${(y % 100).toString().padLeft(2, '0')}";
}
