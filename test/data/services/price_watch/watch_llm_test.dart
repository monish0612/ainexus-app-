import 'package:ai_nexus/data/services/price_watch/watch_llm.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseWatchLlmResponse', () {
    test('accepts a live offer pinned from Settings Flash JSON', () {
      final hit = parseWatchLlmResponse({
        'isProduct': true,
        'name': 'Sony WH-1000XM5',
        'price': 24990,
        'confidence': 0.86,
        'imageUrl': 'https://img.example/x.jpg',
        'availability': 'IN_STOCK',
      })!;
      expect(hit.price, 24990);
      expect(hit.name, 'Sony WH-1000XM5');
      expect(hit.toHit().source, 'gemini');
      expect(hit.toHit().score, 58);
    });

    test('rejects non-product and missing price — never invents MRP', () {
      expect(
        parseWatchLlmResponse({'isProduct': false, 'name': 'Blog', 'price': 0}),
        isNull,
      );
      expect(
        parseWatchLlmResponse({'isProduct': true, 'name': 'X', 'price': 0}),
        isNull,
      );
      expect(
        parseWatchLlmResponse({'isProduct': true, 'name': '', 'price': 99}),
        isNull,
      );
    });

    test('unwraps extract envelope and INR strings', () {
      final hit = parseWatchLlmResponse({
        'extract': {
          'isProduct': true,
          'name': 'Widget',
          'price': '1,299',
          'confidence': 80,
        },
        'model': 'gemini-3.1-flash-lite-preview',
      });
      expect(hit?.price, 1299);
      expect(hit?.confidence, 0.8);
    });
  });
}
