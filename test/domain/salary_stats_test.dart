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
  );
}

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
}
