import 'package:ai_nexus/data/services/sms_auto_expense/sms_models.dart';
import 'package:ai_nexus/data/services/sms_auto_expense/sms_parser.dart';
import 'package:ai_nexus/data/services/sms_auto_expense/sms_spend_dedupe.dart';
import 'package:ai_nexus/domain/entities/expense_entities.dart';
import 'package:flutter_test/flutter_test.dart';

Expense _sms({
  required String id,
  required double amount,
  required String description,
  required DateTime day,
  String bank = 'AXIS',
  String cardType = 'DB',
  String comments = '',
  String category = 'Others',
  bool manual = false,
}) {
  return Expense(
    id: id.startsWith('sms-') ? id : 'sms-$id',
    amount: amount,
    description: description,
    category: category,
    bank: bank,
    cardType: cardType,
    date: DateTime(day.year, day.month, day.day, 12).toIso8601String(),
    isManualCategory: manual,
    comments: comments,
  );
}

void main() {
  final received = DateTime(2026, 9, 11, 17, 3);

  group('screenshot pair: Axis request placeholder + HDFC success', () {
    test('upgrades the empty Auto Detected row instead of adding a second spend',
        () {
      final firstStamp = autoDetectedStamp(DateTime(2026, 9, 11, 16, 22));
      final existing = _sms(
        id: 'axis-req',
        amount: 1933,
        description: firstStamp,
        day: DateTime(2026, 9, 11),
        bank: 'AXIS',
        cardType: 'DB',
      );
      const success = 'Txn Rs.1933.00\nOn HDFC Bank Card 5901\n'
          'At Digitalageretailprivateca\nby UPI 599554152486\nOn 11-09\n'
          'SMS BLOCK CC 5901';
      final incoming = BankSmsParser.parse(
        success,
        smsReceivedAt: received.millisecondsSinceEpoch,
      )!;
      final hit = SmsSpendDedupe.match(
        incoming: incoming,
        incomingDescription: incoming.merchantRaw,
        receivedAt: received,
        recent: [existing],
      );
      expect(hit, isNotNull);
      expect(hit!.upgrade, isTrue);
      expect(hit.existing.id, 'sms-axis-req');
    });

    test('skips a weaker empty SMS when the named merchant is already logged', () {
      final stamp = autoDetectedStamp(received);
      final existing = _sms(
        id: 'hdfc-ok',
        amount: 1933,
        description: 'Digitalageretailprivateca',
        comments: stamp,
        day: DateTime(2026, 9, 11),
        bank: 'HDFC',
        cardType: 'CC',
      );
      final incoming = ParsedSmsDebit(
        amount: 1933,
        merchantRaw: '',
        instrument: 'BANK_ACCOUNT',
        instrumentLast4: null,
        transactionDate: DateTime(2026, 9, 11),
        bank: 'AXIS',
        cardType: 'DB',
        templateId: 'GENERIC',
      );
      final hit = SmsSpendDedupe.match(
        incoming: incoming,
        incomingDescription: stamp,
        receivedAt: received.add(const Duration(minutes: 5)),
        recent: [existing],
      );
      expect(hit, isNotNull);
      expect(hit!.upgrade, isFalse);
    });
  });

  group('does not merge unrelated spends', () {
    test('same amount, different shops, same day stay separate', () {
      final stamp = autoDetectedStamp(received);
      final existing = _sms(
        id: 'swiggy',
        amount: 219,
        description: 'Swiggy E Com',
        comments: stamp,
        day: DateTime(2026, 9, 11),
        bank: 'HDFC',
        cardType: 'CC',
        category: 'Food',
      );
      final incoming = ParsedSmsDebit(
        amount: 219,
        merchantRaw: 'Zomato',
        instrument: 'CREDIT_CARD',
        instrumentLast4: '5901',
        transactionDate: DateTime(2026, 9, 11),
        bank: 'HDFC',
        cardType: 'CC',
        templateId: 'T2',
      );
      expect(
        SmsSpendDedupe.match(
          incoming: incoming,
          incomingDescription: 'Zomato',
          receivedAt: received,
          recent: [existing],
        ),
        isNull,
      );
    });

    test('manual typed row is never treated as an SMS duplicate', () {
      final existing = Expense(
        id: 'manual-1',
        amount: 1933,
        description: 'Rent',
        category: 'Rent',
        bank: 'HDFC',
        cardType: 'DB',
        date: DateTime(2026, 9, 11, 12).toIso8601String(),
        isManualCategory: true,
        comments: '',
      );
      final incoming = ParsedSmsDebit(
        amount: 1933,
        merchantRaw: 'Digitalageretailprivateca',
        instrument: 'CREDIT_CARD',
        instrumentLast4: '5901',
        transactionDate: DateTime(2026, 9, 11),
        bank: 'HDFC',
        cardType: 'CC',
        templateId: 'T2',
      );
      expect(
        SmsSpendDedupe.match(
          incoming: incoming,
          incomingDescription: 'Digitalageretailprivateca',
          receivedAt: received,
          recent: [existing],
        ),
        isNull,
      );
    });

    test('same shop and amount two hours later is a second spend', () {
      final first = autoDetectedStamp(DateTime(2026, 9, 11, 12, 0));
      final existing = _sms(
        id: 'coffee-1',
        amount: 219,
        description: 'Swiggy',
        comments: first,
        day: DateTime(2026, 9, 11),
        category: 'Food',
      );
      final later = DateTime(2026, 9, 11, 14, 10);
      final incoming = ParsedSmsDebit(
        amount: 219,
        merchantRaw: 'Swiggy',
        instrument: 'CREDIT_CARD',
        instrumentLast4: '5901',
        transactionDate: DateTime(2026, 9, 11),
        bank: 'HDFC',
        cardType: 'CC',
        templateId: 'T2',
      );
      expect(
        SmsSpendDedupe.match(
          incoming: incoming,
          incomingDescription: 'Swiggy',
          receivedAt: later,
          recent: [existing],
        ),
        isNull,
      );
    });
  });

  group('mayAutofillCategory', () {
    test('SMS Others row can be filled in by a later named SMS', () {
      final e = _sms(
        id: 'ph',
        amount: 200,
        description: autoDetectedStamp(received),
        day: DateTime(2026, 9, 11),
      );
      expect(SmsSpendDedupe.mayAutofillCategory(e), isTrue);
    });

    test('user-edited Medical is never overwritten back to a suggestion', () {
      final e = _sms(
        id: 'ph',
        amount: 200,
        description: 'Sundaram Medical',
        day: DateTime(2026, 9, 11),
        category: 'Medical',
        manual: true,
      );
      expect(SmsSpendDedupe.mayAutofillCategory(e), isFalse);
    });

    test('Food (auto) is not treated as a blank Others row', () {
      final e = _sms(
        id: 'sw',
        amount: 219,
        description: 'Swiggy',
        day: DateTime(2026, 9, 11),
        category: 'Food',
      );
      expect(SmsSpendDedupe.mayAutofillCategory(e), isFalse);
    });
  });

  group('amountsMatch', () {
    test('treats 5-paise bank rounding as the same debit', () {
      expect(SmsSpendDedupe.amountsMatch(1933, 1933), isTrue);
      expect(SmsSpendDedupe.amountsMatch(1933, 1933.04), isTrue);
      expect(SmsSpendDedupe.amountsMatch(1933, 1933.06), isFalse);
    });
  });
}
