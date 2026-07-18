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

    test('top category considers the whole month, not just today', () {
      final data = ExpenseWidgetService.computeWidgetData(
        expenses: [
          exp(amount: 900, date: '2026-06-05', category: 'Bills'), // earlier
          exp(amount: 100, date: '2026-06-29', category: 'Food'), // today
        ],
        now: now,
      );
      expect(data.topCatName, 'Bills');
      expect(data.topCatAmount, 900);
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
  });
}
