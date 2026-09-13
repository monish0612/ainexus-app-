import 'package:ai_nexus/core/services/expense_pace_metrics.dart';
import 'package:flutter_test/flutter_test.dart';

PaceTxn _t({
  required double amount,
  required DateTime date,
  String category = 'Food',
  String description = 'x',
}) =>
    PaceTxn(
      amount: amount,
      category: category,
      date: date,
      description: description,
    );

void main() {
  group('MonthPace', () {
    test('day 1 expected-by-now is budget / lengthOfMonth', () {
      final today = DateTime(2026, 6, 1);
      final pace = ExpensePaceMetrics.monthPace(
        budget: 30000,
        monthSpent: 0,
        today: today,
      );
      expect(pace.lengthOfMonth, 30);
      expect(pace.dayOfMonth, 1);
      expect(pace.remainingDays, 30);
      expect(pace.expectedByNow, closeTo(1000, 0.01));
      expect(pace.safeDaily, closeTo(1000, 0.01));
      expect(pace.status, PaceStatus.onTrack);
    });

    test('mid-month expected is budget × day / length', () {
      final today = DateTime(2026, 6, 15);
      final pace = ExpensePaceMetrics.monthPace(
        budget: 30000,
        monthSpent: 14000,
        today: today,
      );
      expect(pace.expectedByNow, closeTo(15000, 0.01));
      expect(pace.remainingDays, 16);
      expect(pace.leftover, 16000);
      expect(pace.safeDaily, closeTo(16000 / 16, 0.01));
      expect(pace.status, PaceStatus.onTrack);
    });

    test('last day remaining days is 1 and expected equals budget', () {
      final today = DateTime(2026, 6, 30);
      final pace = ExpensePaceMetrics.monthPace(
        budget: 10000,
        monthSpent: 9000,
        today: today,
      );
      expect(pace.lengthOfMonth, 30);
      expect(pace.dayOfMonth, 30);
      expect(pace.remainingDays, 1);
      expect(pace.expectedByNow, 10000);
      expect(pace.safeDaily, 1000);
      expect(pace.status, PaceStatus.onTrack);
    });

    test('zero budget skips pace and zeros expected / safe daily', () {
      final pace = ExpensePaceMetrics.monthPace(
        budget: 0,
        monthSpent: 500,
        today: DateTime(2026, 6, 15),
      );
      expect(pace.hasBudget, isFalse);
      expect(pace.expectedByNow, 0);
      expect(pace.safeDaily, 0);
      expect(pace.paceThreshold, 0);
      expect(pace.status, PaceStatus.none);
    });

    test('over budget is over plan even if also ahead of pace', () {
      final pace = ExpensePaceMetrics.monthPace(
        budget: 10000,
        monthSpent: 10001,
        today: DateTime(2026, 6, 15),
      );
      expect(pace.status, PaceStatus.overPlan);
      expect(pace.leftover, closeTo(-1, 0.01));
      expect(pace.safeDaily, 0);
    });

    test('ahead of pace uses max(8% of budget, ₹100)', () {
      // June 15: expected = 10000 * 15/30 = 5000. Threshold = max(800, 100) = 800.
      const budget = 10000.0;
      final today = DateTime(2026, 6, 15);

      final onEdge = ExpensePaceMetrics.monthPace(
        budget: budget,
        monthSpent: 5800,
        today: today,
      );
      expect(paceThresholdOf(onEdge), 800);
      expect(onEdge.status, PaceStatus.onTrack,
          reason: 'spent − expected == 800 is not strictly over the floor');

      final ahead = ExpensePaceMetrics.monthPace(
        budget: budget,
        monthSpent: 5800.01,
        today: today,
      );
      expect(ahead.status, PaceStatus.aheadOfPace);

      // Tiny budget: 8% = 4, so floor is ₹100.
      final small = ExpensePaceMetrics.monthPace(
        budget: 50,
        monthSpent: 26,
        today: DateTime(2026, 6, 15),
      );
      expect(small.paceThreshold, 100);
      expect(small.expectedByNow, closeTo(25, 0.01));
      expect(small.status, PaceStatus.onTrack,
          reason: 'delta 1 is under the ₹100 floor');
    });

    test('remainingDaysInclusive includes today and never returns 0', () {
      expect(
        ExpensePaceMetrics.remainingDaysInclusive(DateTime(2026, 6, 15)),
        16,
      );
      expect(
        ExpensePaceMetrics.remainingDaysInclusive(DateTime(2026, 6, 30)),
        1,
      );
    });

    test('remainingSentence uses leftover / remaining days', () {
      final pace = ExpensePaceMetrics.monthPace(
        budget: 30000,
        monthSpent: 10000,
        today: DateTime(2026, 6, 15),
      );
      expect(pace.remainingSentence, contains('You can spend'));
      expect(pace.remainingSentence, contains('16 more days'));
      expect(pace.todayFraction, closeTo(15 / 30, 0.001));
    });
  });

  group('HeatDay', () {
    test('intensity is 0–1 vs the hottest spend day; future days grey', () {
      final today = DateTime(2026, 6, 15);
      final days = ExpensePaceMetrics.heatMonth(
        expenses: [
          _t(amount: 100, date: DateTime(2026, 6, 1)),
          _t(amount: 200, date: DateTime(2026, 6, 10)),
          _t(amount: 50, date: DateTime(2026, 6, 10)),
          _t(amount: 999, date: DateTime(2026, 6, 20)),
        ],
        month: today,
        today: today,
      );
      expect(days, hasLength(30));
      expect(days.first.date.day, 1);
      expect(days.last.date.day, 30);

      final d1 = days[0];
      final d10 = days[9];
      final d15 = days[14];
      final d20 = days[19];

      expect(d1.spent, 100);
      expect(d1.intensity, closeTo(100 / 250, 0.001));
      expect(d10.spent, 250);
      expect(d10.intensity, 1);
      expect(d15.isToday, isTrue);
      expect(d15.isFuture, isFalse);
      expect(d20.isFuture, isTrue);
      expect(d20.spent, 0);
      expect(d20.intensity, 0);
    });

    test('Investment and Loan days are excluded from heat', () {
      final today = DateTime(2026, 6, 10);
      final days = ExpensePaceMetrics.heatMonth(
        expenses: [
          _t(amount: 200, date: DateTime(2026, 6, 1), category: 'Food'),
          _t(
            amount: 9999,
            date: DateTime(2026, 6, 1),
            category: 'Investment',
          ),
          _t(amount: 8888, date: DateTime(2026, 6, 2), category: 'Loan'),
        ],
        month: today,
        today: today,
      );
      expect(days[0].spent, 200);
      expect(days[0].intensity, 1);
      expect(days[1].spent, 0);
      expect(days[1].intensity, 0);
    });
  });

  group('RangeFacts', () {
    test('period vs previous matching range respects ₹100 / 5% floors', () {
      final now = DateTime(2026, 6, 15);
      final quiet = ExpensePaceMetrics.rangeFacts(
        current: [_t(amount: 104, date: now)],
        previous: [_t(amount: 100, date: DateTime(2026, 5, 15))],
        now: now,
      );
      expect(
        quiet.all.any((f) => f.kind == RangeFactKind.vsPrevious),
        isFalse,
        reason: '₹4 / 4% is under both floors',
      );

      final loud = ExpensePaceMetrics.rangeFacts(
        current: [_t(amount: 2000, date: now)],
        previous: [_t(amount: 1000, date: DateTime(2026, 5, 15))],
        now: now,
      );
      expect(loud.primary!.kind, RangeFactKind.vsPrevious);
      expect(loud.primary!.delta, 1000);
    });

    test('Investment and Loan are excluded from range totals', () {
      final now = DateTime(2026, 6, 15);
      final facts = ExpensePaceMetrics.rangeFacts(
        current: [
          _t(amount: 500, date: now, category: 'Food'),
          _t(amount: 8000, date: now, category: 'Investment'),
          _t(amount: 4000, date: now, category: 'Loan'),
        ],
        previous: [_t(amount: 400, date: DateTime(2026, 5, 15))],
        now: now,
      );
      expect(facts.primary!.kind, RangeFactKind.vsPrevious);
      expect(facts.primary!.delta, 100);
    });

    test('top-category share and top-3 concentration fill later slots', () {
      final now = DateTime(2026, 6, 15);
      final facts = ExpensePaceMetrics.rangeFacts(
        current: [
          _t(amount: 700, date: now, category: 'Food'),
          _t(amount: 200, date: now, category: 'Fuel'),
          _t(amount: 100, date: now, category: 'Bills'),
        ],
        previous: [
          _t(amount: 700, date: DateTime(2026, 5, 1), category: 'Food'),
          _t(amount: 200, date: DateTime(2026, 5, 1), category: 'Fuel'),
          _t(amount: 100, date: DateTime(2026, 5, 1), category: 'Bills'),
        ],
        now: now,
      );
      expect(
        facts.all.any((f) => f.kind == RangeFactKind.vsPrevious),
        isFalse,
      );
      expect(facts.primary!.kind, RangeFactKind.topCategoryShare);
      expect(facts.primary!.category, 'Food');
      expect(facts.primary!.percent, closeTo(70, 0.01));
      expect(facts.secondary!.kind, RangeFactKind.top3Concentration);
      expect(facts.secondary!.percent, closeTo(100, 0.01));
    });
  });

  group('previousMatchingTimeRange', () {
    test('shifts an equal-length window immediately before current', () {
      final start = DateTime(2026, 6, 8);
      final end = DateTime(2026, 6, 15);
      final prev = ExpensePaceMetrics.previousMatchingTimeRange(
        start: start,
        end: end,
      );
      expect(prev.start, DateTime(2026, 6, 1));
      expect(prev.end, start);
    });
  });

  group('historicCalendarBars', () {
    test('pads 3/6/12 calendar months oldest-first from monthlyTrend map', () {
      final now = DateTime(2026, 6, 15);
      final bars = ExpensePaceMetrics.historicCalendarBars(
        monthTotals: {'2026-06': 900, '2026-05': 400, '2026-01': 50},
        months: 6,
        now: now,
      );
      expect(bars, hasLength(6));
      expect(bars.map((b) => b.monthKey).toList(), [
        '2026-01',
        '2026-02',
        '2026-03',
        '2026-04',
        '2026-05',
        '2026-06',
      ]);
      expect(bars.first.total, 50);
      expect(bars[1].total, 0);
      expect(bars.last.total, 900);
    });
  });

  group('topMerchants', () {
    test('groups spend-only by description', () {
      final list = ExpensePaceMetrics.topMerchants([
        _t(amount: 100, date: DateTime(2026, 6, 1), description: 'Swiggy'),
        _t(amount: 40, date: DateTime(2026, 6, 2), description: 'Swiggy'),
        _t(amount: 80, date: DateTime(2026, 6, 3), description: 'Uber'),
        _t(
          amount: 5000,
          date: DateTime(2026, 6, 4),
          description: 'Mutual Fund',
          category: 'Investment',
        ),
      ]);
      expect(list.first.name, 'Swiggy');
      expect(list.first.total, 140);
      expect(list.first.count, 2);
      expect(list.any((m) => m.name == 'Mutual Fund'), isFalse);
    });
  });
}

double paceThresholdOf(MonthPace pace) => pace.paceThreshold;
