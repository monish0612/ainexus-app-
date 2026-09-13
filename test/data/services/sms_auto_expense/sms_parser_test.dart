import 'package:flutter_test/flutter_test.dart';

import 'package:ai_nexus/data/services/sms_auto_expense/sms_parser.dart';

void main() {
  const received = 1757000000000; // 2025-ish epoch; dates in the SMS win

  group('T7 future mandate is never an expense', () {
    test('E-Mandate will be deducted is discarded', () {
      const body = 'E-Mandate!\n'
          'Rs.95.70 will be deducted on 03/08/26, 00:00:00\n'
          'For GOOGLECLOUD mandate\nNot You?';
      expect(BankSmsParser.parse(body, smsReceivedAt: received), isNull);
    });

    test('will be deducted without E-Mandate banner is still discarded', () {
      const body =
          'Rs.2346.00 will be deducted on 12/09/26 from HDFC Bank A/C';
      expect(BankSmsParser.parse(body, smsReceivedAt: received), isNull);
    });
  });

  group('HDFC templates from real alerts', () {
    test('T1 UPI Sent Rs from A/C', () {
      const body = 'Sent Rs.2822.00\n'
          'From HDFC Bank A/C *7372\n'
          'To Scapia\n'
          'On 10/09/26\n'
          'Ref 859114032536\n'
          'Not You?\nCall 18002586161/SMS BLOCK UPI to 7308080808';
      final p = BankSmsParser.parse(body, smsReceivedAt: received)!;
      expect(p.amount, 2822.00);
      expect(p.merchantRaw, 'Scapia');
      expect(p.bank, 'HDFC');
      expect(p.cardType, 'DB');
      expect(p.instrument, 'BANK_ACCOUNT');
      expect(p.instrumentLast4, '7372');
      expect(p.referenceId, '859114032536');
      expect(p.transactionDate, DateTime(2026, 9, 10));
      expect(p.templateId, 'T1');
    });

    test('T1 spaced initials survive', () {
      const body = 'Sent Rs.350.00\n'
          'From HDFC Bank A/C *7372\n'
          'To B . KAMALAKANNAN\n'
          'On 24/06/26\n'
          'Ref 205356511756\nNot You?\n'
          'Call 18002586161/SMS BLOCK UPI to 7308080808';
      final p = BankSmsParser.parse(body, smsReceivedAt: received)!;
      expect(p.amount, 350);
      expect(p.merchantRaw, 'B. Kamalakannan');
      expect(p.cardType, 'DB');
    });

    test('T1b UPI Mandate lowercase from/A/c, date without On', () {
      const body = 'UPI Mandate:\n'
          'Sent Rs.95.70\n'
          'from HDFC Bank A/c 7372\n'
          'To GOOGLECLOUD\n'
          '03/08/26\n'
          'Ref 441122334455';
      final p = BankSmsParser.parse(body, smsReceivedAt: received)!;
      expect(p.amount, 95.70);
      expect(p.merchantRaw, 'Googlecloud');
      expect(p.transactionDate, DateTime(2026, 8, 3));
      expect(p.templateId, 'T1');
    });

    test('T2 card UPI, year-less On DD-MM', () {
      const body = 'Txn Rs.20.00\n'
          'On HDFC Bank Card 5901\n'
          'At paytmqr5yt66v@ptys\n'
          'by UPI 599554152486\n'
          'On 05-09\n'
          'Not You?\nSMS BLOCK CC 5901 to 7308080808';
      final smsAt = DateTime(2026, 9, 10).millisecondsSinceEpoch;
      final p = BankSmsParser.parse(body, smsReceivedAt: smsAt)!;
      expect(p.amount, 20);
      expect(p.merchantRaw, 'paytmqr5yt66v@ptys');
      expect(p.cardType, 'CC');
      expect(p.instrumentLast4, '5901');
      expect(p.transactionDate, DateTime(2026, 9, 5));
      expect(p.templateId, 'T2');
    });

    test('T2 Paytm VPA with brandable prefix', () {
      const body = 'Txn Rs.30.00\n'
          'On HDFC Bank Card 5901\n'
          'At paytm.s29gayk@pty \n'
          'by UPI 420791991766\n'
          'On 25-06\nNot You?\n'
          'Call 18002586161/SMS BLOCK CC 5901 to 7308080808';
      final smsAt = DateTime(2026, 6, 26).millisecondsSinceEpoch;
      final p = BankSmsParser.parse(body, smsReceivedAt: smsAt)!;
      expect(p.amount, 30);
      expect(p.merchantRaw, 'Paytm');
      expect(p.cardType, 'CC');
    });

    test('T3 Spent On Card At merchant ISO datetime', () {
      const body = 'Spent Rs.211 On HDFC Bank Card 6177 At SWIGGY ADD MONEY '
          'On 2026-09-04:13:32:18.Not You? To Block+Reissue '
          'Call 18002586161/SMS BLOCK CC 5901 to 7308080808';
      final p = BankSmsParser.parse(body, smsReceivedAt: received)!;
      expect(p.amount, 211);
      expect(p.merchantRaw, 'Swiggy Add Money');
      expect(p.cardType, 'CC');
      expect(p.transactionDate, DateTime(2026, 9, 4));
    });

    test('T3 truncated merchant dots and underscore are stripped', () {
      const body = 'Spent Rs.842 On HDFC Bank Card 5901 At ..SUNDARAM MEDICAL_ '
          'On 2026-06-21:19:21:50.Not You? SMS BLOCK CC 5901';
      final p = BankSmsParser.parse(body, smsReceivedAt: received)!;
      expect(p.merchantRaw, 'Sundaram Medical');
    });

    test('T4 Spent From Card with Bal', () {
      const body = 'Spent Rs.2.69 From HDFC Bank Card x3805 At WWW AMAZON IN '
          'On 2026-08-22:09:22:25 Bal Rs.2124.58 SMS BLOCK DC 3805';
      final p = BankSmsParser.parse(body, smsReceivedAt: received)!;
      expect(p.amount, 2.69);
      expect(p.merchantRaw, 'Www Amazon In');
      expect(p.cardType, 'DB');
      expect(p.instrument, 'DEBIT_CARD');
      expect(p.balanceAfter, 2124.58);
    });

    test('T5 lowercase spent on, Avl bal', () {
      const body = 'Rs.217 spent on HDFC Bank Card x3805 at WWW AMAZON IN '
          'on 2026-07-17:10:43:33 Avl bal: 806.94 SMS BLOCK DC 3805';
      final p = BankSmsParser.parse(body, smsReceivedAt: received)!;
      expect(p.amount, 217);
      expect(p.merchantRaw, 'Www Amazon In');
      expect(p.cardType, 'DB');
      expect(p.balanceAfter, 806.94);
    });

    test('T6 PAYMENT ALERT deducted towards UMRN uses receipt time', () {
      const body = 'PAYMENT ALERT! \n'
          'INR 2346.00 deducted from HDFC Bank A/C No 7372 towards '
          'RACPC TAMBARAM-SBIN0061039 UMRN: HDFC000000000\n'
          'SMS BLOCK UPI';
      final smsAt = DateTime(2026, 9, 10, 11, 22).millisecondsSinceEpoch;
      final p = BankSmsParser.parse(body, smsReceivedAt: smsAt)!;
      expect(p.amount, 2346);
      expect(p.merchantRaw.toLowerCase(), contains('racpc'));
      expect(p.cardType, 'DB');
      expect(p.transactionDate, DateTime(2026, 9, 10));
      expect(p.templateId, 'T6');
    });
  });

  group('card type comes from SMS BLOCK not the x prefix', () {
    test('x5901 with BLOCK CC is credit', () {
      const body = 'Spent Rs.10 On HDFC Bank Card x5901 At SWIGGY '
          'On 2026-09-01:10:00:00 SMS BLOCK CC 5901';
      final p = BankSmsParser.parse(body, smsReceivedAt: received)!;
      expect(p.cardType, 'CC');
    });

    test('no x with BLOCK DC is debit', () {
      const body = 'Spent Rs.10 From HDFC Bank Card 3805 At SWIGGY '
          'On 2026-09-01:10:00:00 Bal Rs.1 SMS BLOCK DC 3805';
      final p = BankSmsParser.parse(body, smsReceivedAt: received)!;
      expect(p.cardType, 'DB');
    });
  });

  group('noise is ignored', () {
    test('credit SMS is ignored', () {
      const body = 'Rs.50000.00 credited to HDFC Bank A/C *7372 on 10/09/26';
      expect(BankSmsParser.parse(body, smsReceivedAt: received), isNull);
    });

    test('OTP is ignored', () {
      const body = 'HDFC Bank: 482911 is your OTP. Do not share with anyone.';
      expect(BankSmsParser.parse(body, smsReceivedAt: received), isNull);
    });
  });

  group('Axis / ICICI / Scapia templates', () {
    test('Axis fuel spend recovers amount, merchant, CC and date', () {
      const body = 'Spent INR 3790.37\nAxis Bank Card no. XX7159\n'
          '19-06-26 15:37:26 IST\nSTAR FUEL S\nAvl Limit: INR 50884.25\n'
          'Not you? SMS BLOCK 7159 to 919951860002 .';
      final p = BankSmsParser.parse(body, smsReceivedAt: received)!;
      expect(p.amount, 3790.37);
      expect(p.bank, 'AXIS');
      expect(p.cardType, 'CC');
      expect(p.instrumentLast4, '7159');
      expect(p.merchantRaw, 'Star Fuel S');
      expect(p.transactionDate, DateTime(2026, 6, 19));
      expect(p.templateId, 'AXIS');
    });
  });

  group('isBankSender', () {
    test('HDFC alphanumeric IDs', () {
      expect(isBankSender('JM-HDFCBK'), isTrue);
      expect(isBankSender('AD-HDFCBK'), isTrue);
      expect(isBankSender('AX-AXISBK'), isTrue);
      expect(isBankSender('+919840012345'), isFalse);
      expect(isBankSender('VM-ICICIB'), isTrue);
      expect(isBankSender('VM-FEDBNK'), isTrue);
      expect(isBankSender('AD-FEDBANK'), isTrue);
      expect(isBankSender('AX-FEDADV'), isTrue);
      expect(isBankSender('VM-FDRLBN'), isTrue);
    });
  });

  group('T2 year inference', () {
    test('December date in early January rolls back a year', () {
      expect(
        BankSmsParser.parseDdMmInferYear(
          '25-12',
          DateTime(2027, 1, 3).millisecondsSinceEpoch,
        ),
        DateTime(2026, 12, 25),
      );
    });
  });

  group('autoDetectedStamp', () {
    test('includes Auto Detected and clock', () {
      final s = autoDetectedStamp(DateTime(2026, 9, 10, 10, 33));
      expect(s, contains('Auto Detected'));
      expect(s, contains('10 Sep 2026'));
      expect(s, contains('10:33'));
    });
  });

  group('production corpus from share-to-log samples', () {
    test('Indian grouping commas parse as rupees', () {
      const body = 'Sent Rs.2,822.00\nFrom HDFC Bank A/C *7372\nTo Scapia\n'
          'On 10/09/26\nRef 859114032536';
      final p = BankSmsParser.parse(body, smsReceivedAt: received)!;
      expect(p.amount, 2822);
    });

    test('glued merchant SANWARIATEXPROPRIVATE', () {
      const body = 'Spent Rs.899 On HDFC Bank Card 5901 At SANWARIATEXPROPRIVATE '
          'On 2026-06-22:18:43:58.Not You? To Block+Reissue '
          'Call 18002586161/SMS BLOCK CC 5901 to 7308080808';
      final p = BankSmsParser.parse(body, smsReceivedAt: received)!;
      expect(p.amount, 899);
      expect(p.merchantRaw, 'Sanwariatexproprivate');
      expect(p.cardType, 'CC');
    });

    test('SANTHOSH SUPER STORES grocery spend', () {
      const body = 'Spent Rs.842 On HDFC Bank Card 5901 At SANTHOSH SUPER STORES '
          'On 2026-06-21:19:21:50.Not You? To Block+Reissue '
          'Call 18002586161/SMS BLOCK CC 5901 to 7308080808';
      final p = BankSmsParser.parse(body, smsReceivedAt: received)!;
      expect(p.amount, 842);
      expect(p.merchantRaw, 'Santhosh Super Stores');
    });

    test('decimal T3 Nobroker', () {
      const body = 'Spent Rs.317.44 On HDFC Bank Card 5901 At NOBROKER TECHNOLOGIES '
          'On 2026-06-21:19:25:05.Not You? SMS BLOCK CC 5901';
      final p = BankSmsParser.parse(body, smsReceivedAt: received)!;
      expect(p.amount, 317.44);
      expect(p.merchantRaw, 'Nobroker Technologies');
    });

    test('T7 notice then T1b real debit both behave correctly', () {
      const notice = 'E-Mandate!\nRs.95.70 will be deducted on 03/08/26, 00:00:00\n'
          'For GOOGLECLOUD mandate';
      const debit = 'UPI Mandate:\nSent Rs.95.70\nfrom HDFC Bank A/c 7372\n'
          'To GOOGLECLOUD\n03/08/26\nRef 441122334455';
      expect(BankSmsParser.parse(notice, smsReceivedAt: received), isNull);
      final p = BankSmsParser.parse(debit, smsReceivedAt: received)!;
      expect(p.amount, 95.70);
      expect(p.merchantRaw, 'Googlecloud');
    });

    test('Not You footer does not look like an OTP drop', () {
      const body = 'Spent Rs.211 On HDFC Bank Card 6177 At SWIGGY ADD MONEY '
          'On 2026-09-04:13:32:18.Not You? To Block+Reissue '
          'Call 18002586161/SMS BLOCK CC 5901 to 7308080808';
      expect(BankSmsParser.parse(body, smsReceivedAt: received), isNotNull);
    });
  });
}
