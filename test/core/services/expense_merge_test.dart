import 'package:ai_nexus/core/services/expense_merge.dart';
import 'package:ai_nexus/domain/entities/expense_entities.dart';
import 'package:flutter_test/flutter_test.dart';

Expense _e({
  required String id,
  double amount = 10,
  String description = 'row',
  String category = 'Others',
  String bank = 'HDFC',
  String cardType = 'CC',
  required String date,
  String comments = '',
}) =>
    Expense(
      id: id,
      amount: amount,
      description: description,
      category: category,
      bank: bank,
      cardType: cardType,
      date: date,
      isManualCategory: false,
      comments: comments,
    );

void main() {
  test('roundExpenseAmount keeps two-decimal rupee totals', () {
    expect(roundExpenseAmount(10.1 + 20.2), 30.3);
    expect(roundExpenseAmount(double.infinity), 0);
    expect(roundExpenseAmount(double.nan), 0);
  });

  test('planExpenseMerge rejects a single row', () {
    expect(
      () => planExpenseMerge([
        _e(id: 'a', date: '2026-09-19T10:10:00.000'),
      ]),
      throwsA(isA<ExpenseMergeException>()),
    );
  });

  test('planExpenseMerge rejects duplicate ids as a single row', () {
    final row = _e(id: 'a', amount: 10, date: '2026-09-19T10:10:00.000');
    expect(
      () => planExpenseMerge([row, row]),
      throwsA(isA<ExpenseMergeException>()),
    );
  });

  test('planExpenseMerge sums unique rows and uses the latest clock', () {
    final plan = planExpenseMerge([
      _e(
        id: 'a',
        amount: 60,
        date: '2026-09-19T10:10:00.000',
        bank: 'HDFC',
        cardType: 'CC',
      ),
      _e(
        id: 'b',
        amount: 37,
        date: '2026-09-19T11:18:00.000',
        bank: 'HDFC',
        cardType: 'CC',
      ),
      _e(
        id: 'c',
        amount: 80,
        date: '2026-09-19T10:15:00.000',
        bank: 'AXIS',
        cardType: 'DB',
      ),
    ]);
    expect(plan.count, 3);
    expect(plan.total, 177);
    expect(plan.canMerge, isTrue);
    expect(plan.loggedAt, DateTime(2026, 9, 19, 11, 18));
    expect(plan.bank, 'HDFC');
    expect(plan.cardType, 'CC');
    expect(plan.defaultCategory, 'Others');
  });

  test('mixed categories default to Others; identical category is kept', () {
    final mixed = planExpenseMerge([
      _e(
        id: 'a',
        category: 'Food',
        date: '2026-09-19T10:00:00.000',
      ),
      _e(
        id: 'b',
        category: 'Personal',
        date: '2026-09-19T10:01:00.000',
      ),
    ]);
    expect(mixed.defaultCategory, 'Others');

    final same = planExpenseMerge([
      _e(
        id: 'a',
        category: 'Food',
        date: '2026-09-19T10:00:00.000',
      ),
      _e(
        id: 'b',
        category: 'Food',
        date: '2026-09-19T10:01:00.000',
      ),
    ]);
    expect(same.defaultCategory, 'Food');
  });

  test('latest clock prefers Auto Detected stamp over dummy noon', () {
    final plan = planExpenseMerge([
      _e(
        id: 'early',
        amount: 10,
        date: '2026-09-19T12:00:00.000',
        comments: 'Auto Detected · 19 Sep 2026, 10:10 AM',
      ),
      _e(
        id: 'late',
        amount: 50,
        date: '2026-09-19T12:00:00.000',
        comments: 'Auto Detected · 19 Sep 2026, 11:18 AM',
      ),
    ]);
    expect(plan.loggedAt, DateTime(2026, 9, 19, 11, 18));
  });

  test('composeMergedExpense keeps latest clock on a picked calendar day', () {
    final plan = planExpenseMerge([
      _e(id: 'a', amount: 60, date: '2026-09-19T11:18:02.000'),
      _e(id: 'b', amount: 37, date: '2026-09-19T10:18:00.000'),
    ]);
    final merged = composeMergedExpense(
      plan: plan,
      id: 'merged',
      description: 'Danalashmi Flower Shop',
      category: 'Personal',
      pickedDay: DateTime(2026, 9, 18),
    );
    expect(merged.id, 'merged');
    expect(merged.amount, 97);
    expect(merged.description, 'Danalashmi Flower Shop');
    expect(merged.category, 'Personal');
    expect(merged.isManualCategory, isTrue);
    expect(merged.comments, isEmpty);
    expect(DateTime.parse(merged.date), DateTime(2026, 9, 18, 11, 18, 2));
  });

  test('composeMergedExpense refuses a source id and blank description', () {
    final plan = planExpenseMerge([
      _e(id: 'a', date: '2026-09-19T10:00:00.000'),
      _e(id: 'b', date: '2026-09-19T10:01:00.000'),
    ]);
    expect(
      () => composeMergedExpense(
        plan: plan,
        id: 'a',
        description: 'Shop',
        category: 'Food',
      ),
      throwsA(isA<ExpenseMergeException>()),
    );
    expect(
      () => composeMergedExpense(
        plan: plan,
        id: 'm',
        description: '  ',
        category: 'Food',
      ),
      throwsA(isA<ExpenseMergeException>()),
    );
  });

  test('zero total cannot merge', () {
    expect(
      () => planExpenseMerge([
        _e(id: 'a', amount: 0, date: '2026-09-19T10:00:00.000'),
        _e(id: 'b', amount: 0, date: '2026-09-19T10:01:00.000'),
      ]),
      throwsA(isA<ExpenseMergeException>()),
    );
  });

  test('screenshot UPI rows sum to 267 and keep the latest Auto Detected clock',
      () {
    final plan = planExpenseMerge([
      _e(
        id: '1',
        amount: 60,
        description: 'paytmqr16ii90sd2y@paytm',
        date: '2026-09-19T12:00:00.000',
        comments: 'Auto Detected · 19 Sep 2026, 11:18 AM',
      ),
      _e(
        id: '2',
        amount: 37,
        description: '99440213809@okbizaxis',
        date: '2026-09-19T12:00:00.000',
        comments: 'Auto Detected · 19 Sep 2026, 10:18 AM',
      ),
      _e(
        id: '3',
        amount: 80,
        description: 'gpay-12198000736@okbizaxi',
        date: '2026-09-19T12:00:00.000',
        comments: 'Auto Detected · 19 Sep 2026, 10:15 AM',
      ),
      _e(
        id: '4',
        amount: 30,
        description: 'Paytm',
        date: '2026-09-19T12:00:00.000',
        comments: 'Auto Detected · 19 Sep 2026, 10:13 AM',
      ),
      _e(
        id: '5',
        amount: 50,
        description: 'paytmqr5wi4xc@ptys',
        date: '2026-09-19T12:00:00.000',
        comments: 'Auto Detected · 19 Sep 2026, 10:11 AM',
      ),
      _e(
        id: '6',
        amount: 10,
        description: 'paytmqr6p24ts@ptys',
        date: '2026-09-19T12:00:00.000',
        comments: 'Auto Detected · 19 Sep 2026, 10:10 AM',
      ),
    ]);
    expect(plan.count, 6);
    expect(plan.total, 267);
    expect(plan.loggedAt, DateTime(2026, 9, 19, 11, 18));
    expect(plan.bank, 'HDFC');
    expect(plan.cardType, 'CC');
    expect(plan.canMerge, isTrue);
  });

  test('skips blank ids, NaN amounts, and bank ties break to the latest row',
      () {
    expect(
      () => planExpenseMerge([
        _e(id: '', amount: 10, date: '2026-09-19T10:00:00.000'),
        _e(id: 'a', amount: 10, date: '2026-09-19T10:00:00.000'),
      ]),
      throwsA(isA<ExpenseMergeException>()),
    );

    final nanSafe = planExpenseMerge([
      _e(id: 'a', amount: double.nan, date: '2026-09-19T10:00:00.000'),
      _e(id: 'b', amount: 20, date: '2026-09-19T10:01:00.000'),
    ]);
    expect(nanSafe.total, 20);

    final infSafe = planExpenseMerge([
      _e(id: 'a', amount: double.infinity, date: '2026-09-19T10:00:00.000'),
      _e(id: 'b', amount: 20, date: '2026-09-19T10:01:00.000'),
    ]);
    expect(infSafe.total, 20);

    expect(
      () => planExpenseMerge([
        _e(id: 'a', amount: double.nan, date: '2026-09-19T10:00:00.000'),
        _e(id: 'b', amount: double.nan, date: '2026-09-19T10:01:00.000'),
      ]),
      throwsA(isA<ExpenseMergeException>()),
    );

    final tied = majorityBankCard([
      _e(
        id: 'a',
        bank: 'HDFC',
        cardType: 'CC',
        date: '2026-09-19T10:00:00.000',
      ),
      _e(
        id: 'b',
        bank: 'AXIS',
        cardType: 'DB',
        date: '2026-09-19T11:00:00.000',
      ),
    ]);
    expect(tied.bank, 'AXIS');
    expect(tied.cardType, 'DB');
  });

  test('compose without a picked day keeps the plan clock and empty category fallback',
      () {
    final plan = planExpenseMerge([
      _e(id: 'a', amount: 10, date: '2026-09-19T11:18:00.000'),
      _e(id: 'b', amount: 5, date: '2026-09-19T10:00:00.000'),
    ]);
    final merged = composeMergedExpense(
      plan: plan,
      id: 'm',
      description: ' Flowers ',
      category: '  ',
    );
    expect(merged.description, 'Flowers');
    expect(merged.category, 'Others');
    expect(DateTime.parse(merged.date), DateTime(2026, 9, 19, 11, 18));
    expect(
      mergeTimestampOnPickedDay(
        DateTime(2026, 9, 1),
        DateTime(2026, 9, 19, 11, 18, 2),
      ),
      DateTime(2026, 9, 1, 11, 18, 2),
    );
    expect(
      () => composeMergedExpense(
        plan: plan,
        id: '  ',
        description: 'x',
        category: 'Food',
      ),
      throwsA(isA<ExpenseMergeException>()),
    );
  });

  test('compose keeps a user comment and does not copy source comments', () {
    final plan = planExpenseMerge([
      _e(
        id: 'a',
        amount: 10,
        comments: 'Auto Detected · 19 Sep 2026, 11:18 AM',
        date: '2026-09-19T11:18:00.000',
      ),
      _e(id: 'b', amount: 5, date: '2026-09-19T10:00:00.000'),
    ]);
    final blank = composeMergedExpense(
      plan: plan,
      id: 'm',
      description: 'shop',
      category: 'Food',
    );
    expect(blank.comments, isEmpty);

    final noted = composeMergedExpense(
      plan: plan,
      id: 'm',
      description: 'shop',
      category: 'Food',
      bank: 'AXIS',
      cardType: 'DB',
      comments: '  split with Riya  ',
    );
    expect(noted.comments, 'split with Riya');
    expect(noted.bank, 'AXIS');
    expect(noted.cardType, 'DB');
  });
}
