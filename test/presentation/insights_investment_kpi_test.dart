// Unit tests for the Insights tab's Investment Portfolio KPI math:
//   • investmentCumulativeMonthlySeries — month bucketing, ascending sort,
//     running cumulative sum, order-independence, malformed-date safety.
//   • compactInr — INR short-form (K/L/Cr) used by the card's secondary stats,
//     including negatives and the sub-1000 passthrough.
//
// These are the pure, presentation-layer computations that power the portfolio
// card; testing them directly keeps the card itself a thin renderer.

import 'package:flutter_test/flutter_test.dart';

import 'package:ai_nexus/presentation/screens/expense/widgets/expense_item.dart';
import 'package:ai_nexus/presentation/screens/expense/widgets/insights_tab.dart';

ExpenseData _inv({
  required double amount,
  required String date,
  String category = 'Investment',
}) =>
    ExpenseData(
      id: 'i-$date-$amount',
      amount: amount,
      description: 'inv',
      category: category,
      bank: 'HDFC',
      cardType: 'CC',
      date: date,
    );

void main() {
  group('investmentCumulativeMonthlySeries', () {
    test('empty input → empty series (sparkline skipped)', () {
      expect(investmentCumulativeMonthlySeries(const []), isEmpty);
    });

    test('single month → single cumulative point', () {
      final series = investmentCumulativeMonthlySeries([
        _inv(amount: 5000, date: '2026-06-03T10:00:00.000'),
        _inv(amount: 2500, date: '2026-06-20T10:00:00.000'),
      ]);
      expect(series, [7500]);
    });

    test('multiple months produce an ascending cumulative curve', () {
      final series = investmentCumulativeMonthlySeries([
        _inv(amount: 1000, date: '2026-04-10T10:00:00.000'),
        _inv(amount: 2000, date: '2026-05-10T10:00:00.000'),
        _inv(amount: 3000, date: '2026-06-10T10:00:00.000'),
      ]);
      // Running sum: 1000 → 3000 → 6000.
      expect(series, [1000, 3000, 6000]);
    });

    test('is order-independent (sorts months ascending before summing)', () {
      final shuffled = investmentCumulativeMonthlySeries([
        _inv(amount: 3000, date: '2026-06-10T10:00:00.000'),
        _inv(amount: 1000, date: '2026-04-10T10:00:00.000'),
        _inv(amount: 2000, date: '2026-05-10T10:00:00.000'),
      ]);
      expect(shuffled, [1000, 3000, 6000]);
    });

    test('cumulative curve is monotonically non-decreasing for positive sums',
        () {
      final series = investmentCumulativeMonthlySeries([
        for (var m = 1; m <= 12; m++)
          _inv(amount: 1000.0 * m, date: '2026-${m.toString().padLeft(2, '0')}-15T00:00:00.000'),
      ]);
      expect(series, hasLength(12));
      for (var i = 1; i < series.length; i++) {
        expect(series[i] >= series[i - 1], isTrue);
      }
      // Total cumulative = sum 1000*(1..12) = 1000*78 = 78000.
      expect(series.last, 78000);
    });

    test('malformed / short dates never throw and still bucket', () {
      final series = investmentCumulativeMonthlySeries([
        _inv(amount: 100, date: ''), // empty → own bucket
        _inv(amount: 200, date: 'xx'), // short → own bucket
        _inv(amount: 300, date: '2026-06-10T10:00:00.000'),
      ]);
      // Three distinct buckets; final cumulative must equal the grand total.
      expect(series, hasLength(3));
      expect(series.last, 600);
    });
  });

  group('compactInr', () {
    test('sub-1000 falls through to full currency formatting', () {
      expect(compactInr(0), contains('0'));
      expect(compactInr(999), contains('999'));
    });

    test('thousands → K', () {
      expect(compactInr(1500), '₹1.5K');
      expect(compactInr(99000), '₹99.0K');
    });

    test('lakhs → L', () {
      expect(compactInr(150000), '₹1.5L');
      expect(compactInr(2500000), '₹25.0L'); // 25 < 100 → 1 decimal
      expect(compactInr(20000000), '₹2.0Cr'); // boundary into Cr
    });

    test('crores → Cr', () {
      expect(compactInr(15000000), '₹1.5Cr');
    });

    test('negatives keep their sign', () {
      expect(compactInr(-1500), '-₹1.5K');
      expect(compactInr(-15000000), '-₹1.5Cr');
    });
  });
}
