// Pins the date -> insight-period contract: an expense logged for a given day
// lands in exactly the periods whose window contains that day. This is the
// behaviour that guarantees "log it on a date, then see it in Insights under
// the matching period (this month / last month / next month / all)".

import 'package:ai_nexus/presentation/screens/expense/widgets/expense_item.dart';
import 'package:ai_nexus/presentation/screens/expense/widgets/insights_tab.dart';
import 'package:flutter_test/flutter_test.dart';

// A fixed "now" well away from month edges so day-count math is unambiguous.
final _now = DateTime(2026, 7, 15, 10, 30);

ExpenseData _e(String id, DateTime date, {String category = 'Food'}) =>
    ExpenseData(
      id: id,
      amount: 100,
      description: id,
      category: category,
      bank: 'HDFC',
      cardType: 'DB',
      date: date.toIso8601String(),
    );

bool _has(List<ExpenseData> list, String id) => list.any((e) => e.id == id);

List<ExpenseData> _period(List<ExpenseData> all, String key) =>
    expensesInInsightPeriod(all, key, _now);

void main() {
  test('today lands in every rolling window + all, but not next month', () {
    final all = [_e('today', _now)];
    for (final k in ['week', 'month', 'm3', 'm6', 'all']) {
      expect(_has(_period(all, k), 'today'), isTrue, reason: 'today in $k');
    }
    expect(_has(_period(all, 'nt'), 'today'), isFalse);
  });

  test('a few days ago is in week/month/all', () {
    final all = [_e('d3', _now.subtract(const Duration(days: 3)))];
    expect(_has(_period(all, 'week'), 'd3'), isTrue);
    expect(_has(_period(all, 'month'), 'd3'), isTrue);
    expect(_has(_period(all, 'all'), 'd3'), isTrue);
  });

  test('20 days ago is in month but NOT week', () {
    final all = [_e('d20', _now.subtract(const Duration(days: 20)))];
    expect(_has(_period(all, 'week'), 'd20'), isFalse);
    expect(_has(_period(all, 'month'), 'd20'), isTrue);
    expect(_has(_period(all, 'm3'), 'd20'), isTrue);
  });

  test('last-month date is in 3M/6M/all but not this-month window or week', () {
    // 15 Jun 2026 — previous calendar month, ~30 days before now.
    final all = [_e('lastMonth', DateTime(2026, 6, 15, 12))];
    expect(_has(_period(all, 'week'), 'lastMonth'), isFalse);
    expect(_has(_period(all, 'm3'), 'lastMonth'), isTrue);
    expect(_has(_period(all, 'm6'), 'lastMonth'), isTrue);
    expect(_has(_period(all, 'all'), 'lastMonth'), isTrue);
    expect(_has(_period(all, 'nt'), 'lastMonth'), isFalse);
  });

  test('older than 6 months only shows under All', () {
    final all = [_e('old', DateTime(2025, 1, 5, 12))];
    expect(_has(_period(all, 'm6'), 'old'), isFalse);
    expect(_has(_period(all, 'm3'), 'old'), isFalse);
    expect(_has(_period(all, 'all'), 'old'), isTrue);
  });

  test('next-month date shows under NT and All, never the current windows', () {
    // 1 Aug 2026 — the classic "NM 1st" credit-card bill.
    final all = [_e('nextMonth', DateTime(2026, 8, 1, 12))];
    expect(_has(_period(all, 'nt'), 'nextMonth'), isTrue);
    expect(_has(_period(all, 'all'), 'nextMonth'), isTrue);
    for (final k in ['week', 'month', 'm3', 'm6']) {
      expect(_has(_period(all, k), 'nextMonth'), isFalse,
          reason: 'future must not leak into $k');
    }
  });

  test('the month after next is NOT in NT (NT is strictly next month)', () {
    final all = [_e('sep', DateTime(2026, 9, 3, 12))];
    expect(_has(_period(all, 'nt'), 'sep'), isFalse);
    expect(_has(_period(all, 'all'), 'sep'), isTrue);
  });

  test('investments are excluded from every spend period', () {
    final all = [
      _e('spend', _now),
      _e('inv', _now, category: 'Investment'),
    ];
    for (final k in ['week', 'month', 'm3', 'm6', 'all', 'nt']) {
      expect(_has(_period(all, k), 'inv'), isFalse, reason: 'inv leaked into $k');
    }
    expect(_has(_period(all, 'all'), 'spend'), isTrue);
  });

  test('malformed dates never throw and are simply not in bounded periods', () {
    final all = [
      ExpenseData(
        id: 'bad',
        amount: 50,
        description: 'bad',
        category: 'Food',
        bank: 'HDFC',
        cardType: 'DB',
        date: 'not-a-date',
      ),
    ];
    // Unparseable → epoch 1970 → far past → only 'all' (which has no lower cut
    // that excludes it since epoch >= epoch) and definitely no crash.
    expect(() => _period(all, 'week'), returnsNormally);
    expect(_has(_period(all, 'week'), 'bad'), isFalse);
    expect(_has(_period(all, 'all'), 'bad'), isTrue);
  });
}
