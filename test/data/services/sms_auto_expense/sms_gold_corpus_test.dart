import 'package:ai_nexus/data/services/sms_auto_expense/sms_merchant_category.dart';
import 'package:ai_nexus/data/services/sms_auto_expense/sms_models.dart';
import 'package:ai_nexus/data/services/sms_auto_expense/sms_parser.dart';
import 'package:flutter_test/flutter_test.dart';

/// Full live path for one SMS: receiver gate (DLT + numeric + blank) then parse.
void expectLiveDebit(
  String body, {
  required String dltSender,
  required double amount,
  required String bank,
  required String cardType,
  required String template,
  required String category,
  String? merchant,
  String? merchantHas,
  String? last4,
  String? instrument,
  DateTime? date,
  required int received,
}) {
  expect(smsShouldAccept(dltSender, body), isTrue, reason: 'DLT $dltSender');
  expect(smsShouldAccept('+919000000000', body), isTrue, reason: 'numeric');
  expect(smsShouldAccept('', body), isTrue, reason: 'blank sender');
  final p = BankSmsParser.parse(
    body,
    smsReceivedAt: received,
    sender: dltSender,
  );
  expect(p, isNotNull, reason: body);
  expect(p!.amount, amount);
  expect(p.bank, bank);
  expect(p.cardType, cardType);
  expect(p.templateId, template);
  if (instrument != null) expect(p.instrument, instrument);
  if (last4 != null) expect(p.instrumentLast4, last4);
  if (merchant != null) expect(p.merchantRaw, merchant);
  if (merchantHas != null) {
    expect(p.merchantRaw.toLowerCase(), contains(merchantHas));
  }
  if (date != null) expect(p.transactionDate, date);
  expect(suggestSmsCategory(p.merchantRaw), category);
  expect(
    BankSmsParser.reconcileQueued(p, smsReceivedAt: received, sender: dltSender),
    isNotNull,
  );
}

void main() {
  final received = DateTime(2026, 9, 10, 11, 26).millisecondsSinceEpoch;

  group('gold corpus — original Axis / ICICI / Scapia / HDFC inbox', () {
    test('Axis Bharat Petr 4173.16', () {
      expectLiveDebit(
        'Spent INR 4173.16\n'
        'Axis Bank Card no. XX7159\n'
        '15-08-26 13:44:31 IST\n'
        'Bharat Petr\n'
        'Avl Limit: INR 57827.35\n'
        'Not you? SMS BLOCK 7159 to 919951860002',
        dltSender: 'AX-AXISBK',
        amount: 4173.16,
        bank: 'AXIS',
        cardType: 'CC',
        template: 'AXIS',
        category: 'Fuel',
        merchant: 'Bharat Petr',
        last4: '7159',
        instrument: 'CREDIT_CARD',
        date: DateTime(2026, 8, 15),
        received: received,
      );
    });

    test('Axis STAR FUEL S 3790.37', () {
      expectLiveDebit(
        'Spent INR 3790.37\n'
        'Axis Bank Card no. XX7159\n'
        '19-06-26 15:37:26 IST\n'
        'STAR FUEL S\n'
        'Avl Limit: INR 50884.25\n'
        'Not you? SMS BLOCK 7159 to 919951860002',
        dltSender: 'AD-AXISBK',
        amount: 3790.37,
        bank: 'AXIS',
        cardType: 'CC',
        template: 'AXIS',
        category: 'Fuel',
        merchant: 'Star Fuel S',
        last4: '7159',
        date: DateTime(2026, 6, 19),
        received: received,
      );
    });

    test('ICICI Amazon 8153.00 Indian grouping', () {
      expectLiveDebit(
        'Rs 8,153.00 spent on ICICI Bank Card XX7003 on 09-Sep-26 '
        'at AMAZON PAY IN E. Avl Lmt: Rs 17,02,098.21. To dispute, call '
        '18002662/SMS BLOCK 7003 to 9215676766.',
        dltSender: 'VM-ICICIB',
        amount: 8153,
        bank: 'ICICI',
        cardType: 'CC',
        template: 'ICICI',
        category: 'Shopping',
        merchantHas: 'amazon',
        last4: '7003',
        date: DateTime(2026, 9, 9),
        received: received,
      );
    });

    test('ICICI Amazon 1004.00 spent using', () {
      expectLiveDebit(
        'INR 1,004.00 spent using ICICI Bank Card XX7003 on 01-Sep-26 '
        'on AMAZON PAY IN E. Avl Limit: INR 17,10,251.21. If not you, call '
        '1800 2662/SMS BLOCK 7003 to 9215676766.',
        dltSender: 'AX-ICICIT',
        amount: 1004,
        bank: 'ICICI',
        cardType: 'CC',
        template: 'ICICI',
        category: 'Shopping',
        merchantHas: 'amazon',
        last4: '7003',
        date: DateTime(2026, 9, 1),
        received: received,
      );
    });

    test('ICICI Amazon 18525.84', () {
      expectLiveDebit(
        'Rs 18,525.84 spent on ICICI Bank Card XX7003 on 15-Aug-26 '
        'at AMAZON PAY IN E. Avl Lmt: Rs 16,76,317.21.',
        dltSender: 'AD-ICICIB',
        amount: 18525.84,
        bank: 'ICICI',
        cardType: 'CC',
        template: 'ICICI',
        category: 'Shopping',
        merchantHas: 'amazon',
        last4: '7003',
        date: DateTime(2026, 8, 15),
        received: received,
      );
    });

    test('Scapia live miss 791.32 Anthropic', () {
      expectLiveDebit(
        'Hi! Your txn of ₹791.32 at Anthropic + Us on your '
        'Scapia Federal Visa credit card was successful. Not you? '
        'Go to Scapia support on the app.- Federal Bank',
        dltSender: 'VM-FEDBNK',
        amount: 791.32,
        bank: 'SCAPIA',
        cardType: 'CC',
        template: 'SCAPIA',
        category: 'Subscription',
        merchant: 'Anthropic',
        instrument: 'CREDIT_CARD',
        received: received,
      );
    });

    test('Scapia live miss 565.23 Anthropic', () {
      expectLiveDebit(
        'Hi! Your txn of ₹565.23 at Anthropic + Us on your '
        'Scapia Federal Visa credit card was successful. Not you? '
        'Go to Scapia support on the app.- Federal Bank',
        dltSender: 'JD-FEDBNK',
        amount: 565.23,
        bank: 'SCAPIA',
        cardType: 'CC',
        template: 'SCAPIA',
        category: 'Subscription',
        merchant: 'Anthropic',
        received: received,
      );
    });

    test('Scapia Cursor 11170.54', () {
      expectLiveDebit(
        'Hi! Your txn of ₹11,170.54 at Cursor Usage Mid Aug + Us on your '
        'Scapia Federal Visa credit card was successful. Not you? '
        'Go to Scapia support on the app.- Federal Bank',
        dltSender: 'VM-FEDBNK',
        amount: 11170.54,
        bank: 'SCAPIA',
        cardType: 'CC',
        template: 'SCAPIA',
        category: 'Subscription',
        merchant: 'Cursor Usage Mid Aug',
        received: received,
      );
    });

    test('Scapia Google Play 1950 with rewards', () {
      expectLiveDebit(
        "Hi! Your txn of ₹1,950.00 at Google Play on your Scapia "
        'Federal Visa credit card was successful. And you\'ve earned 10% '
        'rewards on this spend! Not you? Go to Scapia support on the app '
        'or call 18002961199. -Federal Bank',
        dltSender: 'AD-FEDBNK',
        amount: 1950,
        bank: 'SCAPIA',
        cardType: 'CC',
        template: 'SCAPIA',
        category: 'Subscription',
        merchant: 'Google Play',
        received: received,
      );
    });

    test('HDFC T4 debit card Amazon 154.99', () {
      expectLiveDebit(
        'Spent Rs.154.99 From HDFC Bank Card x3805 At WWW AMAZON IN '
        'On 2026-09-07:21:46:51 Bal Rs.66873.52 Not You? Call 18002586161/'
        'SMS BLOCK DC  3805 to 7308080808',
        dltSender: 'JM-HDFCBK',
        amount: 154.99,
        bank: 'HDFC',
        cardType: 'DB',
        template: 'T3',
        category: 'Shopping',
        last4: '3805',
        instrument: 'DEBIT_CARD',
        date: DateTime(2026, 9, 7),
        received: received,
      );
    });

    test('HDFC T1 person transfer 25000', () {
      expectLiveDebit(
        'Sent Rs.25000.00\nFrom HDFC Bank A/C *7372\nTo C M SARADHA MATHI\n'
        'On 29/08/26\nRef 720432052416\nNot You?\n'
        'Call 18002586161/SMS BLOCK UPI to 7308080808',
        dltSender: 'AD-HDFCBK',
        amount: 25000,
        bank: 'HDFC',
        cardType: 'DB',
        template: 'T1',
        category: 'Personal',
        merchant: 'C M Saradha Mathi',
        last4: '7372',
        date: DateTime(2026, 8, 29),
        received: received,
      );
    });

    test('HDFC T8 a/c debit 589', () {
      expectLiveDebit(
        'HDFC Bank:Rs. 589.00 debited from a/c *7372 on 27/08/26 '
        'to a/c **8640 (UPI Ref No. 233824882396). Not you? Call on '
        '18002586161 to report',
        dltSender: 'JM-HDFCBK',
        amount: 589,
        bank: 'HDFC',
        cardType: 'DB',
        template: 'T8',
        category: 'Others',
        merchant: 'UPI Transfer',
        last4: '7372',
        date: DateTime(2026, 8, 27),
        received: received,
      );
    });

    test('HDFC T2 Paytm VPA 165', () {
      expectLiveDebit(
        'Txn Rs.165.00\nOn HDFC Bank Card 5901\nAt paytm.s1dedqv@pty \n'
        'by UPI 757980182386\nOn 26-08\nNot You?\n'
        'Call 18002586161/SMS BLOCK CC 5901 to 7308080808',
        dltSender: 'VM-HDFCBK',
        amount: 165,
        bank: 'HDFC',
        cardType: 'CC',
        template: 'T2',
        category: 'Others',
        merchant: 'Paytm',
        last4: '5901',
        date: DateTime(2026, 8, 26),
        received: received,
      );
    });

    test('HDFC T3 Apollo 1008.66', () {
      expectLiveDebit(
        'Spent Rs.1008.66 On HDFC Bank Card 5901 At ApolloPharmaciesLtd '
        'On 2026-08-12:20:46:21.Not You? To Block+Reissue Call 18002586161/'
        'SMS BLOCK CC 5901 to 7308080808',
        dltSender: 'JM-HDFCBK',
        amount: 1008.66,
        bank: 'HDFC',
        cardType: 'CC',
        template: 'T3',
        category: 'Medical',
        merchantHas: 'apollo',
        last4: '5901',
        date: DateTime(2026, 8, 12),
        received: received,
      );
    });
  });

  group('gold corpus — must never log', () {
    test('Axis collect request', () {
      const body = 'Axis Bank: Collect request of INR 1,933.00 sent by '
          'DIGITALAGERETAILPRIVATECA. Accept in your UPI app.';
      expect(isBankSender('AX-AXISBK'), isTrue);
      expect(
        BankSmsParser.parse(body, smsReceivedAt: received, sender: 'AX-AXISBK'),
        isNull,
      );
    });

    test('HDFC payment request', () {
      expect(
        BankSmsParser.parse(
          'HDFC Bank: You have received a payment request of Rs.1933.00 '
          'from DIGITALAGERETAILPRIVATECA. Approve using UPI PIN.',
          smsReceivedAt: received,
        ),
        isNull,
      );
    });

    test('E-Mandate future notice', () {
      expect(
        BankSmsParser.parse(
          'E-Mandate!\nRs.95.70 will be deducted on 03/08/26, 00:00:00\n'
          'For GOOGLECLOUD mandate',
          smsReceivedAt: received,
        ),
        isNull,
      );
    });

    test('OTP HDFC and ICICI', () {
      expect(
        BankSmsParser.parse(
          'HDFC Bank: 482911 is your OTP. Do not share with anyone.',
          smsReceivedAt: received,
        ),
        isNull,
      );
      expect(
        BankSmsParser.parse(
          'ICICI Bank: 482911 is your OTP. Do not share with anyone.',
          smsReceivedAt: received,
          sender: 'VM-ICICIB',
        ),
        isNull,
      );
    });

    test('credit and Scapia card payment received', () {
      expect(
        BankSmsParser.parse(
          'Rs.50000.00 credited to HDFC Bank A/C *7372',
          smsReceivedAt: received,
        ),
        isNull,
      );
      expect(
        BankSmsParser.parse(
          "Yay! We've received your payment of ₹791.32 towards your "
          'Scapia Federal credit card. -Federal Bank',
          smsReceivedAt: received,
        ),
        isNull,
      );
    });

    test('declined spend', () {
      expect(
        BankSmsParser.parse(
          'Spent Rs.1933 On HDFC Bank Card 5901 At DIGITALAGE '
          'On 2026-09-11:12:00:00. Declined. Insufficient funds.',
          smsReceivedAt: received,
        ),
        isNull,
      );
    });

    test('personal chat is not a bank debit', () {
      expect(smsShouldAccept('+919840012345', 'Dinner at 8?'), isFalse);
      expect(
        BankSmsParser.parse('Dinner at 8?', smsReceivedAt: received),
        isNull,
      );
    });
  });

  group('gold corpus — hostile live variants still classify', () {
    test('Axis CRLF + Rs prefix + Card no without extra period', () {
      const body = 'Spent Rs.4173.16\r\nAxis Bank Card no XX7159\r\n'
          '15-08-26 13:44:31 IST\r\nBharat Petr\r\nAvl Limit: INR 57827.35';
      expectLiveDebit(
        body,
        dltSender: 'AX-AXISBK',
        amount: 4173.16,
        bank: 'AXIS',
        cardType: 'CC',
        template: 'AXIS',
        category: 'Fuel',
        merchant: 'Bharat Petr',
        last4: '7159',
        received: received,
      );
    });

    test('Scapia NBSP, INR, Rs, truncated UCS-2', () {
      expectLiveDebit(
        'Hi! Your txn of \u20b9\u00a0791.32 at Anthropic + Us on your '
        'Scapia Federal Visa credit card was successful. Not you? '
        'Go to Scapia support on the app.- Federal Bank',
        dltSender: 'VM-FEDBNK',
        amount: 791.32,
        bank: 'SCAPIA',
        cardType: 'CC',
        template: 'SCAPIA',
        category: 'Subscription',
        merchant: 'Anthropic',
        received: received,
      );
      expectLiveDebit(
        'Hi! Your txn of INR 565.23 at Anthropic + Us on your '
        'Scapia Federal Visa credit card was successful. Not you? '
        'Go to Scapia support on the app.- Federal Bank',
        dltSender: 'VM-FEDBNK',
        amount: 565.23,
        bank: 'SCAPIA',
        cardType: 'CC',
        template: 'SCAPIA',
        category: 'Subscription',
        merchant: 'Anthropic',
        received: received,
      );
      expectLiveDebit(
        'Hi! Your txn of Rs.791.32 at Anthropic + Us on your '
        'Scapia Federal Visa credit card was successful. Not you? '
        'Go to Scapia support on the app.- Federal Bank',
        dltSender: 'VM-FEDBNK',
        amount: 791.32,
        bank: 'SCAPIA',
        cardType: 'CC',
        template: 'SCAPIA',
        category: 'Subscription',
        merchant: 'Anthropic',
        received: received,
      );
      expectLiveDebit(
        'Hi! Your txn of ₹791.32 at Anthropic + Us on your Scapia Federal Visa cr',
        dltSender: 'VM-FEDBNK',
        amount: 791.32,
        bank: 'SCAPIA',
        cardType: 'CC',
        template: 'SCAPIA',
        category: 'Subscription',
        merchant: 'Anthropic',
        received: received,
      );
    });

    test('queued Axis and Scapia survive reconcile', () {
      const axisBody = 'Spent INR 4173.16\nAxis Bank Card no. XX7159\n'
          '15-08-26 13:44:31 IST\nBharat Petr\nAvl Limit: INR 57827.35';
      final stale = ParsedSmsDebit(
        amount: 4173.16,
        merchantRaw: 'Bharat Petr',
        instrument: 'CREDIT_CARD',
        instrumentLast4: '7159',
        transactionDate: DateTime(2026, 8, 15),
        bank: 'AXIS',
        cardType: 'CC',
        templateId: 'GENERIC',
        rawBody: axisBody,
      );
      final p = BankSmsParser.reconcileQueued(
        stale,
        smsReceivedAt: received,
        sender: 'AX-AXISBK',
      )!;
      expect(p.templateId, 'AXIS');
      expect(p.amount, 4173.16);
    });
  });
}
