// Unit tests for the offline bank/card transaction-SMS parser used as the
// fallback when text is shared into the Expense scanner and the LLM
// smart-parse is unavailable. Exercises the exact alert formats the user
// shares (HDFC card spends, Axis fuel, HDFC UPI transfer, UPI VPA payments)
// so amount/merchant/bank/card-type are recovered without a network call.

import 'package:flutter_test/flutter_test.dart';

import 'package:ai_nexus/presentation/screens/expense/modals/add_expense_modal.dart';

void main() {
  group('parseBankTransactionSms', () {
    test('sample 1 — HDFC card UPI to a Paytm VPA', () {
      final r = parseBankTransactionSms(
        'Txn Rs.30.00\nOn HDFC Bank Card 5901\nAt paytm.s29gayk@pty \n'
        'by UPI 420791991766\nOn 25-06\nNot You?\n'
        'Call 18002586161/SMS BLOCK CC 5901 to 7308080808',
      );
      expect(r.amount, '30');
      expect(r.bank, 'HDFC');
      expect(r.cardType, 'CC');
      expect(r.description, 'Paytm');
    });

    test('sample 2 — HDFC A/C UPI transfer to a person', () {
      final r = parseBankTransactionSms(
        'Sent Rs.350.00\nFrom HDFC Bank A/C *7372\nTo B . KAMALAKANNAN\n'
        'On 24/06/26\nRef 205356511756\nNot You?\n'
        'Call 18002586161/SMS BLOCK UPI to 7308080808',
      );
      expect(r.amount, '350');
      expect(r.bank, 'HDFC');
      // A/C + UPI transfer (no credit card) → DB.
      expect(r.cardType, 'DB');
      expect(r.description, 'B. Kamalakannan');
    });

    test('sample 3 — HDFC credit card at a glued merchant name', () {
      final r = parseBankTransactionSms(
        'Spent Rs.899 On HDFC Bank Card 5901 At SANWARIATEXPROPRIVATE '
        'On 2026-06-22:18:43:58.Not You? To Block+Reissue '
        'Call 18002586161/SMS BLOCK CC 5901 to 7308080808',
      );
      expect(r.amount, '899');
      expect(r.bank, 'HDFC');
      expect(r.cardType, 'CC');
      expect(r.description, 'Sanwariatexproprivate');
    });

    test('sample 6 — HDFC credit card at a grocery store', () {
      final r = parseBankTransactionSms(
        'Spent Rs.842 On HDFC Bank Card 5901 At SANTHOSH SUPER STORES '
        'On 2026-06-21:19:21:50.Not You? To Block+Reissue '
        'Call 18002586161/SMS BLOCK CC 5901 to 7308080808',
      );
      expect(r.amount, '842');
      expect(r.bank, 'HDFC');
      expect(r.cardType, 'CC');
      expect(r.description, 'Santhosh Super Stores');
    });

    test('sample 7 — decimal amount + multi-word merchant', () {
      final r = parseBankTransactionSms(
        'Spent Rs.317.44 On HDFC Bank Card 5901 At NOBROKER TECHNOLOGIES '
        'On 2026-06-21:19:25:05.Not You? To Block+Reissue '
        'Call 18002586161/SMS BLOCK CC 5901 to 7308080808',
      );
      expect(r.amount, '317'); // rounded to whole rupees for the form
      expect(r.bank, 'HDFC');
      expect(r.cardType, 'CC');
      expect(r.description, 'Nobroker Technologies');
    });

    test('sample 8 — Axis fuel spend, INR + decimal, Avl Limit noise', () {
      final r = parseBankTransactionSms(
        'Spent INR 3790.37\nAxis Bank Card no. XX7159\n19-06-26 15:37:26 IST\n'
        'STAR FUEL S\nAvl Limit: INR 50884.25\n'
        'Not you? SMS BLOCK 7159 to 919951860002 .',
      );
      expect(r.amount, '3790');
      expect(r.bank, 'AXIS');
      // "Card no." with no explicit CC/DC → defaults to DB (a bank is named).
      expect(r.cardType, 'DB');
      // The merchant sits between the timestamp and "Avl Limit"; this template
      // has no "At"/"To" anchor, so the offline parser safely yields no
      // merchant (the LLM handles this case) rather than grabbing the trailing
      // phone number. The amount/bank/card are still recovered.
      expect(r.description, '');
    });
  });

  group('cleanMerchantName', () {
    test('ALL-CAPS → Title Case', () {
      expect(cleanMerchantName('SANTHOSH SUPER STORES'), 'Santhosh Super Stores');
    });

    test('person with spaced initial', () {
      expect(cleanMerchantName('B . KAMALAKANNAN'), 'B. Kamalakannan');
    });

    test('UPI VPA → brand', () {
      expect(cleanMerchantName('paytm.s29gayk@pty'), 'Paytm');
    });

    test('opaque UPI VPA id → generic label', () {
      expect(cleanMerchantName('Q089615363@ybl'), 'UPI Payment');
    });

    test('empty input → empty', () {
      expect(cleanMerchantName('   '), '');
    });
  });
}
