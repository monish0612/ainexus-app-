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
