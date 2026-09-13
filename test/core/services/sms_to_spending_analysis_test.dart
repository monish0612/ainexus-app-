import 'package:ai_nexus/core/services/expense_composition.dart';
import 'package:ai_nexus/data/services/sms_auto_expense/sms_merchant_category.dart';
import 'package:ai_nexus/domain/entities/expense_entities.dart';
import 'package:flutter_test/flutter_test.dart';

/// End-to-end of the yesterday bug, without widgets:
/// SMS classify → period totals → tracker ring slices → user edit → slices.
void main() {
  Map<String, double> spendMap(List<Expense> rows) {
    final map = <String, double>{};
    for (final e in rows.where((e) => !isNonSpendCategory(e.category))) {
      map[e.category] = (map[e.category] ?? 0) + e.amount;
    }
    return map;
  }

  Expense sms({
    required String category,
    double amount = 200,
    bool manual = false,
    String description = 'Sundaram Medical',
  }) =>
      Expense(
        id: 'sms-1',
        amount: amount,
        description: description,
        category: category,
        bank: 'HDFC',
        cardType: 'CC',
        date: DateTime(2026, 9, 12, 12).toIso8601String(),
        isManualCategory: manual,
      );

  test('unknown UPI auto-log is Others on the ring, not synthetic Other', () {
    final cat = suggestSmsCategory('Q227400652@ybl');
    expect(cat, 'Others');
    final slices = ExpenseComposition.pieSlices(spendMap([
      sms(category: 'Food', amount: 9000, description: 'Swiggy', manual: false),
      sms(category: cat, description: 'Q227400652@ybl'),
    ]));
    expect(slices.map((s) => s.category), ['Food', 'Others']);
    expect(slices.any((s) => s.isOther || s.category == 'Other'), isFalse);
  });

  test('pharmacy SMS auto-log is already Medical on the ring', () {
    expect(suggestSmsCategory('Sundaram Medical'), 'Medical');
    final slices = ExpenseComposition.pieSlices(spendMap([
      sms(category: 'Food', amount: 9000, description: 'Swiggy'),
      sms(
        category: suggestSmsCategory('Sundaram Medical'),
        description: 'Sundaram Medical',
      ),
    ]));
    expect(slices.map((s) => s.category), ['Food', 'Medical']);
  });

  test('Others → Medical edit updates the same ring that spent the SMS', () {
    final food = sms(category: 'Food', amount: 9000, description: 'Swiggy');
    final auto = sms(category: 'Others', description: 'Q227400652@ybl');
    expect(
      ExpenseComposition.pieSlices(spendMap([food, auto]))
          .map((s) => s.category),
      ['Food', 'Others'],
    );

    final edited = auto.copyWith(category: 'Medical', isManualCategory: true);
    expect(edited.isManualCategory, isTrue);
    final after = ExpenseComposition.pieSlices(spendMap([food, edited]));
    expect(after.map((s) => s.category), ['Food', 'Medical']);
    expect(after.last.total, 200);
    expect(after.any((s) => s.category == 'Other' || s.isOther), isFalse);
  });

  test('Investment + Loan never enter the spending ring', () {
    final slices = ExpenseComposition.pieSlices(spendMap([
      sms(category: 'Food', amount: 500, description: 'Swiggy'),
      sms(category: 'Investment', amount: 10000, description: 'SIP'),
      sms(category: 'Loan', amount: 8000, description: 'EMI'),
      sms(category: 'Medical', amount: 200, description: 'Apollo'),
    ]));
    expect(slices.map((s) => s.category), ['Food', 'Medical']);
  });
}
