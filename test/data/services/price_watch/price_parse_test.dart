import 'package:ai_nexus/data/services/price_watch/price_parse.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parsePrice', () {
    test('US / IN decimal point', () {
      expect(parsePrice('₹21,799.99'), 21799.99);
      expect(parsePrice('21,799'), 21799);
    });

    test('EU comma decimal', () {
      expect(parsePrice('1.299,99'), 1299.99);
    });

    test('Indian grouping', () {
      expect(parsePrice('17,02,098.21'), 1702098.21);
    });

    test('plain integer and rupee prefix', () {
      expect(parsePrice('₹ 2499'), 2499);
      expect(parsePrice('2499.50'), 2499.50);
    });

    test('rejects junk', () {
      expect(parsePrice(null), isNull);
      expect(parsePrice(''), isNull);
      expect(parsePrice('free'), isNull);
      expect(parsePrice('0'), isNull);
      expect(parsePrice('-12'), isNull);
    });
  });

  test('parseAllPrices unique in document order', () {
    expect(parseAllPrices('₹1,999 then ₹1,299 then ₹1,999'), [1999, 1299]);
  });

  group('formatInr', () {
    test('whole rupees use Indian grouping', () {
      expect(formatInr(2499), '₹ 2,499');
      expect(formatInr(1702098), '₹ 17,02,098');
    });

    test('paise kept', () {
      expect(formatInr(2499.5), '₹ 2,499.50');
    });
  });
}
