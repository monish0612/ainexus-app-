import 'package:ai_nexus/data/services/sms_auto_expense/sms_models.dart';
import 'package:ai_nexus/data/services/sms_auto_expense/sms_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const received = 1757570000000;

  group('UPI collect / request SMS is never a spend', () {
    test('Axis collect request sent by merchant', () {
      const body = 'Axis Bank: Collect request of INR 1,933.00 sent by '
          'DIGITALAGERETAILPRIVATECA. Accept in your UPI app.';
      expect(
        BankSmsParser.parse(body, smsReceivedAt: received, sender: 'AX-AXISBK'),
        isNull,
      );
    });

    test('HDFC payment request to approve with UPI PIN', () {
      const body = 'HDFC Bank: You have received a payment request of '
          'Rs.1933.00 from DIGITALAGERETAILPRIVATECA. Approve using UPI PIN.';
      expect(BankSmsParser.parse(body, smsReceivedAt: received), isNull);
    });

    test('payment request sent waiting for payee', () {
      const body =
          'UPI payment request of Rs.1933.00 sent. Waiting for them to accept.';
      expect(BankSmsParser.parse(body, smsReceivedAt: received), isNull);
    });

    test('has requested you to pay', () {
      const body =
          'DIGITALAGERETAILPRIVATECA has requested you to pay Rs.1933.00 via UPI.';
      expect(BankSmsParser.parse(body, smsReceivedAt: received), isNull);
    });

    test('accept in UPI app without the word request', () {
      const body =
          'Axis Bank: INR 1,933.00 sent by DIGITALAGERETAILPRIVATECA. '
          'Accept in your UPI app.';
      expect(
        BankSmsParser.parse(body, smsReceivedAt: received, sender: 'AX-AXISBK'),
        isNull,
      );
    });

    test('incoming UPI "has sent you" is not a spend', () {
      const body =
          'HDFC Bank: MONISH has sent you Rs.500.00 via UPI.';
      expect(BankSmsParser.parse(body, smsReceivedAt: received), isNull);
    });

    test('txn being processed is not a spend', () {
      const body =
          'Your txn of Rs.1933.00 is being processed. Do not pay twice.';
      expect(BankSmsParser.parse(body, smsReceivedAt: received), isNull);
    });
  });

  group('failed / declined / reversed are never a spend', () {
    test('declined card spend is dropped even if it looks like T3', () {
      const body = 'Spent Rs.1933 On HDFC Bank Card 5901 At DIGITALAGE '
          'On 2026-09-11:12:00:00. Declined. Insufficient funds.';
      expect(BankSmsParser.parse(body, smsReceivedAt: received), isNull);
    });

    test('UPI failed SMS is dropped', () {
      const body =
          'Rs.1933.00 txn failed. UPI Ref 123. Axis Bank.';
      expect(
        BankSmsParser.parse(body, smsReceivedAt: received, sender: 'AX-AXISBK'),
        isNull,
      );
    });

    test('reversed debit is dropped', () {
      const body = 'Rs.500.00 debited from HDFC Bank A/C has been reversed.';
      expect(BankSmsParser.parse(body, smsReceivedAt: received), isNull);
    });
  });

  group('real completed spends still parse after the request filter', () {
    test('T1 Sent Rs is a debit, not a payment request', () {
      const body = 'Sent Rs.2822.00\nFrom HDFC Bank A/C *7372\nTo Scapia\n'
          'On 10/09/26\nRef 859114032536';
      final p = BankSmsParser.parse(body, smsReceivedAt: received)!;
      expect(p.amount, 2822);
      expect(p.templateId, 'T1');
    });

    test('T2 card UPI success still logs', () {
      const body = 'Txn Rs.1933.00\nOn HDFC Bank Card 5901\n'
          'At Digitalageretailprivateca\nby UPI 599554152486\nOn 11-09\n'
          'Not You?\nSMS BLOCK CC 5901 to 7308080808';
      final smsAt = DateTime(2026, 9, 11, 17, 3).millisecondsSinceEpoch;
      final p = BankSmsParser.parse(body, smsReceivedAt: smsAt)!;
      expect(p.amount, 1933);
      expect(p.merchantRaw, 'Digitalageretailprivateca');
      expect(p.cardType, 'CC');
      expect(p.templateId, 'T2');
    });

    test('Axis card spent template is unchanged', () {
      const body = 'Spent INR 4173.16\nAxis Bank Card no. XX7159\n'
          '15-08-26 13:44:31 IST\nBharat Petr\nAvl Limit: INR 57827.35';
      final p = BankSmsParser.parse(body, smsReceivedAt: received)!;
      expect(p.bank, 'AXIS');
      expect(p.amount, 4173.16);
    });
  });

  group('queued debit from an older APK is re-checked', () {
    test('stale collect request in the native queue is dropped', () {
      const body = 'Axis Bank: Collect request of INR 1,933.00 sent by '
          'DIGITALAGERETAILPRIVATECA. Accept in your UPI app.';
      final stale = ParsedSmsDebit(
        amount: 1933,
        merchantRaw: '',
        instrument: 'BANK_ACCOUNT',
        instrumentLast4: null,
        transactionDate: DateTime(2026, 9, 11),
        bank: 'AXIS',
        cardType: 'DB',
        templateId: 'GENERIC',
        rawBody: body,
      );
      expect(
        BankSmsParser.reconcileQueued(stale, smsReceivedAt: received),
        isNull,
      );
    });

    test('queued T1 is still a debit', () {
      const body = 'Sent Rs.2822.00\nFrom HDFC Bank A/C *7372\nTo Scapia\n'
          'On 10/09/26\nRef 859114032536';
      final queued = ParsedSmsDebit(
        amount: 2822,
        merchantRaw: 'Scapia',
        instrument: 'BANK_ACCOUNT',
        instrumentLast4: '7372',
        transactionDate: DateTime(2026, 9, 10),
        bank: 'HDFC',
        cardType: 'DB',
        templateId: 'T1',
        rawBody: body,
      );
      final p = BankSmsParser.reconcileQueued(
        queued,
        smsReceivedAt: received,
      )!;
      expect(p.templateId, 'T1');
      expect(p.amount, 2822);
    });
  });
}
