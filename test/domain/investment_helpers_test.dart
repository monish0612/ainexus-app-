// Unit tests for the central investment helpers in expense_entities.dart:
//   • isInvestmentCategory() — case/whitespace tolerant, null-safe
//   • ExpenseInvestmentFilter.spendOnly / .investmentsOnly
// These guard the single source of truth used everywhere spend is computed.

import 'package:flutter_test/flutter_test.dart';

import 'package:ai_nexus/domain/entities/expense_entities.dart';

Expense _exp(String category) => Expense(
      id: 'id-$category',
      amount: 100,
      description: 'd',
      category: category,
      bank: 'HDFC',
      cardType: 'CC',
      date: '2026-06-01T10:00:00.000',
      isManualCategory: false,
    );

void main() {
  group('isInvestmentCategory', () {
    test('matches exact, lowercase, uppercase, and padded variants', () {
      expect(isInvestmentCategory('Investment'), isTrue);
      expect(isInvestmentCategory('investment'), isTrue);
      expect(isInvestmentCategory('INVESTMENT'), isTrue);
      expect(isInvestmentCategory('  Investment  '), isTrue);
    });

    test('returns false for null, empty, and other categories', () {
      expect(isInvestmentCategory(null), isFalse);
      expect(isInvestmentCategory(''), isFalse);
      expect(isInvestmentCategory('   '), isFalse);
      expect(isInvestmentCategory('Investments'), isFalse);
      expect(isInvestmentCategory('Food'), isFalse);
    });
  });

  group('ExpenseInvestmentFilter', () {
    final items = <Expense>[
      _exp('Food'),
      _exp('Investment'),
      _exp('Transport'),
      _exp('investment'),
    ];

    test('spendOnly drops every investment row', () {
      final spend = items.spendOnly.toList();
      expect(spend.length, 2);
      expect(spend.any((e) => isInvestmentCategory(e.category)), isFalse);
    });

    test('investmentsOnly keeps only investment rows', () {
      final inv = items.investmentsOnly.toList();
      expect(inv.length, 2);
      expect(inv.every((e) => isInvestmentCategory(e.category)), isTrue);
    });
  });
}
