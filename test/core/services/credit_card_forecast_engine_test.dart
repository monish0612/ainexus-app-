// Pure unit tests for the credit-card forecast engine: the statement-close
// boundary, the bill-due roll-forward, the repaying-salary mapping (including
// the due-day >= credit-day edge), per-bank statement bucketing, the forward
// salary-vs-bills timeline, and projected in-hand.

import 'package:ai_nexus/core/services/credit_card_forecast_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // HDFC from the user's worked example: statement closes on the 18th, bill due
  // on the 9th of the following month.
  const hdfc = BankBillingConfig(name: 'HDFC', statementDay: 18, dueDay: 9);
  // Axis: statement 24, due 13.
  const axis = BankBillingConfig(name: 'AXIS', statementDay: 24, dueDay: 13);
  // Scapia: statement 26, due 15.
  const scapia = BankBillingConfig(name: 'SCAPIA', statementDay: 26, dueDay: 15);

  group('statementCloseDate', () {
    test('charge on/before the statement day closes this month', () {
      expect(statementCloseDate(DateTime(2026, 6, 10), 18), DateTime(2026, 6, 18));
      // Boundary: exactly ON the statement day still closes this month.
      expect(statementCloseDate(DateTime(2026, 6, 18), 18), DateTime(2026, 6, 18));
    });

    test('charge after the statement day rolls to next month', () {
      expect(statementCloseDate(DateTime(2026, 6, 19), 18), DateTime(2026, 7, 18));
      expect(statementCloseDate(DateTime(2026, 6, 25), 18), DateTime(2026, 7, 18));
    });

    test('rolls across a year boundary', () {
      expect(statementCloseDate(DateTime(2026, 12, 25), 18), DateTime(2027, 1, 18));
    });

    test('clamps the statement day to the month length', () {
      // Statement day 31 in February clamps to the 28th (2026 is not a leap yr).
      expect(statementCloseDate(DateTime(2026, 2, 10), 31), DateTime(2026, 2, 28));
    });
  });

  group('dueDateFor', () {
    test('bill is due in the month after the statement closes', () {
      expect(dueDateFor(DateTime(2026, 6, 18), 9), DateTime(2026, 7, 9));
      expect(dueDateFor(DateTime(2026, 7, 18), 9), DateTime(2026, 8, 9));
    });

    test('rolls across a year boundary', () {
      expect(dueDateFor(DateTime(2026, 12, 18), 9), DateTime(2027, 1, 9));
    });
  });

  group('repayingSalaryMonthKey', () {
    test('due before the credit day is paid by that month\'s salary', () {
      // Due Jul 9 (< 28) -> July salary (credited Jun 28).
      expect(repayingSalaryMonthKey(DateTime(2026, 7, 9)), '2026-07');
    });

    test('due on/after the credit day rolls to next month\'s salary', () {
      // Due Jul 28 (>= 28) -> August salary.
      expect(repayingSalaryMonthKey(DateTime(2026, 7, 28)), '2026-08');
      expect(repayingSalaryMonthKey(DateTime(2026, 7, 30)), '2026-08');
    });

    test('honours a custom credit day', () {
      expect(
        repayingSalaryMonthKey(DateTime(2026, 7, 9), creditDay: 5),
        '2026-08',
      );
    });
  });

  group('cardBillTimingFor — HDFC worked example', () {
    test('Jun 10 charge -> closes Jun 18 -> due Jul 9 -> July salary', () {
      final t = cardBillTimingFor(
        expenseDate: DateTime(2026, 6, 10),
        statementDay: 18,
        dueDay: 9,
      );
      expect(t.statementClose, DateTime(2026, 6, 18));
      expect(t.dueDate, DateTime(2026, 7, 9));
      expect(t.salaryMonthKey, '2026-07');
    });

    test('Jun 25 charge -> closes Jul 18 -> due Aug 9 -> August salary', () {
      final t = cardBillTimingFor(
        expenseDate: DateTime(2026, 6, 25),
        statementDay: 18,
        dueDay: 9,
      );
      expect(t.statementClose, DateTime(2026, 7, 18));
      expect(t.dueDate, DateTime(2026, 8, 9));
      expect(t.salaryMonthKey, '2026-08');
    });
  });

  group('computeCreditCardForecast', () {
    test('buckets charges per bank into the right statement & salary month', () {
      final forecast = computeCreditCardForecast(
        ccBanks: const [hdfc, axis, scapia],
        ccExpenses: [
          // HDFC: before the 18th -> July salary bucket.
          CardExpense(bank: 'HDFC', amount: 1000, date: _d(2026, 6, 10)),
          CardExpense(bank: 'HDFC', amount: 500, date: _d(2026, 6, 15)),
          // HDFC: after the 18th -> August salary bucket.
          CardExpense(bank: 'HDFC', amount: 2000, date: _d(2026, 6, 25)),
          // Axis: before the 24th -> closes Jun 24, due Jul 13 -> July.
          CardExpense(bank: 'AXIS', amount: 800, date: _d(2026, 6, 20)),
        ],
        salaryByMonth: const {'2026-06': 50000, '2026-07': 50000, '2026-08': 50000},
        now: DateTime(2026, 6, 16),
      );

      // Three statements: HDFC Jun-18, HDFC Jul-18, AXIS Jun-24.
      expect(forecast.statements.length, 3);

      final julyBills = forecast.statements
          .where((s) => s.salaryMonthKey == '2026-07')
          .toList();
      // HDFC 1500 (1000+500) + AXIS 800.
      expect(julyBills.fold<double>(0, (a, b) => a + b.total), 2300);

      final augBills = forecast.statements
          .where((s) => s.salaryMonthKey == '2026-08')
          .toList();
      expect(augBills.fold<double>(0, (a, b) => a + b.total), 2000);
    });

    test('timeline projects in-hand = salary - assigned bills', () {
      final forecast = computeCreditCardForecast(
        ccBanks: const [hdfc],
        ccExpenses: [
          CardExpense(bank: 'HDFC', amount: 12000, date: _d(2026, 6, 10)),
        ],
        salaryByMonth: const {'2026-07': 50000},
        now: DateTime(2026, 6, 16),
      );

      final july = forecast.timeline.firstWhere((m) => m.monthKey == '2026-07');
      expect(july.cardBills, 12000);
      expect(july.salary, 50000);
      expect(july.projectedInHand, 38000);
      expect(july.isShort, isFalse);
    });

    test('flags a month as short when bills exceed the salary', () {
      final forecast = computeCreditCardForecast(
        ccBanks: const [hdfc],
        ccExpenses: [
          CardExpense(bank: 'HDFC', amount: 60000, date: _d(2026, 6, 10)),
        ],
        salaryByMonth: const {'2026-07': 50000},
        now: DateTime(2026, 6, 16),
      );
      final july = forecast.timeline.firstWhere((m) => m.monthKey == '2026-07');
      expect(july.isShort, isTrue);
      expect(july.projectedInHand, -10000);
    });

    test('attaches the contributing charges to each statement, newest first',
        () {
      final forecast = computeCreditCardForecast(
        ccBanks: const [hdfc],
        ccExpenses: [
          CardExpense(
              bank: 'HDFC',
              amount: 1000,
              date: _d(2026, 6, 10),
              description: 'Groceries',
              category: 'Grocery'),
          CardExpense(
              bank: 'HDFC',
              amount: 500,
              date: _d(2026, 6, 15),
              description: 'Dinner',
              category: 'Food'),
        ],
        salaryByMonth: const {'2026-07': 50000},
        now: DateTime(2026, 6, 16),
      );
      expect(forecast.statements.length, 1);
      final items = forecast.statements.first.items;
      expect(items.length, 2);
      // Newest first.
      expect(items.first.date, _d(2026, 6, 15));
      expect(items.first.description, 'Dinner');
      expect(items.last.description, 'Groceries');
      // The total still matches the sum of items.
      expect(forecast.statements.first.total, 1500);
      expect(items.fold<double>(0, (a, b) => a + b.amount), 1500);
    });

    test('open statement is the still-accumulating window for a bank', () {
      final forecast = computeCreditCardForecast(
        ccBanks: const [hdfc],
        ccExpenses: [
          // Closed window (before "now").
          CardExpense(bank: 'HDFC', amount: 1000, date: _d(2026, 5, 10)),
          // Open window (closes Jun 18, now is Jun 16).
          CardExpense(bank: 'HDFC', amount: 3000, date: _d(2026, 6, 12)),
        ],
        salaryByMonth: const {},
        now: DateTime(2026, 6, 16),
      );
      expect(forecast.openStatements.length, 1);
      expect(forecast.openStatements.first.total, 3000);
      expect(forecast.openStatements.first.isOpen, isTrue);
    });

    test('records CC banks without a configured cycle as unconfigured', () {
      final forecast = computeCreditCardForecast(
        ccBanks: const [hdfc],
        ccExpenses: [
          CardExpense(bank: 'AMEX', amount: 999, date: _d(2026, 6, 12)),
        ],
        salaryByMonth: const {},
        now: DateTime(2026, 6, 16),
      );
      expect(forecast.unconfiguredBanks, contains('AMEX'));
      expect(forecast.statements, isEmpty);
      expect(forecast.hasActivity, isFalse);
    });

    test('matches bank names case-insensitively', () {
      final forecast = computeCreditCardForecast(
        ccBanks: const [hdfc],
        ccExpenses: [
          CardExpense(bank: 'hdfc', amount: 1000, date: _d(2026, 6, 10)),
        ],
        salaryByMonth: const {},
        now: DateTime(2026, 6, 16),
      );
      expect(forecast.statements.length, 1);
      expect(forecast.unconfiguredBanks, isEmpty);
    });

    test('empty input yields an inactive forecast', () {
      final forecast = computeCreditCardForecast(
        ccBanks: const [],
        ccExpenses: const [],
        salaryByMonth: const {},
        now: DateTime(2026, 6, 16),
      );
      expect(forecast.hasActivity, isFalse);
      expect(forecast.timeline.length, 3);
    });
  });
}

DateTime _d(int y, int m, int d) => DateTime(y, m, d);

