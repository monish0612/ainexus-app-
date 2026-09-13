import 'package:flutter_test/flutter_test.dart';

import 'package:ai_nexus/data/services/sms_auto_expense/sms_models.dart';
import 'package:ai_nexus/data/services/sms_auto_expense/sms_merchant_category.dart';
import 'package:ai_nexus/data/services/sms_auto_expense/sms_parser.dart';

void main() {
  test('queue JSON survives int timestamps and string amounts', () {
    final item = SmsPendingItem.fromJson({
      'id': 'abc',
      'sender': 'JM-HDFCBK',
      'amount': '282.00',
      'merchantRaw': 'Scapia',
      'instrument': 'BANK_ACCOUNT',
      'transactionDate': 1757000000000,
      'bank': 'HDFC',
      'cardType': 'DB',
      'receivedAt': 1757000000000,
      'status': 'pending',
    });
    expect(item.id, 'abc');
    expect(item.debit.amount, 282);
    final expected = DateTime.fromMillisecondsSinceEpoch(1757000000000);
    expect(item.debit.transactionDate, DateTime(expected.year, expected.month, expected.day));
    expect(item.debit.hasMerchant, isTrue);
  });

  test('unknown merchant copy is Others + Auto Detected description', () {
    const stampAt = 1757000000000;
    final stamp = autoDetectedStamp(
      DateTime.fromMillisecondsSinceEpoch(stampAt),
    );
    final category = suggestSmsCategory('');
    expect(category, 'Others');
    expect(stamp, contains('Auto Detected'));
  });

  test('opaque VPA stays Others until labeled', () {
    expect(suggestSmsCategory('Q227400652@ybl'), 'Others');
  });
}
