// Pure-math tests for the salary stats/trend domain models. These guard the
// percentage calculations, hike detection and the financial-health score so
// the standout stats UI can never display a wrong number.

import 'package:flutter_test/flutter_test.dart';

import 'package:ai_nexus/domain/entities/salary_entities.dart';

SalaryStats _stats({
  double salary = 0,
  double budget = 0,
  double spent = 0,
  double? previousSalary,
  double total = 0,
  int months = 0,
  double highest = 0,
  double average = 0,
  double cumulativeSaved = 0,
  double avgSavingsRatePct = 0,
  double avgMonthlySpend = 0,
  int dayOfMonth = 1,
  int daysInMonth = 30,
  double ccSpentThisMonth = 0,
  double ccDueThisMonth = 0,
}) {
  return SalaryStats(
    month: '2026-06',
    salary: salary,
    budget: budget,
    spent: spent,
    previousSalary: previousSalary,
    totalRecorded: total,
    monthsRecorded: months,
    highestSalary: highest,
    averageSalary: average,
    cumulativeSaved: cumulativeSaved,
    avgSavingsRatePct: avgSavingsRatePct,
    avgMonthlySpend: avgMonthlySpend,
    dayOfMonth: dayOfMonth,
    daysInMonth: daysInMonth,
    ccSpentThisMonth: ccSpentThisMonth,
    ccDueThisMonth: ccDueThisMonth,
  );
}

SalaryEntry _entry(String month, double amount) =>
    SalaryEntry(id: month, month: month, amount: amount, setAt: '');

void main() {
  group('SalaryStats percentages', () {
    test('spent/saved ratios are correct', () {
      final s = _stats(salary: 100000, spent: 40000);
      expect(s.saved, 60000);
      expect(s.spentPct, 40);
      expect(s.savedPct, 60);
    });

    test('budget used and budget-of-salary', () {
      final s = _stats(salary: 100000, budget: 50000, spent: 25000);
      expect(s.budgetUsedPct, 50);
      expect(s.budgetPctOfSalary, 50);
    });

    test('overspent is detected and saved goes negative', () {
      final s = _stats(salary: 50000, spent: 60000);
      expect(s.isOverspent, isTrue);
      expect(s.saved, -10000);
      expect(s.savedPct, -20);
    });

    test('over budget flag', () {
      final s = _stats(salary: 100000, budget: 20000, spent: 25000);
      expect(s.isOverBudget, isTrue);
    });

    test('no salary → safe zeros (no divide-by-zero)', () {
      final s = _stats(salary: 0, spent: 5000);
      expect(s.hasSalary, isFalse);
      expect(s.spentPct, 0);
      expect(s.savedPct, 0);
      expect(s.healthScore, 0);
    });
  });

  group('hike %', () {
    test('positive hike vs previous month', () {
      final s = _stats(salary: 110000, previousSalary: 100000);
      expect(s.hikePct, closeTo(10, 0.0001));
      expect(s.hikeAbs, 10000);
    });

    test('pay cut yields negative hike', () {
      final s = _stats(salary: 90000, previousSalary: 100000);
      expect(s.hikePct, closeTo(-10, 0.0001));
    });

    test('no previous month → null hike', () {
      final s = _stats(salary: 100000);
      expect(s.hikePct, isNull);
      expect(s.hikeAbs, isNull);
    });
  });

  group('health score', () {
    test('high savings + under budget scores high', () {
      final s = _stats(salary: 100000, budget: 60000, spent: 20000);
      // 80% saved (→56) + 67% budget headroom (→20) = 76 ("Healthy").
      expect(s.healthScore, greaterThanOrEqualTo(70));
    });

    test('near-perfect finances score in the excellent band', () {
      final s = _stats(salary: 100000, budget: 10000, spent: 2000);
      expect(s.healthScore, greaterThanOrEqualTo(80));
    });

    test('overspending scores low', () {
      final s = _stats(salary: 100000, budget: 40000, spent: 100000);
      expect(s.healthScore, lessThanOrEqualTo(10));
    });

    test('score is always clamped 0..100', () {
      final s = _stats(salary: 100000, spent: -50000); // pathological
      expect(s.healthScore, inInclusiveRange(0, 100));
    });
  });

  group('SalaryTrendItem', () {
    test('computes delta vs previous recorded month', () {
      const item = SalaryTrendItem(
        entry: SalaryEntry(
            id: '1', month: '2026-06', amount: 120000, setAt: ''),
        previousAmount: 100000,
      );
      expect(item.deltaAbs, 20000);
      expect(item.deltaPct, closeTo(20, 0.0001));
      expect(item.isHike, isTrue);
      expect(item.isCut, isFalse);
    });

    test('first ever month has null delta', () {
      const item = SalaryTrendItem(
        entry:
            SalaryEntry(id: '1', month: '2026-01', amount: 50000, setAt: ''),
        previousAmount: null,
      );
      expect(item.deltaPct, isNull);
      expect(item.isHike, isFalse);
    });
  });

  group('month key helpers', () {
    test('monthKeyOf formats with zero padding', () {
      expect(monthKeyOf(DateTime(2026, 3, 9)), '2026-03');
      expect(monthKeyOf(DateTime(2026, 12, 31)), '2026-12');
    });

    test('labels render human month names', () {
      expect(monthKeyLabel('2026-06'), 'June 2026');
      expect(monthKeyShort('2026-06'), "Jun '26");
    });

    test('invalid keys pass through gracefully', () {
      expect(monthKeyLabel('garbage'), 'garbage');
      expect(monthKeyLabel('2026-13'), '2026-13');
    });
  });

  group('this-month pace / projection', () {
    test('day-elapsed math, daily burn, projection mid-month', () {
      // ₹15,000 spent over 15 of 30 days → ₹1,000/day → ₹30,000 projected.
      final s = _stats(
          salary: 100000, spent: 15000, dayOfMonth: 15, daysInMonth: 30);
      expect(s.daysElapsed, 15);
      expect(s.daysRemaining, 15);
      expect(s.dailyBurnRate, 1000);
      expect(s.projectedSpend, 30000);
      expect(s.projectedSaved, 70000);
      expect(s.projectedOverBudget, isFalse);
    });

    test('projection flags an over-budget pace', () {
      // ₹20,000 in 10/30 days → ₹60,000 projected, budget ₹50,000 → over pace.
      final s = _stats(
          salary: 100000,
          budget: 50000,
          spent: 20000,
          dayOfMonth: 10,
          daysInMonth: 30);
      expect(s.projectedSpend, 60000);
      expect(s.projectedOverBudget, isTrue);
    });

    test('safe-to-spend per remaining day uses the budget as the cap', () {
      // budget 50k, spent 20k → 30k left over 15 remaining days → ₹2,000/day.
      final s = _stats(
          salary: 100000,
          budget: 50000,
          spent: 20000,
          dayOfMonth: 15,
          daysInMonth: 30);
      expect(s.safeToSpendPerDay, 2000);
    });

    test('safe-to-spend falls back to salary when no budget', () {
      // no budget → cap = salary. 80k left over 20 remaining days → ₹4,000/day.
      final s = _stats(
          salary: 100000, spent: 20000, dayOfMonth: 10, daysInMonth: 30);
      expect(s.safeToSpendPerDay, 4000);
    });

    test('safe-to-spend is zero once the cap is exhausted', () {
      final s = _stats(
          salary: 50000,
          budget: 40000,
          spent: 45000,
          dayOfMonth: 20,
          daysInMonth: 30);
      expect(s.safeToSpendPerDay, 0);
    });

    test('last day of month never divides by zero', () {
      final s = _stats(
          salary: 100000,
          budget: 50000,
          spent: 30000,
          dayOfMonth: 30,
          daysInMonth: 30);
      expect(s.daysRemaining, 0);
      // remaining ₹20,000 spread over a guarded single day.
      expect(s.safeToSpendPerDay, 20000);
      expect(s.dailyBurnRate, 1000);
    });
  });

  group('runway', () {
    test('months covered by lifetime savings at the average burn', () {
      final s = _stats(cumulativeSaved: 300000, avgMonthlySpend: 50000);
      expect(s.runwayMonths, closeTo(6, 0.0001));
    });

    test('no runway when there is no burn baseline or no savings', () {
      expect(_stats(cumulativeSaved: 300000, avgMonthlySpend: 0).runwayMonths,
          isNull);
      expect(_stats(cumulativeSaved: -1000, avgMonthlySpend: 50000).runwayMonths,
          isNull);
    });
  });

  group('credit-card repayment forecast', () {
    test('this month CC charges forecast a reduced next-month take-home', () {
      // ₹100k salary, ₹25k charged to credit this month → next month's bill.
      final s = _stats(salary: 100000, ccSpentThisMonth: 25000);
      expect(s.hasCreditCardActivity, isTrue);
      expect(s.nextMonthRepayment, 25000);
      expect(s.forecastNextMonthTakeHome, 75000);
      expect(s.ccPctOfSalary, closeTo(25, 0.0001));
    });

    test('last month CC bill reduces this month\'s real take-home', () {
      // ₹100k salary, ₹30k bill from last month landing now.
      final s = _stats(salary: 100000, ccDueThisMonth: 30000);
      expect(s.hasCreditCardActivity, isTrue);
      expect(s.effectiveTakeHomeThisMonth, 70000);
      // nothing charged this month yet → next month unaffected.
      expect(s.forecastNextMonthTakeHome, 100000);
    });

    test('both cycles: paying last month while building next month\'s bill', () {
      final s = _stats(
        salary: 100000,
        ccSpentThisMonth: 20000,
        ccDueThisMonth: 15000,
      );
      expect(s.effectiveTakeHomeThisMonth, 85000); // 100k - 15k due now
      expect(s.forecastNextMonthTakeHome, 80000); // 100k - 20k charged now
    });

    test('a bill larger than salary pushes the forecast negative', () {
      final s = _stats(salary: 50000, ccSpentThisMonth: 60000);
      expect(s.forecastNextMonthTakeHome, -10000);
      expect(s.ccPctOfSalary, closeTo(120, 0.0001));
    });

    test('ccLeavesNextMonthShort flags when bill drops pay below avg spend', () {
      // forecast take-home 60k < 70k average monthly spend → short next month.
      final s = _stats(
        salary: 100000,
        ccSpentThisMonth: 40000,
        avgMonthlySpend: 70000,
      );
      expect(s.ccLeavesNextMonthShort, isTrue);
    });

    test('ccLeavesNextMonthShort is false when forecast covers avg spend', () {
      final s = _stats(
        salary: 100000,
        ccSpentThisMonth: 10000,
        avgMonthlySpend: 70000,
      );
      expect(s.ccLeavesNextMonthShort, isFalse);
    });

    test('no CC activity → all forecast figures fall back to plain salary', () {
      final s = _stats(salary: 100000);
      expect(s.hasCreditCardActivity, isFalse);
      expect(s.forecastNextMonthTakeHome, 100000);
      expect(s.effectiveTakeHomeThisMonth, 100000);
      expect(s.ccPctOfSalary, 0);
      expect(s.ccLeavesNextMonthShort, isFalse);
    });

    test('no salary → ccPctOfSalary stays zero (no divide-by-zero)', () {
      final s = _stats(salary: 0, ccSpentThisMonth: 5000);
      expect(s.ccPctOfSalary, 0);
      expect(s.ccLeavesNextMonthShort, isFalse);
    });

    test('a due-now bill exceeding salary pushes real take-home negative', () {
      final s = _stats(salary: 40000, ccDueThisMonth: 55000);
      expect(s.effectiveTakeHomeThisMonth, -15000);
      // Still no this-month charge → next month is unaffected.
      expect(s.forecastNextMonthTakeHome, 40000);
    });

    test('ccLeavesNextMonthShort needs salary, a charge AND a burn baseline', () {
      // No avgMonthlySpend baseline → cannot conclude a shortfall.
      expect(
        _stats(salary: 100000, ccSpentThisMonth: 90000).ccLeavesNextMonthShort,
        isFalse,
      );
      // No charge this month → nothing to repay next month.
      expect(
        _stats(salary: 100000, avgMonthlySpend: 90000).ccLeavesNextMonthShort,
        isFalse,
      );
    });
  });

  group('SalaryStats.compute (pure aggregation)', () {
    final now = DateTime(2026, 6, 15); // mid-June, 30-day month
    // History is newest-first, as the repository emits it.
    final history = [
      _entry('2026-06', 100000),
      _entry('2026-05', 90000),
      _entry('2026-04', 80000),
    ];
    final spendByMonth = {
      '2026-06': 30000.0, // current, month-to-date
      '2026-05': 45000.0,
      '2026-04': 60000.0,
    };

    test('blends current salary, previous month, spend and budget', () {
      final s = SalaryStats.compute(
        history: history,
        budget: 70000,
        spent: 30000,
        spendByMonth: spendByMonth,
        now: now,
      );
      expect(s.month, '2026-06');
      expect(s.salary, 100000);
      expect(s.previousSalary, 90000);
      expect(s.spent, 30000);
      expect(s.budget, 70000);
      expect(s.hikePct, closeTo(11.111, 0.01));
      expect(s.monthsRecorded, 3);
      expect(s.totalRecorded, 270000);
      expect(s.highestSalary, 100000);
      expect(s.averageSalary, 90000);
      expect(s.dayOfMonth, 15);
      expect(s.daysInMonth, 30);
    });

    test('cumulative savings pairs each month with its spend', () {
      final s = SalaryStats.compute(
        history: history,
        budget: 0,
        spent: 30000,
        spendByMonth: spendByMonth,
        now: now,
      );
      // (100k-30k)+(90k-45k)+(80k-60k) = 70k+45k+20k = 135k.
      expect(s.cumulativeSaved, 135000);
      // savings rates: 70%, 50%, 25% → mean 48.333%.
      expect(s.avgSavingsRatePct, closeTo(48.333, 0.01));
      // avg monthly spend EXCLUDES the in-progress current month:
      // (45k + 60k) / 2 = 52.5k.
      expect(s.avgMonthlySpend, 52500);
      // runway = 135000 / 52500 ≈ 2.571.
      expect(s.runwayMonths, closeTo(2.571, 0.01));
    });

    test('first ever month: no previous, burn falls back to current month', () {
      final s = SalaryStats.compute(
        history: [_entry('2026-06', 100000)],
        budget: 0,
        spent: 30000,
        spendByMonth: const {'2026-06': 30000.0},
        now: now,
      );
      expect(s.previousSalary, isNull);
      expect(s.hikePct, isNull);
      expect(s.cumulativeSaved, 70000);
      // only the current month is known → it becomes the burn baseline.
      expect(s.avgMonthlySpend, 30000);
    });

    test('empty history → safe zeros, no salary, no divide-by-zero', () {
      final s = SalaryStats.compute(
        history: const [],
        budget: 0,
        spent: 0,
        spendByMonth: const {},
        now: now,
      );
      expect(s.hasSalary, isFalse);
      expect(s.salary, 0);
      expect(s.cumulativeSaved, 0);
      expect(s.avgSavingsRatePct, 0);
      expect(s.avgMonthlySpend, 0);
      expect(s.runwayMonths, isNull);
      expect(s.healthScore, 0);
    });

    test('current month has no salary yet (reads 0) but history is preserved',
        () {
      // No 2026-06 entry → current salary 0, but May/April stay recorded.
      final s = SalaryStats.compute(
        history: [_entry('2026-05', 90000), _entry('2026-04', 80000)],
        budget: 0,
        spent: 0,
        spendByMonth: const {'2026-05': 45000.0, '2026-04': 60000.0},
        now: now,
      );
      expect(s.salary, 0);
      expect(s.hasSalary, isFalse);
      expect(s.monthsRecorded, 2);
      expect(s.previousSalary, 90000);
    });

    test('ccByMonth maps current → next bill and previous → due now', () {
      // now = 2026-06-15 → prev calendar month is 2026-05.
      final s = SalaryStats.compute(
        history: history,
        budget: 0,
        spent: 30000,
        spendByMonth: spendByMonth,
        ccByMonth: const {
          '2026-06': 18000.0, // charged this month → due next month
          '2026-05': 12000.0, // last month's bill → due now
          '2026-04': 9000.0, // older, ignored
        },
        now: now,
      );
      expect(s.ccSpentThisMonth, 18000);
      expect(s.ccDueThisMonth, 12000);
      expect(s.forecastNextMonthTakeHome, 82000); // 100k - 18k
      expect(s.effectiveTakeHomeThisMonth, 88000); // 100k - 12k
    });

    test('prev-month rollover at a year boundary (January → previous Dec)', () {
      final s = SalaryStats.compute(
        history: [_entry('2026-01', 100000)],
        budget: 0,
        spent: 0,
        spendByMonth: const {'2026-01': 0.0},
        ccByMonth: const {'2025-12': 7000.0},
        now: DateTime(2026, 1, 10),
      );
      expect(s.ccDueThisMonth, 7000);
    });

    test('CC charged before this month\'s salary is entered does not crash', () {
      // No 2026-06 salary entry yet, but a CC charge already landed this month.
      final s = SalaryStats.compute(
        history: const [],
        budget: 0,
        spent: 5000,
        spendByMonth: const {'2026-06': 5000.0},
        ccByMonth: const {'2026-06': 5000.0},
        now: now,
      );
      expect(s.hasSalary, isFalse);
      expect(s.ccSpentThisMonth, 5000);
      // salary 0 → forecast is simply the negative bill; no divide-by-zero.
      expect(s.forecastNextMonthTakeHome, -5000);
      expect(s.ccPctOfSalary, 0);
    });

    test('no ccByMonth → forecast figures default to zero CC', () {
      final s = SalaryStats.compute(
        history: history,
        budget: 0,
        spent: 30000,
        spendByMonth: spendByMonth,
        now: now,
      );
      expect(s.ccSpentThisMonth, 0);
      expect(s.ccDueThisMonth, 0);
      expect(s.hasCreditCardActivity, isFalse);
    });

    test('daysInMonth handles February in a leap year', () {
      final s = SalaryStats.compute(
        history: const [],
        budget: 0,
        spent: 0,
        spendByMonth: const {},
        now: DateTime(2028, 2, 10), // 2028 is a leap year
      );
      expect(s.daysInMonth, 29);
    });
  });
}
