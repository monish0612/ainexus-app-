import 'package:flutter_test/flutter_test.dart';

import 'package:ai_nexus/data/services/sms_auto_expense/sms_merchant_category.dart';

void main() {
  test('Swiggy / Amazon / medical aliases', () {
    expect(suggestSmsCategory('SWIGGY ADD MONEY'), 'Food');
    expect(suggestSmsCategory('WWW AMAZON IN'), 'Shopping');
    expect(suggestSmsCategory('Sundaram Medical'), 'Medical');
    expect(suggestSmsCategory('GOOGLECLOUD'), 'Subscription');
    expect(suggestSmsCategory('NOBROKER TECHNOLOGIES'), 'Rent');
  });

  test('learned VPA label wins over aliases', () {
    expect(
      suggestSmsCategory(
        'Q227400652@ybl',
        labels: {'Q227400652@ybl': 'Grocery'},
      ),
      'Grocery',
    );
  });

  test('empty and unknown UPI fall back to Others', () {
    expect(suggestSmsCategory(''), 'Others');
    expect(suggestSmsCategory('Q227400652@ybl'), 'Others');
  });

  test('gym stays Health; medical merchants are Medical', () {
    expect(suggestSmsCategory('Cult Fit'), 'Health');
    expect(suggestSmsCategory('Sundaram Medical'), 'Medical');
    expect(suggestSmsCategory('City Hospital Chennai'), 'Medical');
    expect(suggestSmsCategory('Apollopharmaciesltd'), 'Medical');
  });

  test('FirstCry email VPA is Family', () {
    expect(suggestSmsCategory('email@firstcry.com'), 'Family');
  });

  test('Swiggy Instamart is Grocery not Food', () {
    expect(suggestSmsCategory('SWIGGY INSTAMART'), 'Grocery');
  });

  test('Amazon IRCTC is Travel', () {
    expect(suggestSmsCategory('AMAZON IRCTC'), 'Travel');
  });

  test('person names become Personal', () {
    expect(suggestSmsCategory('B. Kamalakannan'), 'Personal');
    expect(suggestSmsCategory('C M Saradha Mathi'), 'Personal');
  });

  test('fuel / subscription / apollo aliases', () {
    expect(suggestSmsCategory('Bharat Petr'), 'Fuel');
    expect(suggestSmsCategory('Star Fuel S'), 'Fuel');
    expect(suggestSmsCategory('Anthropic'), 'Subscription');
    expect(suggestSmsCategory('Cursor Usage Mid Aug'), 'Subscription');
    expect(suggestSmsCategory('Google Play'), 'Subscription');
    expect(suggestSmsCategory('Apollopharmaciesltd'), 'Medical');
    expect(suggestSmsCategory('UPI Transfer'), 'Others');
  });
}
