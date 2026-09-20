import 'package:flutter_test/flutter_test.dart';

import 'package:ai_nexus/core/services/expense_widget_service.dart';
import 'package:ai_nexus/core/theme/app_colors.dart';
import 'package:ai_nexus/domain/entities/expense_entities.dart';

/// Unit tests for [ExpenseWidgetService.computeWidgetData] — the pure expense
/// aggregation behind the home-screen widget. No SharedPreferences / channels.
void main() {
  // A fixed "now" so the today/month windows are deterministic.
  final now = DateTime(2026, 6, 29, 14, 30); // Mon 29 Jun 2026

  Expense exp({
    required double amount,
    required String date,
    String category = 'Food',
    String id = 'x',
  }) =>
      Expense(
        id: id,
        amount: amount,
        description: 'd',
        category: category,
        bank: 'CASH',
        cardType: 'Cash',
        date: date,
        isManualCategory: false,
      );

  group('today window', () {
    test('sums only today, exclusive of tomorrow / before today', () {
      final data = ExpenseWidgetService.computeWidgetData(
        expenses: [
          exp(amount: 100, date: '2026-06-29T09:00:00'), // today
          exp(amount: 50, date: '2026-06-29T23:59:59'), // today
          exp(amount: 999, date: '2026-06-30T00:00:00'), // tomorrow → out
          exp(amount: 7, date: '2026-06-28T23:59:59'), // yesterday → out
        ],
        now: now,
      );
      expect(data.todayTotal, 150);
      expect(data.todayCount, 2);
    });

    test('yesterday afternoon is not today', () {
      final data = ExpenseWidgetService.computeWidgetData(
        expenses: [
          exp(amount: 2890, date: '2026-09-16T13:37:00'),
          exp(amount: 75, date: '2026-09-16T12:31:00', id: 'y'),
        ],
        now: DateTime(2026, 9, 17, 13, 29),
      );
      expect(data.todayTotal, 0);
      expect(data.todayCount, 0);
    });

    test('date-only string at today midnight counts as today', () {
      final data = ExpenseWidgetService.computeWidgetData(
        expenses: [exp(amount: 80, date: '2026-06-29')],
        now: now,
      );
      expect(data.todayCount, 1);
      expect(data.todayTotal, 80);
    });
  });

  group('month window + count', () {
    test('sums from the 1st; excludes prior month', () {
      final data = ExpenseWidgetService.computeWidgetData(
        expenses: [
          exp(amount: 100, date: '2026-06-01T00:00:00'),
          exp(amount: 200, date: '2026-06-15T12:00:00'),
          exp(amount: 300, date: '2026-06-29T09:00:00'),
          exp(amount: 999, date: '2026-05-31T23:59:59'), // last month → out
        ],
        now: now,
      );
      expect(data.monthSpent, 600);
      expect(data.monthCount, 3);
    });
  });

  group('investment exclusion', () {
    test('investments never count toward today/month/top-category', () {
      final data = ExpenseWidgetService.computeWidgetData(
        expenses: [
          exp(amount: 500, date: '2026-06-29T09:00:00', category: 'Food'),
          exp(
            amount: 100000,
            date: '2026-06-29T09:00:00',
            category: kInvestmentCategory,
          ),
        ],
        now: now,
      );
      expect(data.todayTotal, 500);
      expect(data.todayCount, 1);
      expect(data.monthSpent, 500);
      expect(data.topCatName, 'Food');
    });
  });

  group('malformed data is skipped, never throws', () {
    test('unparseable dates are ignored', () {
      final data = ExpenseWidgetService.computeWidgetData(
        expenses: [
          exp(amount: 100, date: '2026-06-29T09:00:00'),
          exp(amount: 999, date: 'not-a-date'),
          exp(amount: 999, date: ''),
        ],
        now: now,
      );
      expect(data.todayTotal, 100);
      expect(data.monthCount, 1);
    });

    test('empty list yields a clean zero snapshot', () {
      final data = ExpenseWidgetService.computeWidgetData(
        expenses: const [],
        now: now,
      );
      expect(data.todayTotal, 0);
      expect(data.todayCount, 0);
      expect(data.monthSpent, 0);
      expect(data.monthCount, 0);
      expect(data.topCatName, '');
      expect(data.topCatEmoji, '');
      expect(data.topCatAmount, 0);
      expect(data.topCatColor, '');
      expect(data.pieSlices, isEmpty);
    });
  });

  group('top category', () {
    test('picks the biggest month spend with correct emoji + hex color', () {
      final data = ExpenseWidgetService.computeWidgetData(
        expenses: [
          exp(amount: 300, date: '2026-06-10', category: 'Food'),
          exp(amount: 250, date: '2026-06-12', category: 'Food'), // Food = 550
          exp(amount: 500, date: '2026-06-15', category: 'Shopping'),
          exp(amount: 100, date: '2026-06-20', category: 'Transport'),
        ],
        now: now,
      );
      expect(data.topCatName, 'Food');
      expect(data.topCatAmount, 550);
      expect(data.topCatEmoji, AppColors.categoryIcons['Food']);
      // #RRGGBB, six upper-hex digits.
      expect(data.topCatColor, matches(r'^#[0-9A-F]{6}$'));
      final expected =
          '#${AppColors.categoryColors['Food']!.toARGB32().toRadixString(16).substring(2).toUpperCase()}';
      expect(data.topCatColor, expected);
    });

    test('blank category is bucketed as Others', () {
      final data = ExpenseWidgetService.computeWidgetData(
        expenses: [exp(amount: 42, date: '2026-06-10', category: '   ')],
        now: now,
      );
      expect(data.topCatName, 'Others');
      expect(data.topCatEmoji, AppColors.categoryIcons['Others']);
    });

    test('unknown category still resolves with a fallback emoji/color', () {
      final data = ExpenseWidgetService.computeWidgetData(
        expenses: [exp(amount: 42, date: '2026-06-10', category: 'Crypto')],
        now: now,
      );
      expect(data.topCatName, 'Crypto');
      expect(data.topCatEmoji, '📦');
      expect(data.topCatColor, matches(r'^#[0-9A-F]{6}$'));
    });

    test('recategorizing a month of Others to Medical updates top category', () {
      final before = ExpenseWidgetService.computeWidgetData(
        expenses: [exp(amount: 200, date: '2026-06-29T09:00:00', category: 'Others')],
        now: now,
      );
      expect(before.topCatName, 'Others');

      final after = ExpenseWidgetService.computeWidgetData(
        expenses: [exp(amount: 200, date: '2026-06-29T09:00:00', category: 'Medical')],
        now: now,
      );
      expect(after.topCatName, 'Medical');
      expect(after.topCatAmount, 200);
      expect(after.topCatEmoji, AppColors.categoryIcons['Medical']);
      expect(after.todayTotal, 200);
    });
  });

  group('month boundary "now"', () {
    test('on the 1st, only the 1st is in-month', () {
      final firstOfMonth = DateTime(2026, 7, 1, 8, 0);
      final data = ExpenseWidgetService.computeWidgetData(
        expenses: [
          exp(amount: 100, date: '2026-07-01T07:00:00'), // in month + today
          exp(amount: 999, date: '2026-06-30T23:59:59'), // prev month → out
        ],
        now: firstOfMonth,
      );
      expect(data.monthSpent, 100);
      expect(data.todayTotal, 100);
    });

    test('next calendar month is excluded from this month', () {
      final data = ExpenseWidgetService.computeWidgetData(
        expenses: [
          exp(amount: 100, date: '2026-06-29T09:00:00'),
          exp(amount: 999, date: '2026-07-01T00:00:00'),
        ],
        now: now,
      );
      expect(data.monthSpent, 100);
    });
  });

  group('spend mix pie', () {
    test('ranks month categories and keeps four or fewer without Other', () {
      final data = ExpenseWidgetService.computeWidgetData(
        expenses: [
          exp(amount: 300, date: '2026-06-10', category: 'Food'),
          exp(amount: 250, date: '2026-06-12', category: 'Food'),
          exp(amount: 500, date: '2026-06-15', category: 'Shopping'),
          exp(amount: 100, date: '2026-06-20', category: 'Transport'),
        ],
        now: now,
      );
      expect(data.pieSlices.map((s) => s.name).toList(), ['Food', 'Shopping', 'Transport']);
      expect(data.pieSlices.map((s) => s.amount).toList(), [550, 500, 100]);
      expect(data.pieSlices.first.emoji, AppColors.categoryIcons['Food']);
      expect(data.pieSlices.first.color, data.topCatColor);
    });

    test('fifth category and beyond collapse into Other', () {
      final data = ExpenseWidgetService.computeWidgetData(
        expenses: [
          exp(amount: 500, date: '2026-06-02', category: 'Food'),
          exp(amount: 400, date: '2026-06-03', category: 'Shopping'),
          exp(amount: 300, date: '2026-06-04', category: 'Transport'),
          exp(amount: 200, date: '2026-06-05', category: 'Bills'),
          exp(amount: 50, date: '2026-06-06', category: 'Medical'),
          exp(amount: 25, date: '2026-06-07', category: 'Entertainment'),
        ],
        now: now,
      );
      expect(data.pieSlices, hasLength(4));
      expect(data.pieSlices.map((s) => s.name).toList(),
          ['Food', 'Shopping', 'Transport', 'Other']);
      expect(data.pieSlices.last.amount, 275); // Bills + Medical + Entertainment
      expect(data.pieSlices.last.emoji, AppColors.categoryIcons['Others']);
    });

    test('exactly four categories are shown in full', () {
      final slices = ExpenseWidgetService.buildPieSlices({
        'Food': 40,
        'Shopping': 30,
        'Transport': 20,
        'Bills': 10,
      });
      expect(slices.map((s) => s.name).toList(),
          ['Food', 'Shopping', 'Transport', 'Bills']);
    });

    test('investments never appear as a pie slice', () {
      final data = ExpenseWidgetService.computeWidgetData(
        expenses: [
          exp(amount: 80, date: '2026-06-10', category: 'Food'),
          exp(
            amount: 9000,
            date: '2026-06-10',
            category: kInvestmentCategory,
          ),
        ],
        now: now,
      );
      expect(data.pieSlices, hasLength(1));
      expect(data.pieSlices.single.name, 'Food');
    });

    test('loans never appear as a pie slice', () {
      final data = ExpenseWidgetService.computeWidgetData(
        expenses: [
          exp(amount: 80, date: '2026-06-10', category: 'Food'),
          exp(amount: 5000, date: '2026-06-10', category: kLoanCategory),
        ],
        now: now,
      );
      expect(data.pieSlices, hasLength(1));
      expect(data.pieSlices.single.name, 'Food');
      expect(data.monthSpent, 80);
    });

    test('pie slice amounts reconstruct the month spend', () {
      final data = ExpenseWidgetService.computeWidgetData(
        expenses: [
          exp(amount: 500, date: '2026-06-02', category: 'Food'),
          exp(amount: 400, date: '2026-06-03', category: 'Shopping'),
          exp(amount: 300, date: '2026-06-04', category: 'Transport'),
          exp(amount: 200, date: '2026-06-05', category: 'Bills'),
          exp(amount: 50, date: '2026-06-06', category: 'Medical'),
        ],
        now: now,
      );
      final pieSum =
          data.pieSlices.fold<double>(0, (s, slice) => s + slice.amount);
      expect(pieSum, data.monthSpent);
    });

    test('non-finite category totals are dropped from the mix', () {
      final slices = ExpenseWidgetService.buildPieSlices({
        'Food': 40,
        'Glitch': double.nan,
        'Boom': double.infinity,
      });
      expect(slices, hasLength(1));
      expect(slices.single.name, 'Food');
    });

    test('encodePiePayload is native-parseable and strips separators', () {
      final payload = ExpenseWidgetService.encodePiePayload([
        const ExpenseWidgetPieSlice(
          name: 'Food\u001fHack',
          emoji: '🍽️',
          amount: 12.5,
          color: '#AABBCC',
        ),
        const ExpenseWidgetPieSlice(
          name: 'Other',
          emoji: '📦',
          amount: 7,
          color: '#868E96',
        ),
      ]);
      final records = payload.split('\u001e');
      expect(records, hasLength(2));
      expect(records.first.split('\u001f'), ['Food Hack', '🍽️', '#AABBCC', '12.50']);
      expect(records.last.split('\u001f').last, '7.00');
    });
  });

  group('snapshotHash follows add / edit / delete', () {
    test('date-only edit is a new snapshot (today vs last month)', () {
      final before = [
        exp(id: '1', amount: 100, date: '2026-06-29T09:00:00'),
      ];
      final after = [
        exp(id: '1', amount: 100, date: '2026-05-01T09:00:00'),
      ];
      expect(
        ExpenseWidgetService.snapshotHash(expenses: before, monthBudget: 0),
        isNot(ExpenseWidgetService.snapshotHash(expenses: after, monthBudget: 0)),
      );
    });

    test('amount and category edits change the hash; identical rows do not', () {
      final base = [exp(id: '1', amount: 100, date: '2026-06-29', category: 'Food')];
      expect(
        ExpenseWidgetService.snapshotHash(expenses: base, monthBudget: 5000),
        ExpenseWidgetService.snapshotHash(expenses: base, monthBudget: 5000),
      );
      expect(
        ExpenseWidgetService.snapshotHash(expenses: base, monthBudget: 5000),
        isNot(ExpenseWidgetService.snapshotHash(
          expenses: [exp(id: '1', amount: 80, date: '2026-06-29', category: 'Food')],
          monthBudget: 5000,
        )),
      );
      expect(
        ExpenseWidgetService.snapshotHash(expenses: base, monthBudget: 5000),
        isNot(ExpenseWidgetService.snapshotHash(
          expenses: [exp(id: '1', amount: 100, date: '2026-06-29', category: 'Shopping')],
          monthBudget: 5000,
        )),
      );
    });

    test('delete (shorter list) and add (longer list) change the hash', () {
      final one = [exp(id: '1', amount: 100, date: '2026-06-29')];
      final two = [
        exp(id: '1', amount: 100, date: '2026-06-29'),
        exp(id: '2', amount: 40, date: '2026-06-29', category: 'Transport'),
      ];
      expect(
        ExpenseWidgetService.snapshotHash(expenses: one, monthBudget: 0),
        isNot(ExpenseWidgetService.snapshotHash(expenses: two, monthBudget: 0)),
      );
      expect(
        ExpenseWidgetService.snapshotHash(expenses: one, monthBudget: 0),
        isNot(ExpenseWidgetService.snapshotHash(expenses: const [], monthBudget: 0)),
      );
    });

    test('same expenses on a new calendar day are a new snapshot', () {
      final rows = [exp(id: '1', amount: 2965, date: '2026-09-16T13:37:00')];
      expect(
        ExpenseWidgetService.snapshotHash(
          expenses: rows,
          monthBudget: 20000,
          now: DateTime(2026, 9, 16, 21, 30),
        ),
        isNot(ExpenseWidgetService.snapshotHash(
          expenses: rows,
          monthBudget: 20000,
          now: DateTime(2026, 9, 17, 13, 29),
        )),
      );
    });
  });
}
