import 'package:ai_nexus/core/services/expense_composition.dart';
import 'package:ai_nexus/core/services/expense_pace_metrics.dart';
import 'package:flutter_test/flutter_test.dart';

CompositionTxn _t({
  required double amount,
  required DateTime date,
  String category = 'Food',
  String cardType = 'DB',
}) =>
    CompositionTxn(
      amount: amount,
      category: category,
      cardType: cardType,
      date: date,
    );

void main() {
  group('ExpenseComposition.ofMonth', () {
    test('splits cash / debit / credit and surfaces moved Investment+Loan', () {
      final now = DateTime(2026, 9, 11);
      final c = ExpenseComposition.ofMonth(
        txns: [
          _t(amount: 100, date: now, cardType: 'Cash'),
          _t(amount: 200, date: now, cardType: 'DB'),
          _t(amount: 300, date: now, cardType: 'Credit Card'),
          _t(
            amount: 5000,
            date: now,
            category: 'Investment',
            cardType: 'CC',
          ),
          _t(
            amount: 1000,
            date: now,
            category: 'Loan',
            cardType: 'DB',
          ),
          // previous month spend
          _t(amount: 400, date: DateTime(2026, 8, 20), cardType: 'Cash'),
        ],
        now: now,
      );
      expect(c.cash, 100);
      expect(c.debit, 200);
      expect(c.credit, 300);
      expect(c.spendTotal, 600);
      expect(c.moved, 6000);
      expect(c.previousMonthSpend, 400);
      expect(c.momIndex, closeTo(150, 0.01));
    });

    test('ignores other months for the live buckets', () {
      final now = DateTime(2026, 9, 11);
      final c = ExpenseComposition.ofMonth(
        txns: [
          _t(amount: 90, date: DateTime(2026, 7, 1)),
          _t(amount: 50, date: DateTime(2026, 10, 1)),
        ],
        now: now,
      );
      expect(c.spendTotal, 0);
      expect(c.moved, 0);
      expect(c.momIndex, isNull);
    });

    test('completed-month average skips current month and sub-floor zeros', () {
      final now = DateTime(2026, 9, 11);
      final c = ExpenseComposition.ofMonth(
        txns: [
          _t(amount: 500, date: DateTime(2026, 9, 5)), // current — skip
          _t(amount: 50, date: DateTime(2026, 8, 1)), // below floor
          _t(amount: 200, date: DateTime(2026, 7, 1)),
          _t(amount: 400, date: DateTime(2026, 6, 1)),
        ],
        now: now,
      );
      expect(c.completedMonthAverage, 300);
    });
  });

  group('pieSlices', () {
    test('keeps a 2% Medical slice named — the tracker-circle bug', () {
      // Food ₹9,800 + Medical ₹200 is 2% — the old 3% collapse hid Medical
      // as synthetic "Other" after the user recategorized an SMS debit.
      final slices = ExpenseComposition.pieSlices({
        'Food': 9800,
        'Medical': 200,
      });
      expect(slices.map((s) => s.category), ['Food', 'Medical']);
      expect(slices.any((s) => s.isOther), isFalse);
      expect(slices.last.total, 200);
      expect(slices.last.pct, closeTo(2, 0.05));
      expect(slices.map((s) => s.total).fold<double>(0, (a, b) => a + b), 10000);
    });

    test('real Others stays Others, not the overflow Other bucket', () {
      final slices = ExpenseComposition.pieSlices({
        'Food': 970,
        'Others': 30,
      });
      expect(slices.map((s) => s.category), ['Food', 'Others']);
      expect(slices.singleWhere((s) => s.category == 'Others').isOther, isFalse);
    });

    test('Others → Medical is a named Medical slice, not Other', () {
      final before = ExpenseComposition.pieSlices({
        'Food': 9000,
        'Others': 200,
      });
      expect(before.map((s) => s.category), ['Food', 'Others']);

      final after = ExpenseComposition.pieSlices({
        'Food': 9000,
        'Medical': 200,
      });
      expect(after.map((s) => s.category), ['Food', 'Medical']);
      expect(after.any((s) => s.category == 'Other' || s.isOther), isFalse);
    });

    test('empty / zero totals produce no slices', () {
      expect(ExpenseComposition.pieSlices({}), isEmpty);
      expect(ExpenseComposition.pieSlices({'Food': 0, 'Bills': 0}), isEmpty);
    });

    test('investment is not this helper\'s job — caller must exclude it', () {
      final slices = ExpenseComposition.pieSlices({'Food': 100, 'Investment': 5000});
      expect(slices.map((s) => s.category), ['Investment', 'Food']);
    });

    test('keeps up to eight named categories; 9th+ collapse into Other', () {
      final slices = ExpenseComposition.pieSlices({
        'Food': 200,
        'Bills': 180,
        'Transport': 160,
        'Shopping': 150,
        'Grocery': 140,
        'Travel': 120,
        'Fuel': 110,
        'Medical': 100,
        'Pets': 90,
      });
      expect(slices.where((s) => !s.isOther), hasLength(8));
      expect(slices.last.isOther, isTrue);
      expect(slices.last.category, 'Other');
      expect(slices.last.total, 90);
      expect(slices.any((s) => s.category == 'Medical'), isTrue);
    });

    test('equal amounts keep both names, sorted alphabetically', () {
      final slices = ExpenseComposition.pieSlices({
        'Medical': 100,
        'Food': 100,
      });
      expect(slices.map((s) => s.category), ['Food', 'Medical']);
      expect(slices.every((s) => !s.isOther), isTrue);
    });
  });

  group('cardType aliases', () {
    test('DB and debit map together; CC and credit map together', () {
      expect(ExpenseComposition.bucketFor('DB'), CardSpendBucket.debit);
      expect(ExpenseComposition.bucketFor('Debit Card'), CardSpendBucket.debit);
      expect(ExpenseComposition.bucketFor('CC'), CardSpendBucket.credit);
      expect(ExpenseComposition.bucketFor('Cash'), CardSpendBucket.cash);
    });
  });

  group('kBudgetAtRiskRatio', () {
    test('is 75%', () {
      expect(kBudgetAtRiskRatio, 0.75);
      expect(
        ExpensePaceMetrics.isAtRisk(spent: 74, budget: 100),
        isFalse,
      );
      expect(
        ExpensePaceMetrics.isAtRisk(spent: 75, budget: 100),
        isTrue,
      );
      expect(
        ExpensePaceMetrics.isAtRisk(spent: 100, budget: 100),
        isFalse,
      );
    });
  });
}
