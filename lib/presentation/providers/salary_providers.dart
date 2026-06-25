import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/injection.dart';
import '../../domain/entities/salary_entities.dart';
import '../screens/expense/expense_screen.dart' show currentBudgetProvider;

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

/// Fully-computed [SalaryStats] for the current month, blending the in-hand
/// salary, the live budget and the DB-aggregated month-to-date spend.
final salaryStatsProvider = Provider<SalaryStats>((ref) {
  final history = ref.watch(salaryHistoryStreamProvider).valueOrNull ?? const [];
  final budget = ref.watch(currentBudgetProvider);
  final spent = ref.watch(currentMonthSpentProvider).valueOrNull ?? 0.0;

  final now = DateTime.now();
  final monthKey = monthKeyOf(now);

  double salary = 0;
  double? previousSalary;
  for (final e in history) {
    if (e.month == monthKey) {
      salary = e.amount;
    } else if (e.month.compareTo(monthKey) < 0 && previousSalary == null) {
      // history is desc, so the first older month is the previous recorded one
      previousSalary = e.amount;
    }
  }

  final amounts = history.map((e) => e.amount).toList();
  final total = amounts.fold<double>(0, (s, a) => s + a);
  final count = amounts.length;
  final highest = amounts.isEmpty
      ? 0.0
      : amounts.reduce((a, b) => a > b ? a : b);
  final average = count > 0 ? total / count : 0.0;

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
  );
});
