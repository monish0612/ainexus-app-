import 'package:flutter_test/flutter_test.dart';

import 'package:ai_nexus/data/services/sms_auto_expense/sms_merchant_category.dart';
import 'package:ai_nexus/data/services/sms_auto_expense/sms_parser.dart';

void main() {
  final received = DateTime(2026, 9, 10, 11, 26).millisecondsSinceEpoch;

  group('Axis credit card', () {
    test('Bharat Petr 15-08-26', () {
      const body = 'Spent INR 4173.16\n'
          'Axis Bank Card no. XX7159\n'
          '15-08-26 13:44:31 IST\n'
          'Bharat Petr\n'
          'Avl Limit: INR 57827.35\n'
          'Not you? SMS BLOCK 7159 to 919951860002';
      final p = BankSmsParser.parse(body, smsReceivedAt: received)!;
      expect(p.amount, 4173.16);
      expect(p.bank, 'AXIS');
      expect(p.cardType, 'CC');
      expect(p.instrument, 'CREDIT_CARD');
      expect(p.instrumentLast4, '7159');
      expect(p.merchantRaw, 'Bharat Petr');
      expect(p.transactionDate, DateTime(2026, 8, 15));
      expect(p.templateId, 'AXIS');
      expect(suggestSmsCategory(p.merchantRaw), 'Fuel');
    });

    test('STAR FUEL S 19-06-26', () {
      const body = 'Spent INR 3790.37\n'
          'Axis Bank Card no. XX7159\n'
          '19-06-26 15:37:26 IST\n'
          'STAR FUEL S\n'
          'Avl Limit: INR 50884.25\n'
          'Not you? SMS BLOCK 7159 to 919951860002';
      final p = BankSmsParser.parse(body, smsReceivedAt: received)!;
      expect(p.amount, 3790.37);
      expect(p.bank, 'AXIS');
      expect(p.cardType, 'CC');
      expect(p.merchantRaw, 'Star Fuel S');
      expect(p.transactionDate, DateTime(2026, 6, 19));
      expect(suggestSmsCategory(p.merchantRaw), 'Fuel');
    });

    test('available limit is not the spend amount', () {
      const body = 'Spent INR 4173.16\n'
          'Axis Bank Card no. XX7159\n'
          '15-08-26 13:44:31 IST\n'
          'Bharat Petr\n'
          'Avl Limit: INR 57827.35\n'
          'Not you? SMS BLOCK 7159 to 919951860002';
      final p = BankSmsParser.parse(body, smsReceivedAt: received)!;
      expect(p.amount, 4173.16);
      expect(p.amount, isNot(57827.35));
    });

    test('single-line flatten still matches AXIS template', () {
      const body = 'Spent INR 4173.16 Axis Bank Card no. XX7159 '
          '15-08-26 13:44:31 IST Bharat Petr Avl Limit: INR 57827.35 '
          'Not you? SMS BLOCK 7159 to 919951860002';
      final p = BankSmsParser.parse(body, smsReceivedAt: received)!;
      expect(p.templateId, 'AXIS');
      expect(p.amount, 4173.16);
      expect(p.merchantRaw, 'Bharat Petr');
      expect(p.instrumentLast4, '7159');
    });

    test('DLT and numeric senders both pass the receiver gate', () {
      const body = 'Spent INR 4173.16\nAxis Bank Card no. XX7159\n'
          '15-08-26 13:44:31 IST\nBharat Petr\nAvl Limit: INR 57827.35';
      expect(smsShouldAccept('AX-AXISBK', body), isTrue);
      expect(smsShouldAccept('AD-AXISBK', body), isTrue);
      expect(smsShouldAccept('VM-AXISBK', body), isTrue);
      expect(smsShouldAccept('+919840012345', body), isTrue);
      expect(smsShouldAccept('', body), isTrue);
      expect(isBankSender('AX-AXISBK'), isTrue);
    });
  });

  group('ICICI credit card', () {
    test('Rs spent on Card at AMAZON, Indian grouping, ignores Avl Lmt', () {
      const body = 'Rs 8,153.00 spent on ICICI Bank Card XX7003 on 09-Sep-26 '
          'at AMAZON PAY IN E. Avl Lmt: Rs 17,02,098.21. To dispute, call '
          '18002662/SMS BLOCK 7003 to 9215676766. To convert this txn to EMI '
          'give a missed call on 9924667667.';
      final p = BankSmsParser.parse(body, smsReceivedAt: received)!;
      expect(p.amount, 8153);
      expect(p.bank, 'ICICI');
      expect(p.cardType, 'CC');
      expect(p.instrumentLast4, '7003');
      expect(p.merchantRaw.toLowerCase(), contains('amazon'));
      expect(p.transactionDate, DateTime(2026, 9, 9));
      expect(p.templateId, 'ICICI');
      expect(suggestSmsCategory(p.merchantRaw), 'Shopping');
    });

    test('INR spent using Card on AMAZON', () {
      const body = 'INR 1,004.00 spent using ICICI Bank Card XX7003 on '
          '01-Sep-26 on AMAZON PAY IN E. Avl Limit: INR 17,10,251.21. '
          'If not you, call 1800 2662/SMS BLOCK 7003 to 9215676766.';
      final p = BankSmsParser.parse(body, smsReceivedAt: received)!;
      expect(p.amount, 1004);
      expect(p.bank, 'ICICI');
      expect(p.cardType, 'CC');
      expect(p.transactionDate, DateTime(2026, 9, 1));
    });

    test('15-Aug-26 Amazon', () {
      const body = 'Rs 18,525.84 spent on ICICI Bank Card XX7003 on 15-Aug-26 '
          'at AMAZON PAY IN E. Avl Lmt: Rs 16,76,317.21. To dispute, call '
          '18002662/SMS BLOCK 7003 to 9215676766.';
      final p = BankSmsParser.parse(body, smsReceivedAt: received)!;
      expect(p.amount, 18525.84);
      expect(p.transactionDate, DateTime(2026, 8, 15));
      expect(p.bank, 'ICICI');
      expect(p.cardType, 'CC');
    });

    test('available limit with Indian grouping is not the spend', () {
      const body = 'Rs 8,153.00 spent on ICICI Bank Card XX7003 on 09-Sep-26 '
          'at AMAZON PAY IN E. Avl Lmt: Rs 17,02,098.21.';
      final p = BankSmsParser.parse(body, smsReceivedAt: received)!;
      expect(p.amount, 8153);
      expect(p.amount, isNot(1702098.21));
      expect(p.templateId, 'ICICI');
      expect(suggestSmsCategory(p.merchantRaw), 'Shopping');
    });

    test('Avl Limit without trailing period still matches', () {
      const body = 'INR 1,004.00 spent using ICICI Bank Card XX7003 on '
          '01-Sep-26 on AMAZON PAY IN E Avl Limit: INR 17,10,251.21.';
      final p = BankSmsParser.parse(body, smsReceivedAt: received)!;
      expect(p.amount, 1004);
      expect(p.templateId, 'ICICI');
      expect(p.bank, 'ICICI');
      expect(p.cardType, 'CC');
      expect(p.instrumentLast4, '7003');
      expect(p.merchantRaw.toLowerCase(), contains('amazon'));
    });

    test('DLT and numeric senders both pass the receiver gate', () {
      const body = 'Rs 8,153.00 spent on ICICI Bank Card XX7003 on 09-Sep-26 '
          'at AMAZON PAY IN E. Avl Lmt: Rs 17,02,098.21.';
      expect(smsShouldAccept('VM-ICICIB', body), isTrue);
      expect(smsShouldAccept('AD-ICICIB', body), isTrue);
      expect(smsShouldAccept('AX-ICICIT', body), isTrue);
      expect(smsShouldAccept('+919840012345', body), isTrue);
      expect(smsShouldAccept('', body), isTrue);
      expect(isBankSender('VM-ICICIB'), isTrue);
    });

    test('ICICI OTP is still ignored', () {
      expect(
        BankSmsParser.parse(
          'ICICI Bank: 482911 is your OTP. Do not share with anyone.',
          smsReceivedAt: received,
          sender: 'VM-ICICIB',
        ),
        isNull,
      );
    });
  });

  group('Scapia Federal Visa credit card', () {
    test('Anthropic + Us truncation', () {
      const body = 'Hi! Your txn of ₹669.04 at Anthropic + Us on your '
          'Scapia Federal Visa credit card was successful. Not you? '
          'Go to Scapia support on the app.- Federal Bank';
      final p = BankSmsParser.parse(
        body,
        smsReceivedAt: received,
        sender: 'VM-FEDBNK',
      )!;
      expect(p.amount, 669.04);
      expect(p.bank, 'SCAPIA');
      expect(p.cardType, 'CC');
      expect(p.merchantRaw, 'Anthropic');
      expect(p.transactionDate, DateTime(2026, 9, 10));
      expect(p.templateId, 'SCAPIA');
      expect(suggestSmsCategory(p.merchantRaw), 'Subscription');
    });

    test('Cursor Usage Mid Aug + Us', () {
      const body = 'Hi! Your txn of ₹11,170.54 at Cursor Usage Mid Aug + Us '
          'on your Scapia Federal Visa credit card was successful. Not you? '
          'Go to Scapia support on the app.- Federal Bank';
      final p = BankSmsParser.parse(body, smsReceivedAt: received)!;
      expect(p.amount, 11170.54);
      expect(p.bank, 'SCAPIA');
      expect(p.cardType, 'CC');
      expect(p.merchantRaw, 'Cursor Usage Mid Aug');
      expect(suggestSmsCategory(p.merchantRaw), 'Subscription');
    });

    test('Cursor, Ai Powered Ide trailing plus', () {
      const body = 'Hi! Your txn of ₹2,364.93 at Cursor, Ai Powered Ide +  '
          'on your Scapia Federal Visa credit card was successful. Not you? '
          'Go to Scapia support on the app.- Federal Bank';
      final p = BankSmsParser.parse(body, smsReceivedAt: received)!;
      expect(p.amount, 2364.93);
      expect(p.merchantRaw.toLowerCase(), contains('cursor'));
      expect(p.merchantRaw.contains('+'), isFalse);
    });

    test('Anthropic* Claude Sub + U', () {
      const body = 'Hi! Your txn of ₹2,399.00 at Anthropic* Claude Sub + U '
          'on your Scapia Federal Visa credit card was successful. Not you? '
          'Go to Scapia support on the app.- Federal Bank';
      final p = BankSmsParser.parse(body, smsReceivedAt: received)!;
      expect(p.amount, 2399);
      expect(p.merchantRaw.toLowerCase(), contains('anthropic'));
      expect(p.merchantRaw.toLowerCase(), contains('claude'));
      expect(suggestSmsCategory(p.merchantRaw), 'Subscription');
    });

    test('rewards SMS is still a completed txn', () {
      const body = 'Your txn of ₹6,840.00 at Scapia on your Scapia Federal '
          'Visa credit card earned you 20% rewards! Not you? Call '
          '18002961199. - Federal Bank';
      final p = BankSmsParser.parse(body, smsReceivedAt: received)!;
      expect(p.amount, 6840);
      expect(p.bank, 'SCAPIA');
      expect(p.cardType, 'CC');
      expect(p.merchantRaw, 'Scapia');
    });

    test('Google Play with 10% rewards still logs', () {
      const body = "Hi! Your txn of ₹1,950.00 at Google Play on your Scapia "
          'Federal Visa credit card was successful. And you\'ve earned 10% '
          'rewards on this spend! Not you? Go to Scapia support on the app '
          'or call 18002961199. -Federal Bank';
      final p = BankSmsParser.parse(body, smsReceivedAt: received)!;
      expect(p.amount, 1950);
      expect(p.merchantRaw, 'Google Play');
      expect(suggestSmsCategory(p.merchantRaw), 'Subscription');
    });

    test('live miss ₹791.32 Anthropic is a Scapia CC debit', () {
      const body = 'Hi! Your txn of ₹791.32 at Anthropic + Us on your '
          'Scapia Federal Visa credit card was successful. Not you? '
          'Go to Scapia support on the app.- Federal Bank';
      final p = BankSmsParser.parse(
        body,
        smsReceivedAt: received,
        sender: 'VM-FEDBNK',
      )!;
      expect(p.amount, 791.32);
      expect(p.bank, 'SCAPIA');
      expect(p.cardType, 'CC');
      expect(p.instrument, 'CREDIT_CARD');
      expect(p.merchantRaw, 'Anthropic');
      expect(p.templateId, 'SCAPIA');
      expect(suggestSmsCategory(p.merchantRaw), 'Subscription');
    });

    test('live miss ₹565.23 Anthropic is a Scapia CC debit', () {
      const body = 'Hi! Your txn of ₹565.23 at Anthropic + Us on your '
          'Scapia Federal Visa credit card was successful. Not you? '
          'Go to Scapia support on the app.- Federal Bank';
      final p = BankSmsParser.parse(body, smsReceivedAt: received)!;
      expect(p.amount, 565.23);
      expect(p.bank, 'SCAPIA');
      expect(p.cardType, 'CC');
      expect(p.merchantRaw, 'Anthropic');
      expect(p.templateId, 'SCAPIA');
      expect(suggestSmsCategory(p.merchantRaw), 'Subscription');
    });

    test('Rs. prefix still matches the Scapia template', () {
      const body = 'Hi! Your txn of Rs.791.32 at Anthropic + Us on your '
          'Scapia Federal Visa credit card was successful. Not you? '
          'Go to Scapia support on the app.- Federal Bank';
      final p = BankSmsParser.parse(body, smsReceivedAt: received)!;
      expect(p.amount, 791.32);
      expect(p.templateId, 'SCAPIA');
      expect(p.merchantRaw, 'Anthropic');
    });

    test('INR prefix still matches the Scapia template', () {
      const body = 'Hi! Your txn of INR 565.23 at Anthropic + Us on your '
          'Scapia Federal Visa credit card was successful. Not you? '
          'Go to Scapia support on the app.- Federal Bank';
      final p = BankSmsParser.parse(body, smsReceivedAt: received)!;
      expect(p.amount, 565.23);
      expect(p.templateId, 'SCAPIA');
    });

    test('NBSP after rupee still matches', () {
      const body = 'Hi! Your txn of \u20b9\u00a0791.32 at Anthropic + Us on your '
          'Scapia Federal Visa credit card was successful. Not you? '
          'Go to Scapia support on the app.- Federal Bank';
      final p = BankSmsParser.parse(body, smsReceivedAt: received)!;
      expect(p.amount, 791.32);
      expect(p.templateId, 'SCAPIA');
      expect(p.merchantRaw, 'Anthropic');
    });

    test('newline before on your Scapia still matches', () {
      const body = 'Hi! Your txn of ₹791.32 at Anthropic + Us\n'
          'on your Scapia Federal Visa credit card was successful. Not you? '
          'Go to Scapia support on the app.- Federal Bank';
      final p = BankSmsParser.parse(body, smsReceivedAt: received)!;
      expect(p.amount, 791.32);
      expect(p.templateId, 'SCAPIA');
      expect(p.merchantRaw, 'Anthropic');
    });

    test('UCS-2 first segment without credit card still matches', () {
      const body =
          'Hi! Your txn of ₹791.32 at Anthropic + Us on your Scapia Federal Visa cr';
      final p = BankSmsParser.parse(body, smsReceivedAt: received)!;
      expect(p.amount, 791.32);
      expect(p.templateId, 'SCAPIA');
      expect(p.merchantRaw, 'Anthropic');
    });

    test('RuPay network is still a Scapia debit', () {
      const body = 'Hi! Your txn of ₹565.23 at Anthropic + Us on your '
          'Scapia Federal RuPay credit card was successful. Not you? '
          'Go to Scapia support on the app.- Federal Bank';
      final p = BankSmsParser.parse(body, smsReceivedAt: received)!;
      expect(p.amount, 565.23);
      expect(p.templateId, 'SCAPIA');
      expect(p.cardType, 'CC');
    });

    test('card payment received is not a spend', () {
      const body = "Yay! We've received your payment of ₹791.32 towards your "
          'Scapia Federal credit card. -Federal Bank';
      expect(BankSmsParser.parse(body, smsReceivedAt: received), isNull);
    });

    test('numeric or blank sender is accepted from the Scapia body', () {
      const body = 'Hi! Your txn of ₹791.32 at Anthropic + Us on your '
          'Scapia Federal Visa credit card was successful. Not you? '
          'Go to Scapia support on the app.- Federal Bank';
      expect(smsShouldAccept('+919840012345', body), isTrue);
      expect(smsShouldAccept('', body), isTrue);
      expect(smsShouldAccept('+919840012345', 'Dinner at 8?'), isFalse);
      expect(isBankSender('AX-FEDADV'), isTrue);
      expect(isBankSender('VM-FDRLBN'), isTrue);
    });
  });

  group('HDFC extra shapes from the same inbox', () {
    test('T4 debit card Amazon with two spaces after BLOCK DC', () {
      const body = 'Spent Rs.154.99 From HDFC Bank Card x3805 At WWW AMAZON IN '
          'On 2026-09-07:21:46:51 Bal Rs.66873.52 Not You? Call 18002586161/'
          'SMS BLOCK DC  3805 to 7308080808';
      final p = BankSmsParser.parse(body, smsReceivedAt: received)!;
      expect(p.amount, 154.99);
      expect(p.bank, 'HDFC');
      expect(p.cardType, 'DB');
      expect(p.instrument, 'DEBIT_CARD');
      expect(p.instrumentLast4, '3805');
      expect(p.transactionDate, DateTime(2026, 9, 7));
    });

    test('T1 person transfer is Personal', () {
      const body = 'Sent Rs.25000.00\n'
          'From HDFC Bank A/C *7372\n'
          'To C M SARADHA MATHI\n'
          'On 29/08/26\n'
          'Ref 720432052416\n'
          'Not You?\n'
          'Call 18002586161/SMS BLOCK UPI to 7308080808';
      final p = BankSmsParser.parse(body, smsReceivedAt: received)!;
      expect(p.amount, 25000);
      expect(p.bank, 'HDFC');
      expect(p.cardType, 'DB');
      expect(p.merchantRaw, 'C M Saradha Mathi');
      expect(p.transactionDate, DateTime(2026, 8, 29));
      expect(suggestSmsCategory(p.merchantRaw), 'Personal');
    });

    test('T8 a/c debit to another a/c is UPI Transfer', () {
      const body = 'HDFC Bank:Rs. 589.00 debited from a/c *7372 on 27/08/26 '
          'to a/c **8640 (UPI Ref No. 233824882396). Not you? Call on '
          '18002586161 to report';
      final p = BankSmsParser.parse(body, smsReceivedAt: received)!;
      expect(p.amount, 589);
      expect(p.bank, 'HDFC');
      expect(p.cardType, 'DB');
      expect(p.instrument, 'BANK_ACCOUNT');
      expect(p.instrumentLast4, '7372');
      expect(p.merchantRaw, 'UPI Transfer');
      expect(p.transactionDate, DateTime(2026, 8, 27));
      expect(p.templateId, 'T8');
    });

    test('T2 Paytm VPA on credit card', () {
      const body = 'Txn Rs.165.00\n'
          'On HDFC Bank Card 5901\n'
          'At paytm.s1dedqv@pty \n'
          'by UPI 757980182386\n'
          'On 26-08\n'
          'Not You?\n'
          'Call 18002586161/SMS BLOCK CC 5901 to 7308080808';
      final p = BankSmsParser.parse(body, smsReceivedAt: received)!;
      expect(p.amount, 165);
      expect(p.merchantRaw, 'Paytm');
      expect(p.cardType, 'CC');
      expect(p.instrumentLast4, '5901');
      expect(p.transactionDate, DateTime(2026, 8, 26));
    });

    test('T3 Apollo pharmacy', () {
      const body = 'Spent Rs.1008.66 On HDFC Bank Card 5901 At '
          'ApolloPharmaciesLtd On 2026-08-12:20:46:21.Not You? To '
          'Block+Reissue Call 18002586161/SMS BLOCK CC 5901 to 7308080808';
      final p = BankSmsParser.parse(body, smsReceivedAt: received)!;
      expect(p.amount, 1008.66);
      expect(p.bank, 'HDFC');
      expect(p.cardType, 'CC');
      expect(p.merchantRaw.toLowerCase(), contains('apollo'));
      expect(suggestSmsCategory(p.merchantRaw), 'Medical');
    });
  });

  group('receiver pipeline: Axis + ICICI + Scapia still classify', () {
    test('every original card sample passes sender gate then dedicated template',
        () {
      const samples = <Map<String, Object>>[
        {
          'sender': 'AX-AXISBK',
          'body':
              'Spent INR 4173.16\nAxis Bank Card no. XX7159\n15-08-26 13:44:31 IST\nBharat Petr\nAvl Limit: INR 57827.35\nNot you? SMS BLOCK 7159 to 919951860002',
          'amount': 4173.16,
          'bank': 'AXIS',
          'template': 'AXIS',
          'merchant': 'Bharat Petr',
          'category': 'Fuel',
          'last4': '7159',
        },
        {
          'sender': 'AX-AXISBK',
          'body':
              'Spent INR 3790.37\nAxis Bank Card no. XX7159\n19-06-26 15:37:26 IST\nSTAR FUEL S\nAvl Limit: INR 50884.25\nNot you? SMS BLOCK 7159 to 919951860002',
          'amount': 3790.37,
          'bank': 'AXIS',
          'template': 'AXIS',
          'merchant': 'Star Fuel S',
          'category': 'Fuel',
          'last4': '7159',
        },
        {
          'sender': 'VM-ICICIB',
          'body':
              'Rs 8,153.00 spent on ICICI Bank Card XX7003 on 09-Sep-26 at AMAZON PAY IN E. Avl Lmt: Rs 17,02,098.21. To dispute, call 18002662/SMS BLOCK 7003 to 9215676766.',
          'amount': 8153.0,
          'bank': 'ICICI',
          'template': 'ICICI',
          'merchantHas': 'amazon',
          'category': 'Shopping',
          'last4': '7003',
        },
        {
          'sender': 'VM-ICICIB',
          'body':
              'INR 1,004.00 spent using ICICI Bank Card XX7003 on 01-Sep-26 on AMAZON PAY IN E. Avl Limit: INR 17,10,251.21. If not you, call 1800 2662/SMS BLOCK 7003 to 9215676766.',
          'amount': 1004.0,
          'bank': 'ICICI',
          'template': 'ICICI',
          'merchantHas': 'amazon',
          'category': 'Shopping',
          'last4': '7003',
        },
        {
          'sender': 'VM-ICICIB',
          'body':
              'Rs 18,525.84 spent on ICICI Bank Card XX7003 on 15-Aug-26 at AMAZON PAY IN E. Avl Lmt: Rs 16,76,317.21. To dispute, call 18002662/SMS BLOCK 7003 to 9215676766.',
          'amount': 18525.84,
          'bank': 'ICICI',
          'template': 'ICICI',
          'merchantHas': 'amazon',
          'category': 'Shopping',
          'last4': '7003',
        },
        {
          'sender': 'VM-FEDBNK',
          'body':
              'Hi! Your txn of ₹791.32 at Anthropic + Us on your Scapia Federal Visa credit card was successful. Not you? Go to Scapia support on the app.- Federal Bank',
          'amount': 791.32,
          'bank': 'SCAPIA',
          'template': 'SCAPIA',
          'merchant': 'Anthropic',
          'category': 'Subscription',
        },
        {
          'sender': 'VM-FEDBNK',
          'body':
              'Hi! Your txn of ₹565.23 at Anthropic + Us on your Scapia Federal Visa credit card was successful. Not you? Go to Scapia support on the app.- Federal Bank',
          'amount': 565.23,
          'bank': 'SCAPIA',
          'template': 'SCAPIA',
          'merchant': 'Anthropic',
          'category': 'Subscription',
        },
      ];

      for (final s in samples) {
        final body = s['body']! as String;
        final sender = s['sender']! as String;
        expect(smsShouldAccept(sender, body), isTrue, reason: sender);
        expect(smsShouldAccept('+919000000000', body), isTrue, reason: body);
        final p = BankSmsParser.parse(
          body,
          smsReceivedAt: received,
          sender: sender,
        );
        expect(p, isNotNull, reason: body);
        expect(p!.amount, s['amount']);
        expect(p.bank, s['bank']);
        expect(p.cardType, 'CC');
        expect(p.instrument, 'CREDIT_CARD');
        expect(p.templateId, s['template']);
        if (s['last4'] != null) {
          expect(p.instrumentLast4, s['last4']);
        }
        if (s['merchant'] != null) {
          expect(p.merchantRaw, s['merchant']);
        }
        if (s['merchantHas'] != null) {
          expect(p.merchantRaw.toLowerCase(), contains(s['merchantHas']));
        }
        expect(suggestSmsCategory(p.merchantRaw), s['category']);
      }
    });

    test('Axis collect request still never logs', () {
      const body = 'Axis Bank: Collect request of INR 1,933.00 sent by '
          'DIGITALAGERETAILPRIVATECA. Accept in your UPI app.';
      expect(isBankSender('AX-AXISBK'), isTrue);
      expect(
        BankSmsParser.parse(body, smsReceivedAt: received, sender: 'AX-AXISBK'),
        isNull,
      );
    });
  });

  group('Federal sender IDs', () {
    test('FEDBNK is a bank sender', () {
      expect(isBankSender('VM-FEDBNK'), isTrue);
      expect(isBankSender('AD-FEDBNK'), isTrue);
      expect(isBankSender('AX-FEDADV'), isTrue);
      expect(isBankSender('VM-FDRLBN'), isTrue);
    });
  });
}
